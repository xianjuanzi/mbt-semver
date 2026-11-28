@echo off
chcp 65001 >nul
set "MOONBIN=D:\workbuddywork\.tools\moon\bin"
if exist "%MOONBIN%\moon.exe" set "PATH=%MOONBIN%;%PATH%"
cd /d "%~dp0"

echo ============================================
echo  STEP 1: dry-run (validate, no real publish)
echo ============================================
echo.
moon publish --dry-run
if errorlevel 1 goto fail
echo.
echo Dry-run OK. Press any key to publish for real, or close window to cancel.
pause

echo.
echo ============================================
echo  STEP 2: publish to mooncakes.io
echo ============================================
echo.
moon publish
if errorlevel 1 goto fail
echo.
echo PUBLISHED. Check: https://mooncakes.io/xianjuanzi/mbt-semver
goto end

:fail
echo FAILED. Screenshot the error above and send it to the assistant.
:end
echo.
pause
