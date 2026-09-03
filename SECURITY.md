# Security and privacy

## Sensitive information

Do not commit any of the following:

- Private ICS or iCal addresses
- Google or Microsoft OAuth credentials
- Access or refresh tokens
- The local `data` directory
- `settings.json`
- `events-cache.json`
- `widget.log` or `widget.pid`

The repository's `.gitignore` excludes these common runtime files, but contributors should still review every change before committing it.

## Local storage

Installed runtime data is stored under:

`%LOCALAPPDATA%\WatermelonCalendarWidget\data`

Tokens, Google client secrets, private ICS addresses, and cached event data are protected for the current Windows account with Windows Data Protection.

## Calendar permissions

The widget requests read-only calendar access. It does not create, edit, or delete events.

## Reporting a concern

Do not post credentials, private calendar addresses, calendar data, or personal information in a public issue. Contact the repository owner privately through the contact method listed on her GitHub profile.

