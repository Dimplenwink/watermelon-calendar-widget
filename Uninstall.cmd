@echo off
setlocal EnableExtensions
title Uninstall Watermelon Calendar Widget
echo This removes the widget, its encrypted sign-in tokens, private ICS addresses, and local event cache.
choice /C YN /M "Continue"
if errorlevel 2 exit /b 0

set "WM_REMOVE_TARGET=%LOCALAPPDATA%\WatermelonCalendarWidget"
set "WM_REMOVE_MARKER=%LOCALAPPDATA%\WatermelonCalendarWidget.uninstalling"
>"%WM_REMOVE_MARKER%" echo Uninstall cleanup in progress

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$target=$env:WM_REMOVE_TARGET;$p=Join-Path $target 'data\widget.pid';if(Test-Path -LiteralPath $p){$wid=Get-Content -LiteralPath $p -ErrorAction SilentlyContinue;if($wid){Stop-Process -Id $wid -Force -ErrorAction SilentlyContinue}};Remove-Item -LiteralPath ([Environment]::GetFolderPath('Desktop')+'\Watermelon Calendar Widget.lnk') -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ([Environment]::GetFolderPath('Startup')+'\Watermelon Calendar Widget.lnk') -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath ([Environment]::GetFolderPath('Programs')+'\Watermelon Calendar Widget.lnk') -Force -ErrorAction SilentlyContinue"

rem The marker tells a new installer to wait until this delayed cleanup is done.
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$target=$env:WM_REMOVE_TARGET;$marker=$env:WM_REMOVE_MARKER;Start-Sleep -Seconds 2;for($i=0;$i -lt 12;$i++){if(-not(Test-Path -LiteralPath $target)){break};try{Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop;break}catch{Start-Sleep -Milliseconds 500}};Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue"
echo Watermelon Calendar Widget has been removed.
timeout /T 2 /NOBREAK >nul
exit /b 0
