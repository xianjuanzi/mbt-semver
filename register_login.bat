@echo off
chcp 65001 >nul
set "MOONBIN=D:\workbuddywork\.tools\moon\bin"
if exist "%MOONBIN%\moon.exe" set "PATH=%MOONBIN%;%PATH%"
cd /d "%~dp0"

echo ============================================
echo  STEP 1: moon register (create account)
echo ============================================
echo.
echo Use username : xianjuanzi
echo Use email    : 2067029049@qq.com
echo Password     : type it yourself (NOT written to any file for safety)
echo.
echo If the username is taken, note the new name you pick and tell
echo the assistant so the module prefix can be updated.
echo.
moon register
echo.
pause

echo ============================================
echo  STEP 2: moon login (log in to mooncakes.io)
echo ============================================
echo.
moon login
echo.
echo Login step finished. Now double-click publish.bat
echo.
pause
