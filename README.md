# Time Sync Plus

A KOReader plugin that keeps the Kindle clock aligned to a selected timezone.

The plugin does not trust the Kindle's existing system time. It fetches the current wall-clock time for the selected IANA timezone from `timeapi.io`, writes that displayed time to the device, and syncs again automatically after startup and resume.

## Behavior

* Syncs automatically shortly after KOReader starts.
* Syncs automatically after resume when Wi-Fi is available.
* Lets the user select a timezone once from the KOReader Tools menu.
* Saves the selected timezone in KOReader's settings directory.
* Syncs immediately after a timezone is selected.
* Provides a manual **Synchronize now** command.
* Verifies the system clock after setting it before reporting success.

<<<<<<< HEAD
=======
## Timezone Selection

Open:

`Tools` -> `Time Sync Plus` -> `Timezone`

The default timezone is `Atlantic/Canary`. Major timezone options are included, such as:

* `UTC`
* `Atlantic/Canary`
* `Europe/London`
* `Europe/Madrid`
* `America/New_York`
* `America/Los_Angeles`
* `Asia/Shanghai`
* `Asia/Tokyo`
* `Australia/Sydney`

Once selected, the plugin uses that timezone for automatic startup and resume syncs.

## Why This Version Works Differently

Changing timezone and calculating a true UTC timestamp produces the same instant for every timezone, so the visible clock may not move when you switch zones. This plugin is designed for a Kindle where the visible system clock is the thing that needs correcting. It therefore fetches the selected timezone's current wall-clock time and writes that displayed time directly.

There is no hardcoded one-hour correction. DST is handled by the remote timezone source for the selected IANA timezone.

>>>>>>> 8d7b798 (Rename plugin to Time Sync Plus)
## Installation

1. Copy this folder to KOReader's plugins directory as `timesyncplus.koplugin`.
2. Restart KOReader.
3. Choose your timezone once from **Tools** -> **Time Sync Plus** -> **Timezone**.
4. After that, sync is automatic.

## Files

* `main.lua` - plugin implementation
* `_meta.lua` - KOReader plugin metadata
* `README.md` - this document

## Requirements

The plugin needs Wi-Fi and a device environment where KOReader can set system time. It uses `curl`, `date`, `hwclock`, and Kindle's `/usr/sbin/setdate` when available.

The clock setter tries several GNU/BusyBox-compatible `date` formats because Kindle firmware builds differ. A sync is only reported as successful after the plugin reads the visible system clock back and confirms it matches the selected timezone's fetched wall-clock minute.
