# Watermelon Calendar Widget
# Read-only Windows 11 desktop calendar for Google Calendar, Outlook.com, and private ICS feeds.
# Requires Windows PowerShell 5.1 (included with Windows 11).
# Version 1.4.4

param([switch]$StartMinimized)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Security, System.Web

[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:AppName = "Watermelon Calendar Widget"
$script:AppDir = Join-Path $env:LOCALAPPDATA "WatermelonCalendarWidget"
$script:DataDir = Join-Path $script:AppDir "data"
$script:SettingsPath = Join-Path $script:DataDir "settings.json"
$script:CachePath = Join-Path $script:DataDir "events-cache.json"
$script:LogPath = Join-Path $script:DataDir "widget.log"
$script:OAuthPort = 53682
$script:OAuthRedirect = "http://localhost:$($script:OAuthPort)/"
$script:RefreshMinutes = 10
$script:MaxCalendars = 20
$script:CalendarPalette = @(
    [pscustomobject]@{ Name='Watermelon pink'; Color='#D81B60' }
    [pscustomobject]@{ Name='Dark magenta'; Color='#AD1457' }
    [pscustomobject]@{ Name='Raspberry'; Color='#C2185B' }
    [pscustomobject]@{ Name='Soft pink'; Color='#E36C9D' }
    [pscustomobject]@{ Name='Watermelon green'; Color='#2E7D32' }
    [pscustomobject]@{ Name='Leaf green'; Color='#70AD47' }
    [pscustomobject]@{ Name='Classic teal'; Color='#00897B' }
    [pscustomobject]@{ Name='Deep teal'; Color='#00695C' }
    [pscustomobject]@{ Name='Bright turquoise'; Color='#00ACC1' }
    [pscustomobject]@{ Name='Royal purple'; Color='#6A1B9A' }
    [pscustomobject]@{ Name='Violet'; Color='#7E57C2' }
    [pscustomobject]@{ Name='Deep plum'; Color='#4527A0' }
    [pscustomobject]@{ Name='Deep blue'; Color='#1565C0' }
    [pscustomobject]@{ Name='Navy blue'; Color='#0D47A1' }
    [pscustomobject]@{ Name='Cobalt blue'; Color='#1976D2' }
    [pscustomobject]@{ Name='True orange'; Color='#F57C00' }
    [pscustomobject]@{ Name='Deep orange'; Color='#E65100' }
    [pscustomobject]@{ Name='Coral orange'; Color='#E64A19' }
)
$script:CurrentDate = [DateTime]::Today
$script:ViewDays = 1
$script:WindowClosingForExit = $false
$script:IsSyncing = $false
$script:TrayIcon = $null
$script:Window = $null
$script:OAuthListener = $null
$script:OAuthInProgress = $false
$script:OAuthCancelled = $false
$script:ShowRequestEvent = $null
$script:ShowRequestTimer = $null
$script:CreatedShowEvent = $false
$script:CreatedMutex = $false
$script:ShowRequestEvent = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::AutoReset, 'Local\WatermelonCalendarWidget.Show', [ref]$script:CreatedShowEvent)
$script:SingleInstanceMutex = [Threading.Mutex]::new($true, 'Local\WatermelonCalendarWidget', [ref]$script:CreatedMutex)
if (-not $script:CreatedMutex) {
    [void]$script:ShowRequestEvent.Set()
    $script:ShowRequestEvent.Dispose()
    exit
}

New-Item -ItemType Directory -Force -Path $script:DataDir | Out-Null
Set-Content -LiteralPath (Join-Path $script:DataDir 'widget.pid') -Value $PID -Encoding ASCII

function Write-WidgetLog {
    param([string]$Message)
    try {
        $line = "{0:u} {1}" -f [DateTime]::Now, $Message
        Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
        if ((Get-Item -LiteralPath $script:LogPath -ErrorAction SilentlyContinue).Length -gt 1048576) {
            $tail = Get-Content -LiteralPath $script:LogPath -Tail 300
            Set-Content -LiteralPath $script:LogPath -Value $tail -Encoding UTF8
        }
    } catch { }
}

function New-DefaultSettings {
    [pscustomobject]@{
        version = 3
        viewDays = 1
        width = 430
        height = 720
        left = $null
        top = $null
        opacity = 0.98
        launchAtStartup = $true
        pinToTop = $true
        use12HourTime = $false
        accounts = @()
        icsCalendars = @()
        selectedCalendars = @()
        calendarColorOverrides = @()
    }
}

function Load-Settings {
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) { return New-DefaultSettings }
    try {
        $loaded = Get-Content -LiteralPath $script:SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $loaded.PSObject.Properties['accounts']) { $loaded | Add-Member -NotePropertyName accounts -NotePropertyValue @() }
        if (-not $loaded.PSObject.Properties['icsCalendars']) { $loaded | Add-Member -NotePropertyName icsCalendars -NotePropertyValue @() }
        if (-not $loaded.PSObject.Properties['selectedCalendars']) { $loaded | Add-Member -NotePropertyName selectedCalendars -NotePropertyValue @() }
        if (-not $loaded.PSObject.Properties['pinToTop']) { $loaded | Add-Member -NotePropertyName pinToTop -NotePropertyValue $true }
        if (-not $loaded.PSObject.Properties['use12HourTime']) { $loaded | Add-Member -NotePropertyName use12HourTime -NotePropertyValue $false }
        if (-not $loaded.PSObject.Properties['calendarColorOverrides']) { $loaded | Add-Member -NotePropertyName calendarColorOverrides -NotePropertyValue @() }
        if (-not $loaded.accounts) { $loaded.accounts = @() }
        if (-not $loaded.icsCalendars) { $loaded.icsCalendars = @() }
        if (-not $loaded.selectedCalendars) { $loaded.selectedCalendars = @() }
        if (-not $loaded.calendarColorOverrides) { $loaded.calendarColorOverrides = @() }
        $loaded.version = 3
        return $loaded
    } catch {
        Write-WidgetLog "Could not read settings; defaults loaded. $($_.Exception.Message)"
        return New-DefaultSettings
    }
}

