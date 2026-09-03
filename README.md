# Watermelon Calendar Widget

![Watermelon Calendar Widget icon](assets/watermelon-calendar.png)

A browser-independent, read-only calendar widget for Windows 11.

Watermelon Calendar Widget keeps upcoming events visible without requiring a calendar tab to remain open in a browser. It combines selected Google Calendar, Outlook.com, and private ICS calendars in one movable desktop window.

**Current version:** 1.4.4  
**Platform:** Windows 11  
**Runtime:** Windows PowerShell 5.1  
**Status:** Stable personal-use release

## What it does

- Displays one day or three days of events.
- Combines up to 20 selected calendars.
- Connects to Google Calendar and Outlook.com using read-only OAuth permissions.
- Supports secret, read-only ICS feeds from Google, Outlook, and other calendar services.
- Refreshes automatically every 10 minutes.
- Supports 12-hour or 24-hour event times.
- Applies saved color choices to individual calendars.
- Handles common recurring ICS events, exclusions, moved instances, cancellations, all-day events, and time zones.
- Opens an event in its original calendar when selected.
- Can remain above other windows or return to normal window stacking.
- Remembers window size and screen position.
- Minimizes to the Windows notification area.

## Install

1. Select **Code**, then **Download ZIP**.
2. Extract the entire ZIP on a Windows 11 computer.
3. Open the extracted folder and double-click **Install.cmd**.
4. Follow **SETUP_GUIDE.html** to add calendars.

Administrator access is not required. The installer creates desktop, Start menu, and Windows startup shortcuts. It also compiles a small local C# launcher so the PowerShell widget can run without a visible console window.

This is a personal build and is not commercially code-signed. Windows SmartScreen may display a warning. Review the repository before choosing **Run anyway**.

## Privacy and security

The widget is read-only. It does not create, edit, or delete calendar events.

- Passwords are entered only on Google or Microsoft sign-in pages.
- OAuth tokens and the Google client secret are encrypted for the current Windows account with Windows Data Protection.
- Private ICS addresses and the local event cache are encrypted for the current Windows account.
- Runtime settings, tokens, private feeds, logs, process IDs, and cached events are stored locally in the application's `data` folder.
- This repository does not include personal calendar URLs, OAuth credentials, tokens, settings, or cached events.
- The included `.gitignore` is designed to keep local runtime data out of future commits.

Private ICS addresses should be treated like passwords. Anyone with a private calendar URL may be able to read that calendar.

## Setup options

The detailed [setup guide](SETUP_GUIDE.html) covers three connection methods:

1. **Private ICS**, the simplest option for calendars that provide a secret iCal address.
2. **Google OAuth**, using a personal Google Cloud desktop-app registration.
3. **Microsoft OAuth**, using a personal Microsoft Entra desktop-app registration.

## Repository structure

| Path | Purpose |
| --- | --- |
| `WatermelonCalendarWidget.ps1` | Main application, interface, calendar integrations, settings, encryption, caching, and event rendering |
| `WatermelonCalendarWidget.Launcher.cs` | Console-free Windows launcher compiled locally during installation |
| `Install.ps1` and `Install.cmd` | Per-user installation and shortcut creation |
| `Uninstall.cmd` | Removes the application and locally stored runtime data |
| `Launch Watermelon Calendar.cmd` | Direct PowerShell launch option |
| `SETUP_GUIDE.html` | Illustrated local setup and troubleshooting guide |
| `README.txt` | Bundled installation notes and version history |
| `assets/` | Application icon artwork |

## How this project was built

I created Watermelon Calendar Widget because I wanted an always-available desktop calendar and the tools I found required a browser.

My role was product owner and AI-assisted builder. I defined the problem, product vision, user stories, requirements, UX, feature priorities, privacy requirements, and acceptance criteria. I directed AI-assisted PowerShell and C# development through more than 15 build-test-improve cycles. I ran builds and installers, interpreted logs, isolated defects, prioritized fixes, and acceptance-tested each release.

I did not manually author the PowerShell or C# source, and I do not present myself as the programmer. I owned the problem, decisions, testing, debugging, and release validation until the product worked reliably. This repository documents both the working product and that AI-assisted product-development process.

The widget is currently used on two Windows 11 computers for personal and school calendars.

## Known limitations

- Windows 11 only.
- The application is not commercially code-signed.
- Google and Microsoft browser sign-in require users to create their own personal app registrations.
- A Google app left in testing status may require periodic reconnection.
- This is a personal portfolio project, not a commercially supported product.

## Roadmap

- Printable day and multi-day calendar views.
- Additional usability and accessibility testing.
- Continued testing across different Windows display configurations.

## Version history

See [README.txt](README.txt) for the complete version history through version 1.4.4.

## Copyright and use

Copyright (c) 2026 Talia L. Terry. All rights reserved.

This repository is published for portfolio and evaluation purposes. No open-source license is granted. See [NOTICE.md](NOTICE.md).

