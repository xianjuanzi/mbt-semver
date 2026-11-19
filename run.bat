@echo off
set "MOONBIN=D:\workbuddywork\.tools\moon\bin"
if exist "%MOONBIN%\moon.exe" set "PATH=%MOONBIN%;%PATH%"
cd /d "%~dp0"

echo === moon check ===
moon check
if errorlevel 1 goto fail

echo === moon test ===
moon test
if errorlevel 1 goto fail

echo === moon run cmd -- demo ===
moon run cmd -- demo
if errorlevel 1 goto fail

echo.
echo ALL OK. You can upload this folder to GitHub.
goto end

:fail
echo FAILED. Please check the error message above.
:end
pause
