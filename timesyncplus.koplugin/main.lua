local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")

local TimeSyncPlus = WidgetContainer:extend{
    name = "timesyncplus",
}

local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/timesyncplus.lua"
local DEFAULT_TIMEZONE = "Atlantic/Canary"
local STARTUP_DELAY_SECONDS = 6
local RESUME_DELAY_SECONDS = 12

-- When Wi-Fi is off, the plugin will power it on and give the whole
-- synchronization session up to one minute to connect and sync.
local WIFI_SYNC_TIMEOUT_SECONDS = 60
local WIFI_POLL_INTERVAL_SECONDS = 1
local SYNC_RETRY_INTERVAL_SECONDS = 2

-- Keep individual HTTP requests bounded so a retry cannot run far past
-- the one-minute session deadline.
local CURL_TIMEOUT_SECONDS = 15
local CURL_ARGS = string.format(
    "--fail --silent --show-error --insecure --connect-timeout 8 --max-time %d",
    CURL_TIMEOUT_SECONDS
)

local TIMEZONES = {
    "UTC",
    "Atlantic/Canary",
    "Europe/London",
    "Europe/Madrid",
    "Europe/Paris",
    "Europe/Berlin",
    "America/New_York",
    "America/Chicago",
    "America/Denver",
    "America/Los_Angeles",
    "America/Mexico_City",
    "America/Sao_Paulo",
    "Asia/Dubai",
    "Asia/Kolkata",
    "Asia/Bangkok",
    "Asia/Singapore",
    "Asia/Hong_Kong",
    "Asia/Shanghai",
    "Asia/Seoul",
    "Asia/Tokyo",
    "Australia/Sydney",
    "Pacific/Auckland",
}

local function showMessage(text, timeout)
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = timeout or 3,
    })
end

local function executeOk(command)
    local ok = os.execute(command)
    return ok == true or ok == 0
end

local function readCommand(command)
    local handle = io.popen(command)
    if not handle then
        return nil
    end
    local output = handle:read("*a")
    handle:close()
    return output and output:gsub("^%s+", ""):gsub("%s+$", "") or nil
end

local function getSettings()
    return LuaSettings:open(SETTINGS_FILE)
end

local function isValidTimezone(timezone)
    return timezone and timezone:match("^[%a%d_/%-]+$") ~= nil
end

local function getTimezone()
    local timezone = getSettings():readSetting("timezone")
        or DEFAULT_TIMEZONE
    if isValidTimezone(timezone) then
        return timezone
    end
    return DEFAULT_TIMEZONE
end

local function fetchUrl(url)
    local command = string.format("curl %s '%s' 2>&1", CURL_ARGS, url)
    local handle = io.popen(command)
    if not handle then
        return nil
    end
    local body = handle:read("*a")
    handle:close()
    return body
end

local function parseJsonNumber(json, key)
    local value = json and json:match('"' .. key .. '"%s*:%s*(-?%d+)')
    return value and tonumber(value) or nil
end

local function parseJsonString(json, key)
    return json and json:match('"' .. key .. '"%s*:%s*"([^"]+)"') or nil
end

local function fetchTimezoneTime(timezone)
    local url = "https://timeapi.io/api/Time/current/zone?timeZone=" .. timezone
    local body = fetchUrl(url)
    local date = {
        year = parseJsonNumber(body, "year"),
        month = parseJsonNumber(body, "month"),
        day = parseJsonNumber(body, "day"),
        hour = parseJsonNumber(body, "hour"),
        minute = parseJsonNumber(body, "minute"),
        second = parseJsonNumber(body, "seconds"),
        timezone = parseJsonString(body, "timeZone") or timezone,
    }

    if date.year and date.month and date.day and date.hour and date.minute and date.second then
        return date
    end
    return nil
end

local function formatDateForDateCommand(date)
    return string.format(
        "%04d-%02d-%02d %02d:%02d:%02d",
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second
    )
end

local function formatDateForBusyBox(date)
    return string.format(
        "%02d%02d%02d%02d%04d.%02d",
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.year,
        date.second
    )
end

local function formatLocalMinuteKey(date)
    return string.format(
        "%04d%02d%02d%02d%02d",
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute
    )
end

local function formatDateForMessage(date)
    return string.format(
        "%04d-%02d-%02d %02d:%02d:%02d %s",
        date.year,
        date.month,
        date.day,
        date.hour,
        date.minute,
        date.second,
        date.timezone
    )
end

local function notifyKindleFramework()
    if Device:isKindle() and lfs.attributes("/usr/sbin/setdate", "mode") == "file" then
        executeOk(string.format("/usr/sbin/setdate '%d'", os.time()))
    end
end

local function applyDisplayedTime(date)
    local wall_time = formatDateForDateCommand(date)
    local busybox_time = formatDateForBusyBox(date)
    local expected_local_minute = formatLocalMinuteKey(date)
    local commands = {
        string.format("date -s '%s'", wall_time),
        string.format("date -s '%s'", busybox_time),
        string.format("date '%s'", busybox_time),
    }

    for _, command in ipairs(commands) do
        if executeOk(command) then
            local current_minute = readCommand("date '+%Y%m%d%H%M'")
            if current_minute == expected_local_minute then
                executeOk("hwclock -w")
                notifyKindleFramework()
                return true
            end
        end
    end

    return false
