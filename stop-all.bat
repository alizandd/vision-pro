@echo off
REM Vision Pro - Stop All Servers Script (Windows)

chcp 65001 >nul
echo.
echo 🛑 Stopping Vision Pro servers...
echo.

set WS_PORT=8080
set WEB_PORT=3000

REM Stop WebSocket Server (port 8080)
set FOUND_WS=0
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%WS_PORT%" ^| findstr "LISTENING"') do (
    set FOUND_WS=1
    echo    Stopping WebSocket Server (port %WS_PORT%)...
    taskkill /F /PID %%a >nul 2>&1
    echo    ✅ WebSocket Server stopped
)
if %FOUND_WS%==0 (
    echo    ℹ️  WebSocket Server is not running
)

REM Stop Web Controller (port 3000)
set FOUND_WEB=0
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%WEB_PORT%" ^| findstr "LISTENING"') do (
    set FOUND_WEB=1
    echo    Stopping Web Controller (port %WEB_PORT%)...
    taskkill /F /PID %%a >nul 2>&1
    echo    ✅ Web Controller stopped
)
if %FOUND_WEB%==0 (
    echo    ℹ️  Web Controller is not running
)

echo.
echo ✅ All servers stopped
echo.
pause