function Convert-ToAsciiCalendarName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return 'Calendar' }
    $value = $Name
    # Use code points instead of literal Unicode so Windows PowerShell 5.1 can
    # parse this file correctly regardless of its legacy text encoding rules.
    $value = $value.Replace(([char]0x00C6).ToString(), 'AE')
    $value = $value.Replace(([char]0x00E6).ToString(), 'ae')
    $value = $value.Replace(([char]0x0152).ToString(), 'OE')
    $value = $value.Replace(([char]0x0153).ToString(), 'oe')
    $value = $value.Replace(([char]0x00D8).ToString(), 'O')
    $value = $value.Replace(([char]0x00F8).ToString(), 'o')
    $value = $value.Replace(([char]0x00D0).ToString(), 'D')
    $value = $value.Replace(([char]0x00F0).ToString(), 'd')
    $value = $value.Replace(([char]0x00DE).ToString(), 'Th')
    $value = $value.Replace(([char]0x00FE).ToString(), 'th')
    $value = $value.Replace(([char]0x0141).ToString(), 'L')
    $value = $value.Replace(([char]0x0142).ToString(), 'l')
    $value = $value.Replace(([char]0x00DF).ToString(), 'ss')
    $builder = New-Object Text.StringBuilder
    foreach ($character in $value.Normalize([Text.NormalizationForm]::FormD).ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    $value = $builder.ToString().Normalize([Text.NormalizationForm]::FormC)
    $value = [Text.RegularExpressions.Regex]::Replace($value, "[^A-Za-z0-9 &'().,_-]+", ' ')
    $value = [Text.RegularExpressions.Regex]::Replace($value, '\s+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($value)) { return 'Calendar' }
    return $value
}

function Save-Settings {
    param($Settings = $script:Settings)
    try {
        $Settings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
    } catch {
        Write-WidgetLog "Could not save settings. $($_.Exception.Message)"
    }
}

function Get-CalendarDisplayColor {
    param($Calendar)
    $key = [string]$Calendar.key
    $override = @($script:Settings.calendarColorOverrides | Where-Object { [string]$_.key -eq $key } | Select-Object -First 1)
    if ($override.Count -and -not [string]::IsNullOrWhiteSpace([string]$override[0].color)) { return [string]$override[0].color }
    if (-not [string]::IsNullOrWhiteSpace([string]$Calendar.color)) { return [string]$Calendar.color }
    return '#D81B60'
}

function Set-CalendarColorOverride {
    param([string]$Key, [string]$Color)
    if ([string]::IsNullOrWhiteSpace($Key) -or [string]::IsNullOrWhiteSpace($Color)) { return }
    $others = @($script:Settings.calendarColorOverrides | Where-Object { [string]$_.key -ne $Key })
    $script:Settings.calendarColorOverrides = @($others) + [pscustomobject]@{ key=$Key; color=$Color }
}

function Protect-Text {
    param([string]$PlainText)
    if ([string]::IsNullOrWhiteSpace($PlainText)) { return "" }
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($encrypted)
}

function Unprotect-Text {
    param([string]$CipherText)
    if ([string]::IsNullOrWhiteSpace($CipherText)) { return "" }
    try {
        $bytes = [Convert]::FromBase64String($CipherText)
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($plain)
    } catch {
        return ""
    }
}

function New-RandomBase64Url {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($buffer) } finally { $rng.Dispose() }
    return ([Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Get-Sha256Base64Url {
    param([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $hash = $sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($Value)) } finally { $sha.Dispose() }
    return ([Convert]::ToBase64String($hash).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function ConvertTo-QueryString {
    param([hashtable]$Values)
    ($Values.GetEnumerator() | ForEach-Object {
        "{0}={1}" -f [Uri]::EscapeDataString([string]$_.Key), [Uri]::EscapeDataString([string]$_.Value)
    }) -join '&'
}

function Invoke-OAuthBrowserFlow {
    param(
        [ValidateSet('google','microsoft')][string]$Provider,
        [string]$ClientId,
        [string]$ClientSecret = ""
    )
    $state = New-RandomBase64Url 24
    $verifier = New-RandomBase64Url 64
    $challenge = Get-Sha256Base64Url $verifier

    # Google desktop clients are designed to use a fresh loopback port. This also
    # prevents a failed browser attempt from blocking the next sign-in attempt.
    $requestedPort = if ($Provider -eq 'google') { 0 } else { $script:OAuthPort }
    $bindAddress = if ($Provider -eq 'google') { [Net.IPAddress]::Loopback } else { [Net.IPAddress]::IPv6Any }
    if ($script:OAuthListener) {
        try { $script:OAuthListener.Stop() } catch { }
        $script:OAuthListener = $null
    }
    $listener = [Net.Sockets.TcpListener]::new($bindAddress, $requestedPort)
    if ($Provider -eq 'microsoft') { $listener.Server.DualMode = $true }
    try {
        $listener.Start()
    } catch {
        throw "The secure sign-in callback could not start. Restart the widget and try again."
    }
    $script:OAuthListener = $listener
    $actualPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirectUri = if ($Provider -eq 'google') { "http://127.0.0.1:$actualPort/" } else { "http://localhost:$actualPort/" }
    $script:OAuthCancelled = $false
    $script:OAuthInProgress = $true

    if ($Provider -eq 'google') {
        $authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
        $tokenEndpoint = "https://oauth2.googleapis.com/token"
        $scope = "openid email https://www.googleapis.com/auth/calendar.readonly"
        $parameters = @{
            client_id = $ClientId; redirect_uri = $redirectUri; response_type = 'code'
            scope = $scope; access_type = 'offline'; prompt = 'consent select_account'
            state = $state; code_challenge = $challenge; code_challenge_method = 'S256'
        }
    } else {
        $authEndpoint = "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize"
        $tokenEndpoint = "https://login.microsoftonline.com/consumers/oauth2/v2.0/token"
        $scope = "offline_access User.Read Calendars.Read"
        $parameters = @{
            client_id = $ClientId; redirect_uri = $redirectUri; response_type = 'code'
            response_mode = 'query'; scope = $scope; state = $state
            code_challenge = $challenge; code_challenge_method = 'S256'; prompt = 'select_account'
        }
    }

    try {
        Start-Process ($authEndpoint + '?' + (ConvertTo-QueryString $parameters))
        $pending = $listener.AcceptTcpClientAsync()
        $deadline = [DateTime]::UtcNow.AddMinutes(5)
        while (-not $pending.IsCompleted) {
            if ($script:OAuthCancelled) { throw "Sign-in was cancelled. You can try again now." }
            if ([DateTime]::UtcNow -gt $deadline) { throw "Sign-in timed out. Please try again." }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        if ($script:OAuthCancelled) { throw "Sign-in was cancelled. You can try again now." }
        $client = $pending.GetAwaiter().GetResult()
        $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
        $requestLine = $reader.ReadLine()
        while (($line = $reader.ReadLine()) -ne '') { if ($null -eq $line) { break } }
        $target = $requestLine.Split(' ')[1]
        $callbackUri = [Uri]($redirectUri.TrimEnd('/') + $target)
        $query = [Web.HttpUtility]::ParseQueryString($callbackUri.Query)
        $responseText = if ($query['error']) {
            "Sign-in was not completed. You may close this browser tab."
        } else {
            "Sign-in complete. You may close this browser tab and return to Watermelon Calendar Widget."
        }
        $responseBytes = [Text.Encoding]::UTF8.GetBytes("<!doctype html><html><head><meta charset='utf-8'><title>Watermelon Calendar</title><style>body{font-family:Segoe UI;background:#fff5f8;color:#171717;padding:56px}div{max-width:600px;margin:auto;border-left:10px solid #d81b60;padding:20px 28px;background:#fff;box-shadow:0 10px 30px #0002}h1{color:#ad1457}</style></head><body><div><h1>Watermelon Calendar</h1><p>$responseText</p></div></body></html>")
        $headerBytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $($responseBytes.Length)`r`nConnection: close`r`n`r`n")
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        $stream.Write($responseBytes, 0, $responseBytes.Length)
        $stream.Flush(); $reader.Dispose(); $stream.Dispose(); $client.Close()

        if ($query['error']) { throw "Sign-in was cancelled or refused: $($query['error'])" }
        if ($query['state'] -ne $state) { throw "The sign-in response could not be verified. Please try again." }
        $code = $query['code']
        if ([string]::IsNullOrWhiteSpace($code)) { throw "No authorization code was returned." }

        $body = @{
            client_id = $ClientId; code = $code; code_verifier = $verifier
            redirect_uri = $redirectUri; grant_type = 'authorization_code'
        }
        if ($Provider -eq 'google' -and -not [string]::IsNullOrWhiteSpace($ClientSecret)) {
            $body.client_secret = $ClientSecret
        }
        return Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body -ContentType 'application/x-www-form-urlencoded'
    } finally {
        try { $listener.Stop() } catch { }
        if ([object]::ReferenceEquals($script:OAuthListener, $listener)) { $script:OAuthListener = $null }
        $script:OAuthInProgress = $false
    }
}

function Get-ValidAccessToken {
    param($Account)
    $expiry = [DateTime]::MinValue
    [DateTime]::TryParse([string]$Account.expiresAt, [ref]$expiry) | Out-Null
    $accessToken = Unprotect-Text ([string]$Account.accessToken)
    if ($accessToken -and $expiry -gt [DateTime]::UtcNow.AddMinutes(3)) { return $accessToken }

    $refreshToken = Unprotect-Text ([string]$Account.refreshToken)
    if ([string]::IsNullOrWhiteSpace($refreshToken)) { throw "The account needs to be reconnected." }
    if ($Account.provider -eq 'google') {
        $body = @{ client_id = $Account.clientId; refresh_token = $refreshToken; grant_type = 'refresh_token' }
        $secret = Unprotect-Text ([string]$Account.clientSecret)
        if ($secret) { $body.client_secret = $secret }
        $response = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
    } else {
        $body = @{
            client_id = $Account.clientId; refresh_token = $refreshToken; grant_type = 'refresh_token'
            scope = 'offline_access User.Read Calendars.Read'
        }
        $response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/consumers/oauth2/v2.0/token" -Body $body -ContentType 'application/x-www-form-urlencoded'
    }
    $Account.accessToken = Protect-Text ([string]$response.access_token)
    if ($response.refresh_token) { $Account.refreshToken = Protect-Text ([string]$response.refresh_token) }
    $Account.expiresAt = [DateTime]::UtcNow.AddSeconds([int]$response.expires_in).ToString('o')
    Save-Settings
    return [string]$response.access_token
}

function Invoke-ProviderGet {
    param([string]$Uri, [string]$Token, [hashtable]$ExtraHeaders = @{})
    $headers = @{ Authorization = "Bearer $Token" }
    foreach ($key in $ExtraHeaders.Keys) { $headers[$key] = $ExtraHeaders[$key] }
    Invoke-RestMethod -Method Get -Uri $Uri -Headers $headers
}

function Get-AccountCalendars {
    param($Account)
    $token = Get-ValidAccessToken $Account
    $items = @()
    if ($Account.provider -eq 'google') {
        $uri = "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=false"
        do {
            $page = Invoke-ProviderGet $uri $token
            foreach ($calendar in @($page.items)) {
                $items += [pscustomobject]@{
                    key = "$($Account.id)|$($calendar.id)"; accountId = $Account.id; provider = 'google'
                    calendarId = [string]$calendar.id; name = Convert-ToAsciiCalendarName ([string]$calendar.summary)
                    accountLabel = [string]$Account.label; color = if ($calendar.backgroundColor) { [string]$calendar.backgroundColor } else { '#D81B60' }
                    primary = [bool]$calendar.primary
                }
            }
            $uri = if ($page.nextPageToken) { "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=false&pageToken=$([Uri]::EscapeDataString([string]$page.nextPageToken))" } else { $null }
        } while ($uri)
    } else {
        $uri = "https://graph.microsoft.com/v1.0/me/calendars?`$top=100&`$select=id,name,color,isDefaultCalendar"
        do {
            $page = Invoke-ProviderGet $uri $token
            foreach ($calendar in @($page.value)) {
                $items += [pscustomobject]@{
                    key = "$($Account.id)|$($calendar.id)"; accountId = $Account.id; provider = 'microsoft'
                    calendarId = [string]$calendar.id; name = Convert-ToAsciiCalendarName ([string]$calendar.name)
                    accountLabel = [string]$Account.label; color = Convert-OutlookColor ([string]$calendar.color)
                    primary = [bool]$calendar.isDefaultCalendar
                }
            }
            $uri = [string]$page.'@odata.nextLink'
        } while ($uri)
    }
    return @($items)
}

function Convert-OutlookColor {
    param([string]$Name)
    $map = @{
        lightBlue='#5B9BD5'; lightGreen='#70AD47'; lightOrange='#ED7D31'; lightGray='#A5A5A5'
        lightYellow='#FFC000'; lightTeal='#2E9E93'; lightPink='#E36C9D'; lightBrown='#A47757'
        lightRed='#C00000'; maxColor='#D81B60'; auto='#2E7D32'
    }
    if ($map.ContainsKey($Name)) { return $map[$Name] }
    return '#2E7D32'
}

function Get-AccountIdentity {
    param([string]$Provider, [string]$Token)
    if ($Provider -eq 'google') {
        $profile = Invoke-ProviderGet "https://openidconnect.googleapis.com/v1/userinfo" $Token
        if ($profile.email) { return [string]$profile.email }
        return 'Google account'
    }
    $profile = Invoke-ProviderGet "https://graph.microsoft.com/v1.0/me?`$select=displayName,mail,userPrincipalName" $Token
    if ($profile.mail) { return [string]$profile.mail }
    if ($profile.userPrincipalName) { return [string]$profile.userPrincipalName }
    return [string]$profile.displayName
}

function Add-CalendarAccount {
    param([ValidateSet('google','microsoft')][string]$Provider, [string]$ClientId, [string]$ClientSecret = '')
    $tokenResponse = Invoke-OAuthBrowserFlow -Provider $Provider -ClientId $ClientId -ClientSecret $ClientSecret
    if (-not $tokenResponse.refresh_token) { throw "The provider did not return a long-lived refresh token. Remove the widget from the provider's connected apps and try again." }
    $label = Get-AccountIdentity -Provider $Provider -Token ([string]$tokenResponse.access_token)
    $account = [pscustomobject]@{
        id = [Guid]::NewGuid().ToString('N'); provider = $Provider; label = $label; clientId = $ClientId
        clientSecret = Protect-Text $ClientSecret; accessToken = Protect-Text ([string]$tokenResponse.access_token)
        refreshToken = Protect-Text ([string]$tokenResponse.refresh_token)
        expiresAt = [DateTime]::UtcNow.AddSeconds([int]$tokenResponse.expires_in).ToString('o')
    }
    $script:Settings.accounts = @($script:Settings.accounts) + $account
    Save-Settings
    return $account
}

function Find-Account {
    param([string]$Id)
    @($script:Settings.accounts) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

function Convert-GoogleEvent {
    param($Event, $Calendar)
    $isAllDay = [bool]$Event.start.date
    $start = if ($isAllDay) { [DateTime]::Parse([string]$Event.start.date).Date } else { [DateTimeOffset]::Parse([string]$Event.start.dateTime).LocalDateTime }
    $end = if ($isAllDay) { [DateTime]::Parse([string]$Event.end.date).Date } else { [DateTimeOffset]::Parse([string]$Event.end.dateTime).LocalDateTime }
    [pscustomobject]@{
        id = [string]$Event.id; calendarKey = $Calendar.key; calendarName = Convert-ToAsciiCalendarName ([string]$Calendar.name); accountLabel = $Calendar.accountLabel
        provider = 'google'; title = if ($Event.summary) { [string]$Event.summary } else { '(No title)' }
        start = $start; end = $end; allDay = $isAllDay; location = [string]$Event.location
        meetingType = Get-MeetingType -Location ([string]$Event.location) -OnlineUrl ([string]$Event.hangoutLink)
        url = [string]$Event.htmlLink; color = $Calendar.color
    }
}

function Convert-MicrosoftEvent {
    param($Event, $Calendar)
    $isAllDay = [bool]$Event.isAllDay
    $start = [DateTime]::Parse([string]$Event.start.dateTime, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal)
    $end = [DateTime]::Parse([string]$Event.end.dateTime, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal)
    $onlineUrl = if ($Event.onlineMeeting.joinUrl) { [string]$Event.onlineMeeting.joinUrl } else { '' }
    [pscustomobject]@{
        id = [string]$Event.id; calendarKey = $Calendar.key; calendarName = Convert-ToAsciiCalendarName ([string]$Calendar.name); accountLabel = $Calendar.accountLabel
        provider = 'microsoft'; title = if ($Event.subject) { [string]$Event.subject } else { '(No title)' }
        start = $start; end = $end; allDay = $isAllDay; location = [string]$Event.location.displayName
        meetingType = Get-MeetingType -Location ([string]$Event.location.displayName) -OnlineUrl $onlineUrl
        url = [string]$Event.webLink; color = $Calendar.color
    }
}

function Get-MeetingType {
    param([string]$Location, [string]$OnlineUrl)
    $combined = "$Location $OnlineUrl".ToLowerInvariant()
    if ($combined -match 'teams\.microsoft|microsoft teams') { return 'Microsoft Teams' }
    if ($combined -match 'zoom\.|zoom meeting') { return 'Zoom' }
    if ($combined -match 'meet\.google') { return 'Google Meet' }
    if ($OnlineUrl) { return 'Online meeting' }
    return ''
}

function ConvertFrom-IcsText {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    $result = $Value.Replace('\N', "`n").Replace('\n', "`n")
    $result = $result.Replace('\,', ',').Replace('\;', ';').Replace('\\', '\')
    return $result
}

function Get-IcsTimeZone {
    param([string]$TzId)
    if ([string]::IsNullOrWhiteSpace($TzId)) { return [TimeZoneInfo]::Local }
    $ianaToWindows = @{
        'UTC'='UTC'; 'Etc/UTC'='UTC'; 'Etc/GMT'='UTC'; 'GMT'='GMT Standard Time'
        'Europe/London'='GMT Standard Time'; 'Europe/Dublin'='GMT Standard Time'
        'Europe/Paris'='Romance Standard Time'; 'Europe/Berlin'='W. Europe Standard Time'; 'Europe/Oslo'='W. Europe Standard Time'
        'Europe/Stockholm'='W. Europe Standard Time'; 'Europe/Copenhagen'='Romance Standard Time'; 'Europe/Rome'='W. Europe Standard Time'
        'Europe/Madrid'='Romance Standard Time'; 'Europe/Amsterdam'='W. Europe Standard Time'; 'Europe/Brussels'='Romance Standard Time'
        'America/New_York'='Eastern Standard Time'; 'America/Detroit'='Eastern Standard Time'; 'America/Toronto'='Eastern Standard Time'
        'America/Chicago'='Central Standard Time'; 'America/Winnipeg'='Central Standard Time'; 'America/Denver'='Mountain Standard Time'
        'America/Phoenix'='US Mountain Standard Time'; 'America/Los_Angeles'='Pacific Standard Time'; 'America/Vancouver'='Pacific Standard Time'
        'America/Anchorage'='Alaskan Standard Time'; 'Pacific/Honolulu'='Hawaiian Standard Time'
        'Australia/Sydney'='AUS Eastern Standard Time'; 'Australia/Melbourne'='AUS Eastern Standard Time'
        'Asia/Tokyo'='Tokyo Standard Time'; 'Asia/Singapore'='Singapore Standard Time'; 'Asia/Kolkata'='India Standard Time'
    }
    $candidates = @($TzId)
    if ($ianaToWindows.ContainsKey($TzId)) { $candidates += $ianaToWindows[$TzId] }
    foreach ($candidate in $candidates) {
        try { return [TimeZoneInfo]::FindSystemTimeZoneById([string]$candidate) } catch { }
    }
    return [TimeZoneInfo]::Local
}

function ConvertFrom-IcsDate {
    param([string]$Value, [hashtable]$Parameters = @{})
    $isDate = ($Parameters['VALUE'] -eq 'DATE') -or ($Value -match '^\d{8}$')
    if ($isDate) {
        return [pscustomobject]@{ DateTime = [DateTime]::ParseExact($Value.Substring(0,8), 'yyyyMMdd', [Globalization.CultureInfo]::InvariantCulture); AllDay = $true }
    }
    $format = if ($Value -match '^\d{8}T\d{4}Z?$') { 'yyyyMMddTHHmm' } else { 'yyyyMMddTHHmmss' }
    $trimmed = $Value.TrimEnd('Z')
    $parsed = [DateTime]::ParseExact($trimmed, $format, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None)
    if ($Value.EndsWith('Z')) {
        $parsed = [DateTime]::SpecifyKind($parsed, [DateTimeKind]::Utc).ToLocalTime()
    } elseif ($Parameters['TZID']) {
        $zone = Get-IcsTimeZone ([string]$Parameters['TZID'])
        $parsed = [TimeZoneInfo]::ConvertTime([DateTime]::SpecifyKind($parsed, [DateTimeKind]::Unspecified), $zone, [TimeZoneInfo]::Local)
    }
    return [pscustomobject]@{ DateTime = [DateTime]$parsed; AllDay = $false }
}

function Get-IcsProperties {
    param($RawEvent, [string]$Name)
    if ($RawEvent.Properties.ContainsKey($Name)) { return @($RawEvent.Properties[$Name]) }
    return @()
}

function Get-IcsProperty {
    param($RawEvent, [string]$Name)
    @(Get-IcsProperties $RawEvent $Name) | Select-Object -First 1
}

function ConvertFrom-IcsCalendar {
    param([string]$Text)
    $unfolded = New-Object Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^[ \t]' -and $unfolded.Count -gt 0) {
            $unfolded[$unfolded.Count - 1] = $unfolded[$unfolded.Count - 1] + $line.Substring(1)
        } else { $unfolded.Add($line) }
    }
    $events = New-Object Collections.ArrayList
    $current = $null
    foreach ($line in $unfolded) {
        if ($line -eq 'BEGIN:VEVENT') { $current = [pscustomobject]@{ Properties = @{} }; continue }
        if ($line -eq 'END:VEVENT') {
            if ($current) { $events.Add($current) | Out-Null }
            $current = $null; continue
        }
        if (-not $current) { continue }
        $colon = $line.IndexOf(':')
        if ($colon -lt 1) { continue }
        $left = $line.Substring(0, $colon); $value = $line.Substring($colon + 1)
        $parts = $left.Split(';'); $name = $parts[0].ToUpperInvariant(); $parameters = @{}
        for ($index = 1; $index -lt $parts.Count; $index++) {
            $equals = $parts[$index].IndexOf('=')
            if ($equals -gt 0) { $parameters[$parts[$index].Substring(0,$equals).ToUpperInvariant()] = $parts[$index].Substring($equals + 1).Trim('"') }
        }
        $property = [pscustomobject]@{ Value = $value; Parameters = $parameters }
        if (-not $current.Properties.ContainsKey($name)) { $current.Properties[$name] = @() }
        $current.Properties[$name] = @($current.Properties[$name]) + $property
    }
    return @($events)
}

function Convert-IcsRawEvent {
    param($RawEvent)
    $startProperty = Get-IcsProperty $RawEvent 'DTSTART'
    if (-not $startProperty) { return $null }
    $startValue = ConvertFrom-IcsDate ([string]$startProperty.Value) $startProperty.Parameters
    $endProperty = Get-IcsProperty $RawEvent 'DTEND'
    if ($endProperty) { $endValue = ConvertFrom-IcsDate ([string]$endProperty.Value) $endProperty.Parameters }
    else { $endValue = [pscustomobject]@{ DateTime = $startValue.DateTime.Add($(if ($startValue.AllDay) { [TimeSpan]::FromDays(1) } else { [TimeSpan]::FromHours(1) })); AllDay = $startValue.AllDay } }
    $recurrenceProperty = Get-IcsProperty $RawEvent 'RECURRENCE-ID'
    $recurrenceId = if ($recurrenceProperty) { (ConvertFrom-IcsDate ([string]$recurrenceProperty.Value) $recurrenceProperty.Parameters).DateTime } else { $null }
    $exDates = @()
    foreach ($property in @(Get-IcsProperties $RawEvent 'EXDATE')) {
        foreach ($part in ([string]$property.Value -split ',')) { $exDates += (ConvertFrom-IcsDate $part $property.Parameters).DateTime }
    }
    $rDates = @()
    foreach ($property in @(Get-IcsProperties $RawEvent 'RDATE')) {
        foreach ($part in ([string]$property.Value -split ',')) { $rDates += (ConvertFrom-IcsDate $part $property.Parameters).DateTime }
    }
    $uid = Get-IcsProperty $RawEvent 'UID'; $summary = Get-IcsProperty $RawEvent 'SUMMARY'; $location = Get-IcsProperty $RawEvent 'LOCATION'
    $url = Get-IcsProperty $RawEvent 'URL'; $status = Get-IcsProperty $RawEvent 'STATUS'; $rrule = Get-IcsProperty $RawEvent 'RRULE'
    return [pscustomobject]@{
        Uid = if ($uid) { [string]$uid.Value } else { [Guid]::NewGuid().ToString('N') }
        Title = if ($summary) { ConvertFrom-IcsText ([string]$summary.Value) } else { '(No title)' }
        Location = if ($location) { ConvertFrom-IcsText ([string]$location.Value) } else { '' }
        Url = if ($url) { [string]$url.Value } else { '' }
        Status = if ($status) { ([string]$status.Value).ToUpperInvariant() } else { '' }
        Start = [DateTime]$startValue.DateTime; End = [DateTime]$endValue.DateTime; AllDay = [bool]$startValue.AllDay
        RecurrenceId = $recurrenceId; Rule = if ($rrule) { [string]$rrule.Value } else { '' }
        ExDates = @($exDates); RDates = @($rDates)
    }
}

function ConvertFrom-IcsRule {
    param([string]$Rule)
    $values = @{}
    foreach ($part in ($Rule -split ';')) {
        $equals = $part.IndexOf('=')
        if ($equals -gt 0) { $values[$part.Substring(0,$equals).ToUpperInvariant()] = $part.Substring($equals + 1).ToUpperInvariant() }
    }
    return $values
}

function Test-IcsByDay {
    param([DateTime]$Date, [string[]]$Tokens)
    if (-not $Tokens -or $Tokens.Count -eq 0) { return $true }
    $codes = @('SU','MO','TU','WE','TH','FR','SA'); $code = $codes[[int]$Date.DayOfWeek]
    foreach ($token in $Tokens) {
        if ($token -notmatch '^([+-]?\d+)?(SU|MO|TU|WE|TH|FR|SA)$') { continue }
        if ($Matches[2] -ne $code) { continue }
        if (-not $Matches[1]) { return $true }
        $ordinal = [int]$Matches[1]
        if ($ordinal -gt 0 -and ([Math]::Floor(($Date.Day - 1) / 7) + 1) -eq $ordinal) { return $true }
        if ($ordinal -lt 0) {
            $remaining = [DateTime]::DaysInMonth($Date.Year,$Date.Month) - $Date.Day
            if (-([Math]::Floor($remaining / 7) + 1) -eq $ordinal) { return $true }
        }
    }
    return $false
}

function Test-IcsRecurrenceDate {
    param([DateTime]$Date, $Event, [hashtable]$Rule)
    $frequency = [string]$Rule['FREQ']; $interval = if ($Rule['INTERVAL']) { [int]$Rule['INTERVAL'] } else { 1 }
    $byDay = if ($Rule['BYDAY']) { @([string]$Rule['BYDAY'] -split ',') } else { @() }
    $byMonth = if ($Rule['BYMONTH']) { @([string]$Rule['BYMONTH'] -split ',' | ForEach-Object { [int]$_ }) } else { @() }
    $byMonthDay = if ($Rule['BYMONTHDAY']) { @([string]$Rule['BYMONTHDAY'] -split ',' | ForEach-Object { [int]$_ }) } else { @() }
    if ($Date.Date -lt $Event.Start.Date) { return $false }
    if ($byMonth.Count -and $Date.Month -notin $byMonth) { return $false }
    if ($byMonthDay.Count) {
        $validDays = @($byMonthDay | ForEach-Object { if ($_ -lt 0) { [DateTime]::DaysInMonth($Date.Year,$Date.Month) + $_ + 1 } else { $_ } })
        if ($Date.Day -notin $validDays) { return $false }
    }
    switch ($frequency) {
        'DAILY' {
            if (([int]($Date.Date - $Event.Start.Date).TotalDays % $interval) -ne 0) { return $false }
            if ($byDay.Count -and -not (Test-IcsByDay $Date $byDay)) { return $false }
        }
        'WEEKLY' {
            $anchor = $Event.Start.Date.AddDays(-[int]$Event.Start.DayOfWeek)
            $week = [Math]::Floor(($Date.Date - $anchor).TotalDays / 7)
            if (($week % $interval) -ne 0) { return $false }
            if ($byDay.Count) { if (-not (Test-IcsByDay $Date $byDay)) { return $false } }
            elseif ($Date.DayOfWeek -ne $Event.Start.DayOfWeek) { return $false }
        }
        'MONTHLY' {
            $months = (($Date.Year - $Event.Start.Year) * 12) + $Date.Month - $Event.Start.Month
            if (($months % $interval) -ne 0) { return $false }
            if ($byMonthDay.Count -eq 0 -and $byDay.Count -eq 0 -and $Date.Day -ne $Event.Start.Day) { return $false }
            if ($byDay.Count -and -not (Test-IcsByDay $Date $byDay)) { return $false }
        }
        'YEARLY' {
            if ((($Date.Year - $Event.Start.Year) % $interval) -ne 0) { return $false }
            if ($byMonth.Count -eq 0 -and $Date.Month -ne $Event.Start.Month) { return $false }
            if ($byMonthDay.Count -eq 0 -and $byDay.Count -eq 0 -and $Date.Day -ne $Event.Start.Day) { return $false }
            if ($byDay.Count -and -not (Test-IcsByDay $Date $byDay)) { return $false }
        }
        default { return $false }
    }
    return $true
}

function Expand-IcsEvent {
    param($Event, [DateTime]$From, [DateTime]$To)
    if ([string]::IsNullOrWhiteSpace([string]$Event.Rule)) {
        if ($Event.Start -lt $To -and $Event.End -gt $From) { return @([pscustomobject]@{ Event=$Event; Start=$Event.Start; End=$Event.End }) }
        return @()
    }
    $rule = ConvertFrom-IcsRule ([string]$Event.Rule)
    $until = [DateTime]::MaxValue
    if ($rule['UNTIL']) { try { $until = (ConvertFrom-IcsDate ([string]$rule['UNTIL']) @{}).DateTime } catch { } }
    $countLimit = if ($rule['COUNT']) { [int]$rule['COUNT'] } else { [int]::MaxValue }
    $duration = $Event.End - $Event.Start; $results = @(); $occurrenceCount = 0; $iterations = 0
    $untilBoundary = if ($until -eq [DateTime]::MaxValue) { $To } else { $until.AddDays(1) }
    $scanEnd = if ($To -lt $untilBoundary) { $To } else { $untilBoundary }
    for ($date = $Event.Start.Date; $date -lt $scanEnd.Date.AddDays(1); $date = $date.AddDays(1)) {
        $iterations++; if ($iterations -gt 40000) { break }
        if (-not (Test-IcsRecurrenceDate $date $Event $rule)) { continue }
        $occurrenceCount++
        if ($occurrenceCount -gt $countLimit) { break }
        $start = $date.Add($Event.Start.TimeOfDay)
        if ($start -gt $until) { break }
        $end = $start.Add($duration)
        if ($start -lt $To -and $end -gt $From) { $results += [pscustomobject]@{ Event=$Event; Start=$start; End=$end } }
    }
    foreach ($rDate in @($Event.RDates)) {
        $rEnd = ([DateTime]$rDate).Add($duration)
        if ($rDate -lt $To -and $rEnd -gt $From) { $results += [pscustomobject]@{ Event=$Event; Start=[DateTime]$rDate; End=$rEnd } }
    }
    return @($results | Sort-Object Start -Unique)
}

function Get-IcsCalendarEvents {
    param($Calendar, [DateTime]$From, [DateTime]$To)
    $feedUrl = Unprotect-Text ([string]$Calendar.feedUrl)
    if ([string]::IsNullOrWhiteSpace($feedUrl)) { throw 'The private ICS address could not be decrypted. Remove and add this calendar again.' }
    $response = Invoke-WebRequest -UseBasicParsing -Uri $feedUrl -TimeoutSec 30 -Headers @{ 'User-Agent'='WatermelonCalendarWidget/1.3' }
    $text = [string]$response.Content
    if ($text -notmatch 'BEGIN:VCALENDAR') { throw 'The address did not return an iCalendar feed.' }
    $parsed = @(ConvertFrom-IcsCalendar $text | ForEach-Object { Convert-IcsRawEvent $_ } | Where-Object { $null -ne $_ })
    $output = @()
    foreach ($group in @($parsed | Group-Object Uid)) {
        $masters = @($group.Group | Where-Object { $null -eq $_.RecurrenceId })
        $overrides = @($group.Group | Where-Object { $null -ne $_.RecurrenceId })
        foreach ($master in $masters) {
            if ($master.Status -eq 'CANCELLED') { continue }
            foreach ($occurrence in @(Expand-IcsEvent $master $From $To)) {
                $replacement = @($overrides | Where-Object { [Math]::Abs((([DateTime]$_.RecurrenceId) - ([DateTime]$occurrence.Start)).TotalSeconds) -lt 1 } | Select-Object -First 1)
                if ($replacement.Count -and $replacement[0].Status -eq 'CANCELLED') { continue }
                $source = if ($replacement.Count) { $replacement[0] } else { $master }
                $start = if ($replacement.Count) { [DateTime]$source.Start } else { [DateTime]$occurrence.Start }
                $end = if ($replacement.Count) { [DateTime]$source.End } else { [DateTime]$occurrence.End }
                $isExcluded = @($master.ExDates | Where-Object { [Math]::Abs((([DateTime]$_) - ([DateTime]$occurrence.Start)).TotalSeconds) -lt 1 }).Count -gt 0
                if ($isExcluded) { continue }
                $output += [pscustomobject]@{
                    id = "$($source.Uid)|$($start.ToString('o'))"; calendarKey = $Calendar.key
                    calendarName = Convert-ToAsciiCalendarName ([string]$Calendar.name); accountLabel = 'Private ICS'; provider = 'ics'
                    title = [string]$source.Title; start = $start; end = $end; allDay = [bool]$source.AllDay
                    location = [string]$source.Location; meetingType = Get-MeetingType -Location ([string]$source.Location) -OnlineUrl ([string]$source.Url)
                    url = [string]$source.Url; color = [string]$Calendar.color
                }
            }
        }
        $standaloneOverrides = if ($masters.Count -eq 0) { @($overrides) } else { @() }
        foreach ($standalone in $standaloneOverrides) {
            if ($standalone.Status -ne 'CANCELLED' -and $standalone.Start -lt $To -and $standalone.End -gt $From) {
                $output += [pscustomobject]@{
                    id = "$($standalone.Uid)|$($standalone.Start.ToString('o'))"; calendarKey = $Calendar.key
                    calendarName = Convert-ToAsciiCalendarName ([string]$Calendar.name); accountLabel = 'Private ICS'; provider = 'ics'
                    title = [string]$standalone.Title; start = [DateTime]$standalone.Start; end = [DateTime]$standalone.End; allDay = [bool]$standalone.AllDay
                    location = [string]$standalone.Location; meetingType = Get-MeetingType -Location ([string]$standalone.Location) -OnlineUrl ([string]$standalone.Url)
                    url = [string]$standalone.Url; color = [string]$Calendar.color
                }
            }
        }
    }
    return @($output | Sort-Object start)
}

function Get-CalendarEvents {
    param($Calendar, [DateTime]$From, [DateTime]$To)
    if ($Calendar.provider -eq 'ics') { return @(Get-IcsCalendarEvents $Calendar $From $To) }
    $account = Find-Account $Calendar.accountId
    if (-not $account) { return @() }
    $token = Get-ValidAccessToken $account
    $events = @()
    if ($Calendar.provider -eq 'google') {
        $calendarId = [Uri]::EscapeDataString([string]$Calendar.calendarId)
        $timeMin = [Uri]::EscapeDataString($From.ToUniversalTime().ToString('o'))
        $timeMax = [Uri]::EscapeDataString($To.ToUniversalTime().ToString('o'))
        $uri = "https://www.googleapis.com/calendar/v3/calendars/$calendarId/events?singleEvents=true&orderBy=startTime&maxResults=2500&timeMin=$timeMin&timeMax=$timeMax"
        do {
            $page = Invoke-ProviderGet $uri $token
            foreach ($item in @($page.items)) {
                if ($item.status -ne 'cancelled') { $events += Convert-GoogleEvent $item $Calendar }
            }
            $uri = if ($page.nextPageToken) { $uri.Split('&pageToken=')[0] + '&pageToken=' + [Uri]::EscapeDataString([string]$page.nextPageToken) } else { $null }
        } while ($uri)
    } else {
        $calendarId = [Uri]::EscapeDataString([string]$Calendar.calendarId)
        $startIso = [Uri]::EscapeDataString($From.ToUniversalTime().ToString('o'))
        $endIso = [Uri]::EscapeDataString($To.ToUniversalTime().ToString('o'))
        $uri = "https://graph.microsoft.com/v1.0/me/calendars/$calendarId/calendarView?startDateTime=$startIso&endDateTime=$endIso&`$top=500&`$select=id,subject,start,end,isAllDay,location,onlineMeeting,webLink,isCancelled"
        $zone = [TimeZoneInfo]::Local.Id.Replace('"','')
        do {
            $page = Invoke-ProviderGet $uri $token @{ Prefer = "outlook.timezone=`"$zone`"" }
            foreach ($item in @($page.value)) {
                if (-not $item.isCancelled) { $events += Convert-MicrosoftEvent $item $Calendar }
            }
            $uri = [string]$page.'@odata.nextLink'
        } while ($uri)
    }
    return @($events)
}

function Load-CachedEvents {
    if (-not (Test-Path -LiteralPath $script:CachePath)) { return @() }
    try {
        $stored = Get-Content -LiteralPath $script:CachePath -Raw -Encoding UTF8
        $json = if ($stored.TrimStart().StartsWith('{')) { $stored } else { Unprotect-Text $stored.Trim() }
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $cache = $json | ConvertFrom-Json
        foreach ($item in @($cache.events)) {
            $item.start = [DateTime]::Parse([string]$item.start)
            $item.end = [DateTime]::Parse([string]$item.end)
            $item.calendarName = Convert-ToAsciiCalendarName ([string]$item.calendarName)
            $item.color = Get-CalendarDisplayColor ([pscustomobject]@{ key=$item.calendarKey; color=$item.color })
        }
        return @($cache.events)
    } catch { return @() }
}

function Save-CachedEvents {
    param($Events)
    try {
        $json = [pscustomobject]@{ savedAt = [DateTime]::UtcNow.ToString('o'); events = @($Events) } | ConvertTo-Json -Depth 8
        Protect-Text $json | Set-Content -LiteralPath $script:CachePath -Encoding ASCII
    } catch { Write-WidgetLog "Could not save event cache. $($_.Exception.Message)" }
}

$script:Settings = Load-Settings
$script:ViewDays = if ([int]$script:Settings.viewDays -eq 3) { 3 } else { 1 }
$script:AllEvents = @(Load-CachedEvents)

function New-Brush {
    param([string]$Color)
    try { return [Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
    catch { return [Windows.Media.Brushes]::DeepPink }
}

function Initialize-CalendarColorComboBox {
    param([Windows.Controls.ComboBox]$ComboBox, [string]$SelectedColor = '#D81B60')
    $ComboBox.Items.Clear()
    $selectedItem = $null
    foreach ($option in $script:CalendarPalette) {
        $item = New-Object Windows.Controls.ComboBoxItem
        $item.Tag = [string]$option.Color
        $panel = New-Object Windows.Controls.StackPanel
        $panel.Orientation = 'Horizontal'
        $swatch = New-Object Windows.Shapes.Rectangle
        $swatch.Width = 14; $swatch.Height = 14; $swatch.RadiusX = 2; $swatch.RadiusY = 2
        $swatch.Margin = '0,0,7,0'; $swatch.Fill = New-Brush ([string]$option.Color)
        $label = New-Object Windows.Controls.TextBlock
        $label.Text = [string]$option.Name; $label.VerticalAlignment = 'Center'
        $panel.Children.Add($swatch) | Out-Null; $panel.Children.Add($label) | Out-Null
        $item.Content = $panel
        $ComboBox.Items.Add($item) | Out-Null
        if ([string]$option.Color -eq $SelectedColor) { $selectedItem = $item }
    }
    if ($selectedItem) { $ComboBox.SelectedItem = $selectedItem }
    elseif ($ComboBox.Items.Count -gt 0) { $ComboBox.SelectedIndex = 0 }
}

function Set-Status {
    param([string]$Text, [ValidateSet('normal','ok','error')][string]$Kind = 'normal')
    if (-not $script:StatusText) { return }
    $script:StatusText.Text = $Text
    $script:StatusDot.Fill = switch ($Kind) {
        'ok' { New-Brush '#2E7D32' }
        'error' { New-Brush '#C2185B' }
        default { New-Brush '#7BC67B' }
    }
}

function Format-EventTime {
    param($Event)
    if ($Event.allDay) { return 'All day' }
    if ([bool]$script:Settings.use12HourTime) {
        return ([DateTime]$Event.start).ToString('h:mm tt', [Globalization.CultureInfo]::InvariantCulture)
    }
    return ([DateTime]$Event.start).ToString('HH:mm')
}

function Add-TextBlock {
    param([Windows.Controls.Panel]$Parent, [string]$Text, [double]$Size = 12, [string]$Color = '#171717', [string]$Weight = 'Normal')
    $block = New-Object Windows.Controls.TextBlock
    $block.Text = $Text
    $block.FontSize = $Size
    $block.Foreground = New-Brush $Color
    $block.FontWeight = [Windows.FontWeights]::$Weight
    $block.TextWrapping = [Windows.TextWrapping]::Wrap
    $Parent.Children.Add($block) | Out-Null
    return $block
}

function New-EventCard {
    param($Event)
    $border = New-Object Windows.Controls.Border
    $border.Margin = '0,0,0,8'
    $border.Padding = '12,10,12,10'
    $border.Background = New-Brush '#FFFFFFFF'
    $border.BorderBrush = New-Brush ([string]$Event.color)
    $border.BorderThickness = '5,0,0,0'
    $border.CornerRadius = '6'
    $border.Cursor = [Windows.Input.Cursors]::Hand
    $border.ToolTip = 'Open this event in its source calendar'

    $grid = New-Object Windows.Controls.Grid
    $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = '62' }))
    $grid.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = '*' }))

    $timePanel = New-Object Windows.Controls.StackPanel
    $timePanel.VerticalAlignment = 'Top'
    Add-TextBlock $timePanel (Format-EventTime $Event) 12 '#AD1457' 'SemiBold' | Out-Null
    if (-not $Event.allDay) {
        $duration = [Math]::Max(0, (([DateTime]$Event.end) - ([DateTime]$Event.start)).TotalMinutes)
        $durationText = if ($duration -ge 60) { '{0:0.#} hr' -f ($duration / 60) } else { '{0:0} min' -f $duration }
        Add-TextBlock $timePanel $durationText 9 '#6A6A6A' 'Normal' | Out-Null
    }
    [Windows.Controls.Grid]::SetColumn($timePanel, 0)
    $grid.Children.Add($timePanel) | Out-Null

    $detailPanel = New-Object Windows.Controls.StackPanel
    Add-TextBlock $detailPanel ([string]$Event.title) 13 '#171717' 'SemiBold' | Out-Null
    $calendarLine = "Calendar: $(Convert-ToAsciiCalendarName ([string]$Event.calendarName))"
    Add-TextBlock $detailPanel $calendarLine 10 ([string]$Event.color) 'SemiBold' | Out-Null
    $place = if ($Event.location) { [string]$Event.location } else { [string]$Event.meetingType }
    if ($place) { Add-TextBlock $detailPanel $place 10 '#555555' 'Normal' | Out-Null }
    [Windows.Controls.Grid]::SetColumn($detailPanel, 1)
    $grid.Children.Add($detailPanel) | Out-Null
    $border.Child = $grid

    $eventUrl = [string]$Event.url
    if ($eventUrl) {
        $border.Add_MouseLeftButtonUp({ try { Start-Process $eventUrl } catch { } }.GetNewClosure())
    }
    return $border
}

function Render-Calendar {
    if (-not $script:EventsPanel) { return }
    $script:EventsPanel.Children.Clear()
    $script:DateHeading.Text = if ($script:ViewDays -eq 1) {
        $script:CurrentDate.ToString('dddd, d MMMM yyyy')
    } else {
        $end = $script:CurrentDate.AddDays(2)
        if ($script:CurrentDate.Month -eq $end.Month) {
            '{0:ddd d} - {1:ddd d MMM yyyy}' -f $script:CurrentDate, $end
        } else {
            '{0:ddd d MMM} - {1:ddd d MMM yyyy}' -f $script:CurrentDate, $end
        }
    }
    $script:DayOneButton.Background = New-Brush $(if ($script:ViewDays -eq 1) { '#D81B60' } else { '#FCE4EC' })
    $script:DayOneButton.Foreground = New-Brush $(if ($script:ViewDays -eq 1) { '#FFFFFF' } else { '#AD1457' })
    $script:DayThreeButton.Background = New-Brush $(if ($script:ViewDays -eq 3) { '#2E7D32' } else { '#E8F5E9' })
    $script:DayThreeButton.Foreground = New-Brush $(if ($script:ViewDays -eq 3) { '#FFFFFF' } else { '#1B5E20' })

    $selectedCount = @($script:Settings.selectedCalendars).Count
    if ($selectedCount -eq 0) {
        $welcome = New-Object Windows.Controls.Border
        $welcome.Margin = '2,22,2,0'; $welcome.Padding = '20'; $welcome.CornerRadius = '10'
        $welcome.Background = New-Brush '#FFF5F8'; $welcome.BorderBrush = New-Brush '#F8BBD0'; $welcome.BorderThickness = '1'
        $panel = New-Object Windows.Controls.StackPanel
        Add-TextBlock $panel 'Your glanceable schedule starts here.' 18 '#AD1457' 'Bold' | Out-Null
        $body = Add-TextBlock $panel "Select Settings, connect Google or Outlook, or add a private ICS address. Choose up to 20 calendars; the widget refreshes them every 10 minutes." 12 '#333333' 'Normal'
        $body.Margin = '0,8,0,12'
        $button = New-Object Windows.Controls.Button
        $button.Content = 'Open settings'; $button.Padding = '14,8'; $button.HorizontalAlignment = 'Left'
        $button.Background = New-Brush '#D81B60'; $button.Foreground = New-Brush '#FFFFFF'; $button.BorderThickness = '0'
        $button.Add_Click({ Show-SettingsWindow })
        $panel.Children.Add($button) | Out-Null
        $welcome.Child = $panel
        $script:EventsPanel.Children.Add($welcome) | Out-Null
        Set-Status 'No calendars selected' 'normal'
        return
    }

    for ($offset = 0; $offset -lt $script:ViewDays; $offset++) {
        $day = $script:CurrentDate.AddDays($offset)
        $dayEvents = @($script:AllEvents | Where-Object {
            ([DateTime]$_.start) -lt $day.AddDays(1) -and ([DateTime]$_.end) -gt $day
        } | Sort-Object @{ Expression = { -not [bool]$_.allDay } }, @{ Expression = { [DateTime]$_.start } }, title)

        $headingBorder = New-Object Windows.Controls.Border
        $headingBorder.Margin = if ($offset -eq 0) { '0,4,0,8' } else { '0,16,0,8' }
        $headingBorder.Padding = '4,5'; $headingBorder.BorderBrush = New-Brush '#7BC67B'; $headingBorder.BorderThickness = '0,0,0,2'
        $heading = New-Object Windows.Controls.TextBlock
        $heading.Text = if ($day.Date -eq [DateTime]::Today) { 'TODAY | ' + $day.ToString('dddd d MMMM') } else { $day.ToString('dddd d MMMM').ToUpperInvariant() }
        $heading.FontSize = 12; $heading.FontWeight = 'Bold'; $heading.Foreground = New-Brush '#1B5E20'
        $headingBorder.Child = $heading
        $script:EventsPanel.Children.Add($headingBorder) | Out-Null

        if ($dayEvents.Count -eq 0) {
            $empty = New-Object Windows.Controls.TextBlock
            $empty.Text = 'Nothing scheduled'; $empty.Foreground = New-Brush '#777777'; $empty.FontStyle = 'Italic'; $empty.Margin = '12,6,0,10'
            $script:EventsPanel.Children.Add($empty) | Out-Null
        } else {
            foreach ($event in $dayEvents) { $script:EventsPanel.Children.Add((New-EventCard $event)) | Out-Null }
        }
    }
}

function Sync-Calendars {
    param([switch]$Quiet)
    if ($script:IsSyncing) { return }
    if (@($script:Settings.selectedCalendars).Count -eq 0) { return }
    $script:IsSyncing = $true
    Set-Status 'Refreshing...' 'normal'
    try {
        $from = [DateTime]::Today.AddDays(-7)
        $to = [DateTime]::Today.AddDays(45)
        $fresh = @()
        $failures = 0
        foreach ($calendar in @($script:Settings.selectedCalendars)) {
            [System.Windows.Forms.Application]::DoEvents()
            try { $fresh += @(Get-CalendarEvents $calendar $from $to) }
            catch {
                $failures++
                Write-WidgetLog "Sync failed for $($calendar.name): $($_.Exception.Message)"
            }
        }
        if ($fresh.Count -gt 0 -or $failures -eq 0) {
            $script:AllEvents = @($fresh)
            Save-CachedEvents $script:AllEvents
        }
        Render-Calendar
        if ($failures -eq 0) { Set-Status ("Updated {0:HH:mm}" -f [DateTime]::Now) 'ok' }
        else { Set-Status "$failures calendar(s) could not refresh" 'error' }
    } catch {
        Write-WidgetLog "Refresh error: $($_.Exception.Message)"
        Set-Status 'Could not refresh; showing saved events' 'error'
    } finally {
        $script:IsSyncing = $false
    }
}

function Show-AddAccountDialog {
    param([ValidateSet('google','microsoft')][string]$Provider)
    $providerName = if ($Provider -eq 'google') { 'Google Calendar' } else { 'Outlook.com' }
    $helpText = if ($Provider -eq 'google') {
        "Paste the Desktop app Client ID and Client secret from Google Cloud. If Google says the app is not approved, confirm that this exact Google address is listed under Audience > Test users."
    } else {
        "Paste the Application (client) ID from Microsoft Entra. See SETUP_GUIDE.html for the illustrated steps."
    }
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Connect $providerName" Height="470" Width="540" WindowStartupLocation="CenterOwner" ResizeMode="NoResize" Background="#FFF7F9" FontFamily="Segoe UI">
  <Grid Margin="24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Connect $providerName" FontSize="22" FontWeight="Bold" Foreground="#AD1457"/>
    <TextBlock Grid.Row="1" Margin="0,10,0,18" Text="$helpText" TextWrapping="Wrap" Foreground="#333333"/>
    <StackPanel Grid.Row="2" Margin="0,0,0,14"><TextBlock Text="Client ID" FontWeight="SemiBold"/><TextBox Name="ClientIdBox" Margin="0,5,0,0" Padding="8" FontSize="13"/></StackPanel>
    <StackPanel Grid.Row="3" Name="SecretPanel" Margin="0,0,0,14"><TextBlock Text="Client secret" FontWeight="SemiBold"/><PasswordBox Name="SecretBox" Margin="0,5,0,0" Padding="8" FontSize="13"/></StackPanel>
    <TextBlock Grid.Row="4" Name="ErrorText" TextWrapping="Wrap" Foreground="#C2185B"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="CancelButton" Content="Cancel" Padding="16,8" Margin="0,0,8,0"/>
      <Button Name="ConnectButton" Content="Open secure sign-in" Padding="16,8" Background="#D81B60" Foreground="White" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader ([xml]$dialogXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $script:Window
    $clientBox = $dialog.FindName('ClientIdBox'); $secretBox = $dialog.FindName('SecretBox')
    $secretPanel = $dialog.FindName('SecretPanel'); $errorText = $dialog.FindName('ErrorText')
    $cancelButton = $dialog.FindName('CancelButton'); $connectButton = $dialog.FindName('ConnectButton')
    if ($Provider -eq 'microsoft') { $secretPanel.Visibility = 'Collapsed' }
    $cancelButton.Add_Click({
        if ($script:OAuthInProgress) {
            $script:OAuthCancelled = $true
            if ($script:OAuthListener) { try { $script:OAuthListener.Stop() } catch { } }
            $errorText.Text = 'Cancelling sign-in...'
        } else { $dialog.Close() }
    })
    $connectButton.Add_Click({
        $clientId = $clientBox.Text.Trim()
        $clientSecret = if ($Provider -eq 'google') { $secretBox.Password.Trim() } else { '' }
        if (-not $clientId) { $errorText.Text = 'A Client ID is required.'; return }
        $dialog.Cursor = [Windows.Input.Cursors]::Wait
        $connectButton.IsEnabled = $false
        $cancelButton.Content = 'Cancel sign-in'
        $errorText.Text = 'Your browser is opening. Complete sign-in there...'
        try {
            Add-CalendarAccount -Provider $Provider -ClientId $clientId -ClientSecret $clientSecret | Out-Null
            $dialog.DialogResult = $true
            $dialog.Close()
        } catch {
            $errorText.Text = $_.Exception.Message
            Write-WidgetLog "Account connection failed: $($_.Exception.Message)"
        } finally {
            $dialog.Cursor = [Windows.Input.Cursors]::Arrow
            $connectButton.IsEnabled = $true
            $cancelButton.Content = 'Cancel'
        }
    }.GetNewClosure())
    return $dialog.ShowDialog()
}

function Show-AddIcsCalendarDialog {
    $dialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Add Private ICS Calendar" Height="510" Width="590" WindowStartupLocation="CenterOwner" ResizeMode="NoResize" Background="#FFF7F9" FontFamily="Segoe UI">
  <Grid Margin="24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Add a private ICS calendar" FontSize="22" FontWeight="Bold" Foreground="#AD1457"/>
    <TextBlock Grid.Row="1" Margin="0,7,0,18" Text="Use a secret, read-only iCal address from Google, Outlook, or another calendar service. The address and downloaded event cache are encrypted for your Windows account." TextWrapping="Wrap" Foreground="#444444"/>
    <TextBlock Grid.Row="2" Text="Calendar name" FontWeight="SemiBold"/>
    <TextBox Grid.Row="3" Name="IcsNameBox" Height="32" Margin="0,5,0,13" Padding="7,4" MaxLength="80"/>
    <TextBlock Grid.Row="4" Text="Secret iCal / ICS address" FontWeight="SemiBold"/>
    <PasswordBox Grid.Row="5" Name="IcsUrlBox" Height="32" Margin="0,5,0,10" Padding="7,4"/>
    <StackPanel Grid.Row="6">
      <TextBlock Text="Color" FontWeight="SemiBold" Margin="0,0,0,5"/>
      <ComboBox Name="IcsColorBox" Height="31"/>
      <TextBlock Name="IcsErrorText" Margin="0,13,0,0" Foreground="#C2185B" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Grid.Row="7" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="IcsCancelButton" Content="Cancel" Padding="17,8" Margin="0,0,8,0"/>
      <Button Name="IcsAddButton" Content="Add calendar" Padding="17,8" Background="#D81B60" Foreground="White" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader ([xml]$dialogXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader); $dialog.Owner = $script:Window
    $nameBox = $dialog.FindName('IcsNameBox'); $urlBox = $dialog.FindName('IcsUrlBox'); $colorBox = $dialog.FindName('IcsColorBox')
    Initialize-CalendarColorComboBox -ComboBox $colorBox -SelectedColor '#D81B60'
    $errorText = $dialog.FindName('IcsErrorText'); $addButton = $dialog.FindName('IcsAddButton'); $cancelButton = $dialog.FindName('IcsCancelButton')
    $cancelButton.Add_Click({ $dialog.Close() })
    $addButton.Add_Click({
        $icsCalendarCount = 0
        if ($script:Settings -and $script:Settings.PSObject.Properties['icsCalendars']) {
            $icsCalendarCount = @($script:Settings.icsCalendars | Where-Object { $null -ne $_ }).Count
        }
        $calendarLimit = [int]$script:MaxCalendars
        if ($calendarLimit -lt 1) { $calendarLimit = 20 }
        if ($icsCalendarCount -ge $calendarLimit) { $errorText.Text = 'The 20-calendar limit has been reached.'; return }
        $name = Convert-ToAsciiCalendarName ($nameBox.Text.Trim())
        $feedUrl = $urlBox.Password.Trim()
        if ($feedUrl -match '^webcal://') { $feedUrl = 'https://' + $feedUrl.Substring(9) }
        [Uri]$uri = $null
        if (-not [Uri]::TryCreate($feedUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') {
            $errorText.Text = 'Paste a complete HTTPS secret iCal address.'; return
        }
        $dialog.Cursor = [Windows.Input.Cursors]::Wait; $addButton.IsEnabled = $false
        $errorText.Text = 'Checking the private calendar address...'
        try {
            $test = Invoke-WebRequest -UseBasicParsing -Uri $feedUrl -TimeoutSec 30 -Headers @{ 'User-Agent'='WatermelonCalendarWidget/1.3' }
            if ([string]$test.Content -notmatch 'BEGIN:VCALENDAR') { throw 'That address did not return an iCalendar feed.' }
            $id = [Guid]::NewGuid().ToString('N')
            $color = [string](($colorBox.SelectedItem).Tag)
            $calendar = [pscustomobject]@{
                key = "ics|$id"; accountId = "ics|$id"; provider = 'ics'; calendarId = $id
                name = $name; accountLabel = 'Private ICS'; color = $color; primary = $false
                feedUrl = Protect-Text $feedUrl
            }
            $script:Settings.icsCalendars = @($script:Settings.icsCalendars) + $calendar
            if (@($script:Settings.selectedCalendars).Count -lt $script:MaxCalendars) {
                $script:Settings.selectedCalendars = @($script:Settings.selectedCalendars) + $calendar
            }
            Save-Settings
            $dialog.DialogResult = $true; $dialog.Close()
        } catch {
            $errorText.Text = "The private calendar could not be added. $($_.Exception.Message)"
        } finally {
            $dialog.Cursor = [Windows.Input.Cursors]::Arrow; $addButton.IsEnabled = $true
        }
    })
    return $dialog.ShowDialog()
}

function Get-AllAvailableCalendars {
    $all = @($script:Settings.icsCalendars | ForEach-Object {
        $_.name = Convert-ToAsciiCalendarName ([string]$_.name)
        $_
    })
    foreach ($account in @($script:Settings.accounts)) {
        try { $all += @(Get-AccountCalendars $account) }
        catch { Write-WidgetLog "Could not list calendars for $($account.label): $($_.Exception.Message)" }
    }
    foreach ($calendar in $all) { $calendar.color = Get-CalendarDisplayColor $calendar }
    return @($all)
}

function Show-SettingsWindow {
    $xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Watermelon Calendar Settings" Height="700" Width="760" MinHeight="600" MinWidth="680" WindowStartupLocation="CenterOwner" Background="#FFF7F9" FontFamily="Segoe UI">
  <Grid Margin="22">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Calendar settings" FontSize="24" FontWeight="Bold" Foreground="#AD1457"/>
    <TextBlock Grid.Row="1" Margin="0,5,0,16" Text="Read-only access | refreshes every 10 minutes | maximum 20 selected calendars" Foreground="#555555"/>
    <Grid Grid.Row="2" Margin="0,0,0,14">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <ListBox Name="AccountList" Grid.Column="0" Height="92" DisplayMemberPath="display"/>
      <StackPanel Grid.Column="1" Margin="10,0,6,0">
        <Button Name="AddGoogle" Content="+ Google" Padding="12,7" Background="#D81B60" Foreground="White" BorderThickness="0"/>
        <Button Name="AddIcs" Content="+ Private ICS" Margin="0,8,0,0" Padding="12,7" Background="#AD1457" Foreground="White" BorderThickness="0"/>
      </StackPanel>
      <StackPanel Grid.Column="2">
        <Button Name="AddOutlook" Content="+ Outlook" Padding="12,7" Background="#2E7D32" Foreground="White" BorderThickness="0"/>
        <Button Name="RemoveAccount" Content="Remove" Margin="0,8,0,0" Padding="12,6"/>
      </StackPanel>
    </Grid>
    <Border Grid.Row="3" Background="White" BorderBrush="#F8BBD0" BorderThickness="1" CornerRadius="8" Padding="12">
      <Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <DockPanel Grid.Row="0" Margin="0,0,0,8"><TextBlock DockPanel.Dock="Right" Text="DISPLAY COLOR" Foreground="#666666" FontSize="10" FontWeight="SemiBold" Margin="0,0,12,0"/><TextBlock Name="CountText" DockPanel.Dock="Right" Foreground="#AD1457" FontWeight="SemiBold" Margin="0,0,25,0"/><TextBlock Text="Calendars to display" FontWeight="Bold" FontSize="15"/></DockPanel>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel Name="CalendarPanel"/></ScrollViewer>
      </Grid>
    </Border>
    <StackPanel Grid.Row="4" Margin="0,10,0,10">
      <CheckBox Name="Use12HourTime" Content="Use 12-hour time with AM/PM (example: 2:30 PM)" Foreground="#333333" FontWeight="SemiBold"/>
      <TextBlock Name="SettingsStatus" Margin="0,7,0,0" Foreground="#C2185B" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="HelpSettings" Content="Setup guide" Padding="17,8" Margin="0,0,18,0" Foreground="#2E7D32"/>
      <Button Name="CancelSettings" Content="Cancel" Padding="17,8" Margin="0,0,8,0"/>
      <Button Name="SaveSettings" Content="Save and refresh" Padding="17,8" Background="#D81B60" Foreground="White" BorderThickness="0"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $script:Window
    $accountList = $dialog.FindName('AccountList')
    $calendarPanel = $dialog.FindName('CalendarPanel')
    $countText = $dialog.FindName('CountText')
    $status = $dialog.FindName('SettingsStatus')
    $use12HourTime = $dialog.FindName('Use12HourTime')
    $use12HourTime.IsChecked = [bool]$script:Settings.use12HourTime
    $checkboxes = New-Object Collections.ArrayList
    $calendarRows = New-Object Collections.ArrayList

    function Update-AccountListLocal {
        $accountList.Items.Clear()
        foreach ($account in @($script:Settings.accounts)) {
            $provider = if ($account.provider -eq 'google') { 'Google' } else { 'Outlook' }
            $accountList.Items.Add([pscustomobject]@{ id=$account.id; kind='account'; display="$provider | $($account.label)" }) | Out-Null
        }
        foreach ($calendar in @($script:Settings.icsCalendars)) {
            $plainName = Convert-ToAsciiCalendarName ([string]$calendar.name)
            $accountList.Items.Add([pscustomobject]@{ id=$calendar.calendarId; key=$calendar.key; kind='ics'; display="Private ICS | $plainName" }) | Out-Null
        }
    }
    function Update-CountLocal {
        $checked = @($checkboxes | Where-Object { $_.IsChecked }).Count
        $countText.Text = "$checked / $($script:MaxCalendars) selected"
        if ($checked -gt $script:MaxCalendars) { $status.Text = 'Please deselect calendars until 20 or fewer remain.' }
        elseif ($status.Text -like 'Please deselect*') { $status.Text = '' }
    }
    function Load-CalendarsLocal {
        $calendarPanel.Children.Clear(); $checkboxes.Clear(); $calendarRows.Clear()
        $hasSources = (@($script:Settings.accounts).Count + @($script:Settings.icsCalendars).Count) -gt 0
        $status.Text = if ($hasSources) { 'Loading calendars...' } else { 'Add Google, Outlook, or a private ICS calendar to begin.' }
        [System.Windows.Forms.Application]::DoEvents()
        $available = @(Get-AllAvailableCalendars)
        $selectedKeys = @($script:Settings.selectedCalendars | ForEach-Object { $_.key })
        foreach ($calendar in $available | Sort-Object accountLabel, @{ Expression = { -not $_.primary } }, name) {
            $row = New-Object Windows.Controls.Grid
            $row.Margin = '2,3,2,3'
            $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width='*' }))
            $row.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width='185' }))
            $check = New-Object Windows.Controls.CheckBox
            $check.Margin = '4,3'; $check.Padding = '3'; $check.Tag = $calendar
            $check.IsChecked = $selectedKeys -contains $calendar.key
            $check.ToolTip = $calendar.accountLabel
            $content = New-Object Windows.Controls.StackPanel
            $content.Orientation = 'Horizontal'
            $swatch = New-Object Windows.Shapes.Ellipse
            $swatch.Width = 11; $swatch.Height = 11; $swatch.Margin = '0,0,8,0'; $swatch.Fill = New-Brush $calendar.color
            $label = New-Object Windows.Controls.TextBlock
            $label.Text = "$(Convert-ToAsciiCalendarName ([string]$calendar.name))  |  $($calendar.accountLabel)"; $label.FontSize = 12
            $content.Children.Add($swatch) | Out-Null; $content.Children.Add($label) | Out-Null
            $check.Content = $content
            $check.Add_Checked({ Update-CountLocal }); $check.Add_Unchecked({ Update-CountLocal })
            [Windows.Controls.Grid]::SetColumn($check, 0)
            $row.Children.Add($check) | Out-Null

            $colorBox = New-Object Windows.Controls.ComboBox
            $colorBox.Height = 30; $colorBox.Margin = '8,0,2,0'; $colorBox.VerticalAlignment = 'Center'
            Initialize-CalendarColorComboBox -ComboBox $colorBox -SelectedColor ([string]$calendar.color)
            $colorBox.Tag = [pscustomobject]@{ Swatch=$swatch }
            $colorBox.Add_SelectionChanged({
                param($sender, $eventArgs)
                if ($sender.SelectedItem -and $sender.Tag -and $sender.Tag.Swatch) {
                    $sender.Tag.Swatch.Fill = New-Brush ([string]$sender.SelectedItem.Tag)
                }
            })
            [Windows.Controls.Grid]::SetColumn($colorBox, 1)
            $row.Children.Add($colorBox) | Out-Null

            $checkboxes.Add($check) | Out-Null
            $calendarRows.Add([pscustomobject]@{ CheckBox=$check; Calendar=$calendar; ColorBox=$colorBox }) | Out-Null
            $calendarPanel.Children.Add($row) | Out-Null
        }
        $status.Text = if ($available.Count) { '' } elseif ($hasSources) { 'No calendars could be loaded. Reconnect the account or re-add the private ICS address.' } else { $status.Text }
        Update-CountLocal
    }

    $dialog.FindName('AddGoogle').Add_Click({
        if (Show-AddAccountDialog 'google') { Update-AccountListLocal; Load-CalendarsLocal }
    })
    $dialog.FindName('AddOutlook').Add_Click({
        if (Show-AddAccountDialog 'microsoft') { Update-AccountListLocal; Load-CalendarsLocal }
    })
    $dialog.FindName('AddIcs').Add_Click({
        if (Show-AddIcsCalendarDialog) { Update-AccountListLocal; Load-CalendarsLocal }
    })
    $dialog.FindName('RemoveAccount').Add_Click({
        $chosen = $accountList.SelectedItem
        if (-not $chosen) { $status.Text = 'Select an account or private ICS calendar to remove.'; return }
        $answer = [System.Windows.MessageBox]::Show("Remove this source and its calendars from the widget?`n`n$($chosen.display)", 'Remove calendar source', 'YesNo', 'Question')
        if ($answer -eq 'Yes') {
            if ($chosen.kind -eq 'ics') {
                $script:Settings.icsCalendars = @($script:Settings.icsCalendars | Where-Object { $_.key -ne $chosen.key })
                $script:Settings.selectedCalendars = @($script:Settings.selectedCalendars | Where-Object { $_.key -ne $chosen.key })
                $script:Settings.calendarColorOverrides = @($script:Settings.calendarColorOverrides | Where-Object { $_.key -ne $chosen.key })
            } else {
                $removedKeys = @($calendarRows | Where-Object { $_.Calendar.accountId -eq $chosen.id } | ForEach-Object { [string]$_.Calendar.key })
                $script:Settings.accounts = @($script:Settings.accounts | Where-Object { $_.id -ne $chosen.id })
                $script:Settings.selectedCalendars = @($script:Settings.selectedCalendars | Where-Object { $_.accountId -ne $chosen.id })
                $script:Settings.calendarColorOverrides = @($script:Settings.calendarColorOverrides | Where-Object { $removedKeys -notcontains [string]$_.key })
            }
            Save-Settings; Update-AccountListLocal; Load-CalendarsLocal
        }
    })
    $dialog.FindName('CancelSettings').Add_Click({ $dialog.Close() })
    $dialog.FindName('HelpSettings').Add_Click({
        $guide = Join-Path $script:AppDir 'SETUP_GUIDE.html'
        if (-not (Test-Path -LiteralPath $guide)) { $guide = Join-Path $PSScriptRoot 'SETUP_GUIDE.html' }
        if (Test-Path -LiteralPath $guide) { Start-Process $guide }
    })
    $dialog.FindName('SaveSettings').Add_Click({
        foreach ($calendarRow in $calendarRows) {
            $selectedColorItem = $calendarRow.ColorBox.SelectedItem
            if ($selectedColorItem) {
                $selectedColor = [string]$selectedColorItem.Tag
                $calendarRow.Calendar.color = $selectedColor
                Set-CalendarColorOverride -Key ([string]$calendarRow.Calendar.key) -Color $selectedColor
            }
        }
        $chosen = @($calendarRows | Where-Object { $_.CheckBox.IsChecked } | ForEach-Object { $_.Calendar })
        if ($chosen.Count -gt $script:MaxCalendars) { $status.Text = 'Please select no more than 20 calendars.'; return }
        $script:Settings.selectedCalendars = @($chosen)
        $script:Settings.use12HourTime = [bool]$use12HourTime.IsChecked
        foreach ($event in @($script:AllEvents)) {
            $event.color = Get-CalendarDisplayColor ([pscustomobject]@{ key=$event.calendarKey; color=$event.color })
        }
        Save-Settings
        $dialog.DialogResult = $true; $dialog.Close()
    })
    Update-AccountListLocal
    $dialog.Add_ContentRendered({ Load-CalendarsLocal })
    $saved = $dialog.ShowDialog()
    if ($saved) { Render-Calendar; Sync-Calendars }
}

function Set-WindowTopRight {
    $area = [System.Windows.SystemParameters]::WorkArea
    $script:Window.Left = $area.Right - $script:Window.Width - 18
    $script:Window.Top = $area.Top + 18
}

function Update-PinState {
    param([switch]$NoSave)
    if (-not $script:PinButton -or -not $script:Window) { return }
    $isPinned = [bool]$script:PinButton.IsChecked
    $script:Window.Topmost = $isPinned
    $script:PinButton.Background = New-Brush $(if ($isPinned) { '#2E7D32' } else { '#00000000' })
    $script:PinButton.Opacity = $(if ($isPinned) { 1.0 } else { 0.58 })
    $script:PinButton.ToolTip = $(if ($isPinned) { 'Pinned above other windows. Click to allow windows on top.' } else { 'Other windows may cover the calendar. Click to pin it on top.' })
    $script:Settings.pinToTop = $isPinned
    if (-not $NoSave) { Save-Settings }
}

function Save-WindowPlacement {
    if ($script:Window.WindowState -eq 'Normal') {
        $script:Settings.left = [double]$script:Window.Left
        $script:Settings.top = [double]$script:Window.Top
        $script:Settings.width = [double]$script:Window.Width
        $script:Settings.height = [double]$script:Window.Height
        Save-Settings
    }
}

function Show-Widget {
    $script:Window.Show()
    $script:Window.WindowState = 'Normal'
    $script:Window.Activate() | Out-Null
}

function Hide-Widget {
    Save-WindowPlacement
    $script:Window.Hide()
}

function Exit-Widget {
    $script:WindowClosingForExit = $true
    Save-WindowPlacement
    if ($script:ShowRequestTimer) { $script:ShowRequestTimer.Stop() }
    if ($script:ShowRequestEvent) { $script:ShowRequestEvent.Dispose() }
    if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() }
    Remove-Item -LiteralPath (Join-Path $script:DataDir 'widget.pid') -Force -ErrorAction SilentlyContinue
    if ($script:SingleInstanceMutex) { $script:SingleInstanceMutex.ReleaseMutex(); $script:SingleInstanceMutex.Dispose() }
    $script:Window.Close()
}

$mainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="Watermelon Calendar Widget" Width="430" Height="720" MinWidth="350" MinHeight="440" WindowStyle="SingleBorderWindow" AllowsTransparency="False" Background="#FFF7F9" Topmost="True" ShowInTaskbar="True" ResizeMode="CanResize" FontFamily="Segoe UI">
  <Border Background="#FFF7F9" BorderBrush="#D81B60" BorderThickness="1" SnapsToDevicePixels="True">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Border Name="DragBar" Grid.Row="0" Background="#AD1457" Padding="12,10">
        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal"><Ellipse Width="11" Height="11" Fill="#7BC67B" Margin="0,0,8,0"/><TextBlock Text="WATERMELON CALENDAR" Foreground="White" FontWeight="Bold" FontSize="12" VerticalAlignment="Center"/></StackPanel>
          <Button Name="RefreshButton" Grid.Column="1" ToolTip="Refresh now" Style="{x:Null}" Background="Transparent" BorderThickness="0" Padding="8,2">
            <Viewbox Width="18" Height="18"><Path Fill="White" Data="M17.65,6.35 C16.2,4.9 14.21,4 12,4 C7.58,4 4,7.58 4,12 C4,16.42 7.58,20 12,20 C15.73,20 18.84,17.45 19.73,14 L17.65,14 C16.83,16.33 14.61,18 12,18 C8.69,18 6,15.31 6,12 C6,8.69 8.69,6 12,6 C13.66,6 15.14,6.69 16.22,7.78 L13,11 L20,11 L20,4 Z"/></Viewbox>
          </Button>
          <ToggleButton Name="PinButton" Grid.Column="2" IsChecked="True" ToolTip="Pinned above other windows" Style="{x:Null}" Background="#2E7D32" BorderThickness="0" Padding="8,2">
            <Viewbox Width="18" Height="18"><Path Fill="White" Data="M7,3 L17,3 L16,9 L20,13 L13,13 L13,21 L11,21 L11,13 L4,13 L8,9 Z"/></Viewbox>
          </ToggleButton>
          <Button Name="SettingsButton" Grid.Column="3" ToolTip="Settings" Style="{x:Null}" Background="Transparent" BorderThickness="0" Padding="8,2">
            <Viewbox Width="18" Height="18"><Canvas Width="24" Height="24">
              <Path Stroke="White" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M4,6 L20,6 M4,12 L20,12 M4,18 L20,18"/>
              <Ellipse Canvas.Left="7" Canvas.Top="3" Width="6" Height="6" Fill="#AD1457" Stroke="White" StrokeThickness="2"/>
              <Ellipse Canvas.Left="13" Canvas.Top="9" Width="6" Height="6" Fill="#AD1457" Stroke="White" StrokeThickness="2"/>
              <Ellipse Canvas.Left="5" Canvas.Top="15" Width="6" Height="6" Fill="#AD1457" Stroke="White" StrokeThickness="2"/>
            </Canvas></Viewbox>
          </Button>
        </Grid>
      </Border>
      <Grid Grid.Row="1" Margin="14,13,14,8"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button Name="PreviousButton" Width="32" Height="32" Background="#FCE4EC" BorderThickness="0" ToolTip="Previous date">
          <Viewbox Width="15" Height="15"><Path Stroke="#AD1457" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M15,18 L9,12 L15,6"/></Viewbox>
        </Button>
        <TextBlock Name="DateHeading" Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center" TextAlignment="Center" FontSize="15" FontWeight="Bold" Foreground="#171717" TextWrapping="Wrap"/>
        <Button Name="NextButton" Grid.Column="2" Width="32" Height="32" Background="#FCE4EC" BorderThickness="0" ToolTip="Next date">
          <Viewbox Width="15" Height="15"><Path Stroke="#AD1457" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Data="M9,18 L15,12 L9,6"/></Viewbox>
        </Button>
      </Grid>
      <Grid Grid.Row="2" Margin="14,0,14,10"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <Button Name="DayOneButton" Content="1 DAY" Padding="12,6" BorderThickness="0" FontWeight="SemiBold"/>
        <Button Name="DayThreeButton" Grid.Column="1" Content="3 DAYS" Margin="7,0,0,0" Padding="12,6" BorderThickness="0" FontWeight="SemiBold"/>
        <Button Name="TodayButton" Grid.Column="3" Content="TODAY" Padding="12,6" Background="White" Foreground="#AD1457" BorderBrush="#F8BBD0" FontWeight="SemiBold"/>
      </Grid>
      <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="14,0,10,0"><StackPanel Name="EventsPanel"/></ScrollViewer>
      <Border Grid.Row="4" Background="#FCE4EC" Padding="12,7">
        <DockPanel><TextBlock DockPanel.Dock="Right" Text="READ ONLY" FontSize="9" FontWeight="Bold" Foreground="#AD1457"/><StackPanel Orientation="Horizontal"><Ellipse Name="StatusDot" Width="8" Height="8" Fill="#7BC67B" Margin="0,0,7,0"/><TextBlock Name="StatusText" Text="Ready" FontSize="10" Foreground="#555555"/></StackPanel></DockPanel>
      </Border>
    </Grid>
  </Border>
</Window>
"@

$mainReader = New-Object Xml.XmlNodeReader ([xml]$mainXaml)
$script:Window = [Windows.Markup.XamlReader]::Load($mainReader)
$iconPath = Join-Path $script:AppDir 'assets\watermelon-calendar.ico'
if (-not (Test-Path -LiteralPath $iconPath)) { $iconPath = Join-Path $PSScriptRoot 'assets\watermelon-calendar.ico' }
if (Test-Path -LiteralPath $iconPath) {
    try { $script:Window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath) } catch { }
}
$script:EventsPanel = $script:Window.FindName('EventsPanel')
$script:DateHeading = $script:Window.FindName('DateHeading')
$script:StatusText = $script:Window.FindName('StatusText')
$script:StatusDot = $script:Window.FindName('StatusDot')
$script:DayOneButton = $script:Window.FindName('DayOneButton')
$script:DayThreeButton = $script:Window.FindName('DayThreeButton')
$script:PinButton = $script:Window.FindName('PinButton')

$savedWidth = [double]$script:Settings.width; $savedHeight = [double]$script:Settings.height
if ($savedWidth -ge 350) { $script:Window.Width = $savedWidth }
if ($savedHeight -ge 440) { $script:Window.Height = $savedHeight }
$script:Window.Opacity = [Math]::Max(0.72, [Math]::Min(1.0, [double]$script:Settings.opacity))
if ($null -ne $script:Settings.left -and $null -ne $script:Settings.top) {
    $script:Window.Left = [double]$script:Settings.left; $script:Window.Top = [double]$script:Settings.top
} else { Set-WindowTopRight }
$script:PinButton.IsChecked = [bool]$script:Settings.pinToTop
Update-PinState -NoSave

$script:Window.FindName('DragBar').Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) { Set-WindowTopRight } else { try { $script:Window.DragMove() } catch { } }
})
$script:Window.FindName('PreviousButton').Add_Click({ $script:CurrentDate = $script:CurrentDate.AddDays(-$script:ViewDays); Render-Calendar })
$script:Window.FindName('NextButton').Add_Click({ $script:CurrentDate = $script:CurrentDate.AddDays($script:ViewDays); Render-Calendar })
$script:Window.FindName('TodayButton').Add_Click({ $script:CurrentDate = [DateTime]::Today; Render-Calendar })
$script:Window.FindName('DayOneButton').Add_Click({ $script:ViewDays = 1; $script:Settings.viewDays = 1; Save-Settings; Render-Calendar })
$script:Window.FindName('DayThreeButton').Add_Click({ $script:ViewDays = 3; $script:Settings.viewDays = 3; Save-Settings; Render-Calendar })
$script:Window.FindName('RefreshButton').Add_Click({ Sync-Calendars })
$script:PinButton.Add_Click({ Update-PinState })
$script:Window.FindName('SettingsButton').Add_Click({ Show-SettingsWindow })
$script:Window.Add_LocationChanged({ if ($script:Window.IsVisible) { Save-WindowPlacement } })
$script:Window.Add_SizeChanged({ if ($script:Window.IsVisible) { Save-WindowPlacement } })
$script:Window.Add_StateChanged({ if ($script:Window.WindowState -eq 'Minimized') { Hide-Widget } })
$script:Window.Add_Closing({
    if (-not $script:WindowClosingForExit) { $_.Cancel = $true; Hide-Widget }
})

$script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
$script:TrayIcon.Text = 'Watermelon Calendar Widget'
if (Test-Path -LiteralPath $iconPath) { $script:TrayIcon.Icon = [System.Drawing.Icon]::new($iconPath) }
else { $script:TrayIcon.Icon = [System.Drawing.SystemIcons]::Information }
$script:TrayIcon.Visible = $true
$trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
$showItem = $trayMenu.Items.Add('Show widget')
$refreshItem = $trayMenu.Items.Add('Refresh now')
$settingsItem = $trayMenu.Items.Add('Settings')
$trayMenu.Items.Add('-') | Out-Null
$exitItem = $trayMenu.Items.Add('Exit')
$showItem.Add_Click({ Show-Widget }); $refreshItem.Add_Click({ Show-Widget; Sync-Calendars })
$settingsItem.Add_Click({ Show-Widget; Show-SettingsWindow }); $exitItem.Add_Click({ Exit-Widget })
$script:TrayIcon.ContextMenuStrip = $trayMenu
$script:TrayIcon.Add_DoubleClick({ Show-Widget })

$script:ShowRequestTimer = New-Object Windows.Threading.DispatcherTimer
$script:ShowRequestTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$script:ShowRequestTimer.Add_Tick({
    if ($script:ShowRequestEvent -and $script:ShowRequestEvent.WaitOne(0)) { Show-Widget }
})
$script:ShowRequestTimer.Start()

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes($script:RefreshMinutes)
$timer.Add_Tick({ Sync-Calendars -Quiet })
$timer.Start()

Render-Calendar
$script:Window.Add_ContentRendered({
    if (@($script:Settings.selectedCalendars).Count -gt 0) { Sync-Calendars -Quiet }
})
if ($StartMinimized) { $script:Window.Add_ContentRendered({ Hide-Widget }) }
$null = $script:Window.ShowDialog()
