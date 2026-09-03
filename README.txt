WATERMELON CALENDAR WIDGET
Version 1.4.4

1. Extract this ZIP file on your Windows 11 computer.
2. Double-click Install.cmd.
3. Follow SETUP_GUIDE.html to connect Google Calendar, Outlook.com, or private ICS feeds.

The widget is read-only, supports up to 20 selected calendars, refreshes every
10 minutes, and offers one-day and three-day views. It is pinned above other
windows by default; the header pin button lets other windows cover it when desired.
It hides to the Windows notification area when minimized.

No administrator access is required. Because this is a personal build and is not
commercially code-signed, Windows may show a SmartScreen warning during install.

VERSION 1.1 FIXES
- Uses native Windows 11 minimize, maximize, and close buttons.
- Gives each Google sign-in attempt a fresh secure callback port.
- Allows an in-progress browser sign-in to be cancelled and retried immediately.
- Adds clearer guidance for Google test-user and unverified-app screens.

VERSION 1.2 FIX
- Replaces the character-based previous and next date arrows with proper vector chevron icons.

VERSION 1.3 FEATURES
- Adds read-only Private ICS calendars without browser sign-in.
- Encrypts private ICS addresses and the local event cache for the current Windows account.
- Adds a pin toggle beside Refresh; always-on-top remains the default.
- Converts displayed calendar names to plain ASCII characters.
- Expands common recurring ICS events and handles exclusions, moved instances, cancellations,
  all-day events, and common time zones.

VERSION 1.3.1 INSTALLER FIX
- Prevents a delayed cleanup from the previous uninstaller from deleting a new installation.
- Verifies every copied file and displays a useful error log if installation cannot finish.

VERSION 1.3.2 INSTALLER FIX
- Replaces the batch-label installer logic with a PowerShell installer for reliable Windows 11 execution.

VERSION 1.3.3 STARTUP FIX
- Removes literal Unicode from the program source so Windows PowerShell 5.1 parses it reliably.

VERSION 1.3.4 PRIVATE ICS FIX
- Corrects the Private ICS count check so the first calendar is treated as calendar 1 of 20.

VERSION 1.3.5 STARTUP FIX
- Replaces the case-insensitive character dictionary with direct substitutions.

VERSION 1.3.6 ICS DATE FIX
- Uses the valid Windows PowerShell date style when parsing timed ICS events.

VERSION 1.3.7 COLOR OPTIONS
- Adds teal, turquoise, royal purple, violet, plum, deep blue, navy, cobalt,
  true orange, deep orange, and coral calendar colors without adding yellow shades.

VERSION 1.4.0 DISPLAY OPTIONS
- Adds a color selector beside every existing calendar in Calendars to display.
- Saves color overrides across refreshes for Google, Outlook, and Private ICS calendars.
- Adds a setting for 12-hour AM/PM event times while retaining 24-hour time as an option.

VERSION 1.4.1 LAUNCHER FIX
- Adds a dedicated Watermelon Calendar launcher with the watermelon icon.
- Runs the widget without a visible PowerShell or Windows Terminal taskbar window.
- Makes the desktop shortcut suitable for pinning directly to the Windows taskbar.
- Restores the existing widget when the launcher is selected after the calendar was minimized.

VERSION 1.4.2 INSTALLER FIX
- Removes a compiler option that is unavailable in Windows PowerShell 5.1.
- Uses the existing watermelon icon file for the shortcut and calendar window.

VERSION 1.4.3 LAUNCH FIX
- Applies the execution-policy bypass only inside the widget's own PowerShell session.
- Adds a proper Start-menu shortcut so Windows Search launches the dedicated widget.

VERSION 1.4.4 UPGRADE FIX
- Stops a lingering Watermelon launcher even when it failed before writing its PID file.
- Waits for Windows to release the old executable before rebuilding the launcher.