end

-- One actual synchronization attempt. The Wi-Fi/session wrapper below
-- is responsible for retries and the one-minute timeout.
function TimeSyncPlus:syncNow(is_auto)
    if self.sync_running then
        return false
    end
    self.sync_running = true

    if not NetworkMgr:isConnected() then
        self.sync_running = false
        return false
    end

    local timezone = getTimezone()
    local date = fetchTimezoneTime(timezone)
    if not date then
        self.sync_running = false
        return false
    end

    local ok = applyDisplayedTime(date)
    self.sync_running = false

    if not ok then
        return false
    end

    return true, date
end

function TimeSyncPlus:_finishManagedSync(ok, date)
    if not self.sync_session_running then
        return
    end

    local started_wifi_by_plugin = self.sync_wifi_started_by_plugin

    self.sync_session_running = false
    self.sync_wifi_started_by_plugin = false
    self.sync_session_deadline = nil

    -- Only shut Wi-Fi down when this synchronization session turned it on.
    -- interactive=true also clears KOReader's "Wi-Fi was on" restore flag,
    -- so this temporary connection does not become a persistent preference.
    if started_wifi_by_plugin and NetworkMgr:isWifiOn() then
        NetworkMgr:disableWifi(nil, true)
    end

    if self.sync_session_interactive then
        if ok and date then
            showMessage("Time synchronized: " .. formatDateForMessage(date), 4)
        elseif not ok then
            showMessage("Time sync failed: no successful sync within 1 minute")
        end
    end

    self.sync_session_interactive = false
end

function TimeSyncPlus:_scheduleManagedSync(token, delay_seconds)
    UIManager:scheduleIn(delay_seconds, function()
        self:_runManagedSync(token)
    end)
end

function TimeSyncPlus:_runManagedSync(token)
    if not self.sync_session_running or token ~= self.sync_session_token then
        return
    end

    local now = os.time()
    local deadline = self.sync_session_deadline

    -- Do not start a new curl request if there is not enough time left
    -- for the individual request to finish.
    if now >= deadline or now + CURL_TIMEOUT_SECONDS >= deadline then
        self:_finishManagedSync(false)
        return
    end

    if not NetworkMgr:isConnected() then
        self:_scheduleManagedSync(token, WIFI_POLL_INTERVAL_SECONDS)
        return
    end

    local ok, date = self:syncNow(true)
    if ok then
        self:_finishManagedSync(true, date)
        return
    end

    self:_scheduleManagedSync(token, SYNC_RETRY_INTERVAL_SECONDS)
end

function TimeSyncPlus:syncWithTemporaryWifi(is_interactive)
    if self.sync_session_running then
        return false
    end

    self.sync_session_running = true
    self.sync_session_interactive = is_interactive
    self.sync_session_token = (self.sync_session_token or 0) + 1
    local token = self.sync_session_token

    local wifi_was_on = NetworkMgr:isWifiOn()
    self.sync_wifi_started_by_plugin = not wifi_was_on
    self.sync_session_deadline = os.time() + WIFI_SYNC_TIMEOUT_SECONDS

    if not NetworkMgr:isConnected() then
        -- Use KOReader's own network manager so Kindle-specific Wi-Fi
        -- handling, reconnection and NetworkConnected events remain intact.
        local status = NetworkMgr:enableWifi(nil, false)
        if status == false then
            self:_finishManagedSync(false)
            return false
        end
    end

    self:_scheduleManagedSync(token, 0)
    return true
end

function TimeSyncPlus:scheduleAutoSync(delay_seconds)
    if self.auto_sync_scheduled then
        return
    end
    self.auto_sync_scheduled = true

    UIManager:scheduleIn(delay_seconds, function()
        self.auto_sync_scheduled = false
        -- Auto sync now also works with Wi-Fi initially turned off.
        self:syncWithTemporaryWifi(false)
    end)
end

function TimeSyncPlus:onResume()
    self:scheduleAutoSync(RESUME_DELAY_SECONDS)
end

function TimeSyncPlus:init()
    self.ui.menu:registerToMainMenu(self)
    self:scheduleAutoSync(STARTUP_DELAY_SECONDS)
end

function TimeSyncPlus:addToMainMenu(menu_items)
    local timezone_items = {}
    for _, timezone in ipairs(TIMEZONES) do
        table.insert(timezone_items, {
            text = timezone,
            checked_func = function()
                return getTimezone() == timezone
            end,
            callback = function()
                local settings = getSettings()
                settings:saveSetting("timezone", timezone)
                settings:flush()
                self:syncWithTemporaryWifi(true)
            end,
        })
    end

    menu_items.timesyncplus = {
        text = "Time Sync Plus",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Timezone",
                sub_item_table = timezone_items,
            },
            {
                text = "Synchronize now",
                keep_menu_open = true,
                callback = function()
                    self:syncWithTemporaryWifi(true)
                end,
            },
        },
    }
end

return TimeSyncPlus
