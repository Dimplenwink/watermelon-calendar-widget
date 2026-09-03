$ErrorActionPreference = 'Stop'

$version = '1.4.4'
$source = $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'WatermelonCalendarWidget'
$assetsTarget = Join-Path $target 'assets'
$marker = Join-Path $env:LOCALAPPDATA 'WatermelonCalendarWidget.uninstalling'
$logPath = Join-Path $env:TEMP 'WatermelonCalendarWidget-Install.log'

function Write-InstallLog {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value ("{0:u} {1}" -f [DateTime]::Now, $Message) -Encoding UTF8
}

try {
    Set-Content -LiteralPath $logPath -Value "Watermelon Calendar Widget $version installation log" -Encoding UTF8
    Write-Host ''
    Write-Host " WATERMELON CALENDAR WIDGET $version" -ForegroundColor Magenta
    Write-Host ' Installing for your Windows account...'
    Write-Host ''

    $mainSource = Join-Path $source 'WatermelonCalendarWidget.ps1'
    if (-not (Test-Path -LiteralPath $mainSource)) {
        throw 'The installer files are incomplete. Extract the entire ZIP file before running Install.cmd.'
    }

    $parseTokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($mainSource, [ref]$parseTokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        $firstParseError = [string]$parseErrors[0].Message
        throw "The widget program did not pass the Windows PowerShell parser check: $firstParseError"
    }
    Write-InstallLog 'Windows PowerShell parser check passed.'

    Write-Host ' Checking that the previous uninstall has finished...'
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ((Test-Path -LiteralPath $marker) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    # Version 1.3 used a two-second delayed cleanup without a marker.
    Start-Sleep -Seconds 3

    $pidPath = Join-Path $target 'data\widget.pid'
    if (Test-Path -LiteralPath $pidPath) {
        $widgetProcessId = Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($widgetProcessId) {
            Stop-Process -Id $widgetProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 700
        }
    }

    $launcherPath = Join-Path $target 'WatermelonCalendarWidget.exe'
    Get-Process -Name 'WatermelonCalendarWidget' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $releaseDeadline = [DateTime]::UtcNow.AddSeconds(12)
    while (Test-Path -LiteralPath $launcherPath) {
        try {
            Remove-Item -LiteralPath $launcherPath -Force -ErrorAction Stop
            break
        } catch {
            if ([DateTime]::UtcNow -ge $releaseDeadline) {
                throw 'Windows did not release the previous Watermelon launcher. Close any Watermelon Calendar error box and run Install.cmd again.'
            }
            Get-Process -Name 'WatermelonCalendarWidget' -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    }

    New-Item -ItemType Directory -Force -Path $target, $assetsTarget | Out-Null

    $files = @(
        'WatermelonCalendarWidget.ps1'
        'WatermelonCalendarWidget.Launcher.cs'
        'Install.ps1'
        'Launch Watermelon Calendar.cmd'
        'Uninstall.cmd'
        'SETUP_GUIDE.html'
        'README.txt'
        'assets\watermelon-calendar.ico'
        'assets\watermelon-calendar.svg'
        'assets\watermelon-calendar.png'
    )
    foreach ($relativePath in $files) {
        $sourcePath = Join-Path $source $relativePath
        $destinationPath = Join-Path $target $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Missing installer file: $relativePath" }
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        if (-not (Test-Path -LiteralPath $destinationPath)) { throw "Windows did not copy: $relativePath" }
        if ((Get-Item -LiteralPath $sourcePath).Length -ne (Get-Item -LiteralPath $destinationPath).Length) {
            throw "The copied file did not verify correctly: $relativePath"
        }
        Write-InstallLog "Copied $relativePath"
    }

    $launcherSource = Join-Path $target 'WatermelonCalendarWidget.Launcher.cs'
    $iconPath = Join-Path $assetsTarget 'watermelon-calendar.ico'
    $launcherCode = Get-Content -LiteralPath $launcherSource -Raw -Encoding UTF8
    $automationAssembly = [System.Management.Automation.PSObject].Assembly.Location
    Add-Type -TypeDefinition $launcherCode -Language CSharp `
        -ReferencedAssemblies @($automationAssembly, 'System.Windows.Forms.dll') `
        -OutputAssembly $launcherPath -OutputType WindowsApplication
    if (-not (Test-Path -LiteralPath $launcherPath)) {
        throw 'Windows could not create the dedicated Watermelon launcher.'
    }
    Write-InstallLog 'Created the console-free Watermelon launcher.'

    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startup = [Environment]::GetFolderPath('Startup')
    $programs = [Environment]::GetFolderPath('Programs')
    $desktopShortcut = Join-Path $desktop 'Watermelon Calendar Widget.lnk'
    $startupShortcut = Join-Path $startup 'Watermelon Calendar Widget.lnk'
    $startMenuShortcut = Join-Path $programs 'Watermelon Calendar Widget.lnk'
    foreach ($shortcutPath in @($desktopShortcut, $startupShortcut, $startMenuShortcut)) {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $launcherPath
        $shortcut.WorkingDirectory = $target
        $shortcut.IconLocation = $iconPath
        if ($shortcutPath -eq $startupShortcut) { $shortcut.Arguments = '--start-minimized' }
        $shortcut.Save()
    }

    Write-InstallLog 'Installation completed successfully.'
    Write-Host ''
    Write-Host ' Installation complete.' -ForegroundColor Green
    Write-Host ' A shortcut has been added to your desktop and Windows startup.'
    Write-Host ''

    try { Start-Process (Join-Path $target 'SETUP_GUIDE.html') }
    catch { Write-InstallLog "The setup guide did not open automatically: $($_.Exception.Message)" }
    try { Start-Process $launcherPath }
    catch { Write-InstallLog "The widget did not launch automatically: $($_.Exception.Message)" }
    exit 0
} catch {
    $detail = $_.Exception.Message
    try { Write-InstallLog "FAILED: $detail`r`n$($_.ScriptStackTrace)" } catch { }
    Write-Host ''
    Write-Host ' INSTALLATION FAILED' -ForegroundColor Red
    Write-Host " $detail" -ForegroundColor Red
    Write-Host ''
    Write-Host ' Details were saved here:'
    Write-Host " $logPath"
    Write-Host ''
    exit 1
}
