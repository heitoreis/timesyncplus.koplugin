# Time Sync Plus

A KOReader plugin that keeps the Kindle clock aligned to a selected timezone.

The plugin fetches the current wall-clock time for the selected IANA timezone from `timeapi.io`, writes that displayed time to the device, and syncs again automatically after startup and resume.

## Wi-Fi behavior

When a sync starts and Wi-Fi is already enabled, the plugin leaves it alone.

When Wi-Fi is disabled, the plugin:

1. Turns Wi-Fi on using KOReader's own `NetworkMgr`.
2. Waits for a connection and retries the time request within a maximum one-minute synchronization window.
3. Stops trying after one minute if there has been no successful synchronization.
4. Turns Wi-Fi back off when the session ends.

The one-minute limit is a maximum attempt window. If synchronization succeeds earlier, Wi-Fi is turned off immediately.

The plugin also clears KOReader's "Wi-Fi was on" restore flag when it turns Wi-Fi off, so a temporary sync does not make Wi-Fi become a persistent automatic-restore preference.

## Behavior

* Syncs automatically shortly after KOReader starts.
* Syncs automatically after resume.
* Works even when Wi-Fi was initially turned off.
* Lets the user select a timezone once from the KOReader Tools menu.
* Saves the selected timezone in KOReader's settings directory.
* Syncs immediately after a timezone is selected.
* Provides a manual **Synchronize now** command.
* Retries synchronization failures until the one-minute session limit.
* Verifies the system clock after setting it before reporting success.

## Timezone Selection

Open:

`Tools` -> `Time Sync Plus` -> `Timezone`

The default timezone is `Atlantic/Canary`.

Major timezone options include:

* `UTC`
* `Atlantic/Canary`
* `Europe/London`
* `Europe/Madrid`
* `Europe/Paris`
* `Europe/Berlin`
* `America/New_York`
* `America/Chicago`
* `America/Denver`
* `America/Los_Angeles`
* `America/Mexico_City`
* `America/Sao_Paulo`
* `Asia/Dubai`
* `Asia/Kolkata`
* `Asia/Bangkok`
* `Asia/Singapore`
* `Asia/Hong_Kong`
* `Asia/Shanghai`
* `Asia/Seoul`
* `Asia/Tokyo`
* `Australia/Sydney`
* `Pacific/Auckland`

## Why This Version Works Differently

Changing timezone and calculating a true UTC timestamp produces the same instant for every timezone, so the visible clock may not move when you switch zones. This plugin is designed for a Kindle where the visible system clock is the thing that needs correcting. It therefore fetches the selected timezone's current wall-clock time and writes that displayed time directly.

There is no hardcoded one-hour correction. DST is handled by the remote timezone source for the selected IANA timezone.

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

The plugin needs a saved/usable Wi-Fi connection and a device environment where KOReader can set system time. It uses KOReader's `NetworkMgr`, plus `curl`, `date`, `hwclock`, and Kindle's `/usr/sbin/setdate` when available.

The clock setter tries several GNU/BusyBox-compatible `date` formats because Kindle firmware builds differ. A sync is only reported as successful after the plugin reads the visible system clock back and confirms it matches the selected timezone's fetched wall-clock minute.
