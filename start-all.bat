@echo off
REM Vision Pro - Start All Servers Script (Windows)
REM This script starts both WebSocket server and Web Controller
REM and displays all necessary addresses

chcp 65001 >nul
echo.
echo ╔════════════════════════════════════════════════════════════╗
echo ║        Vision Pro - Starting All Servers                  ║
echo ╚════════════════════════════════════════════════════════════╝
echo.

REM Get local IP address
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address"') do (
    set LOCAL_IP=%%a
    goto :found_ip
)
:found_ip
set LOCAL_IP=%LOCAL_IP: =%

if "%LOCAL_IP%"=="" (
    echo ⚠️  Could not detect IP address. Using localhost.
    set LOCAL_IP=localhost
)

echo 🔍 Detected IP Address: %LOCAL_IP%
echo.

REM Check and install dependencies if needed
echo 📦 Checking dependencies...
if not exist "%~dp0server\node_modules" (
    echo    Installing server dependencies...
    cd /d "%~dp0server"
    call npm install --silent
    cd /d "%~dp0"
    echo    ✅ Dependencies installed
) else (
    echo    ✅ Dependencies already installed
)
echo.

set WS_PORT=8080
set WEB_PORT=3000

REM Check and kill processes on ports
echo 🔄 Checking for existing processes...
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%WS_PORT%" ^| findstr "LISTENING"') do (
    echo    Killing process on port %WS_PORT%...
    taskkill /F /PID %%a >nul 2>&1
)

for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":%WEB_PORT%" ^| findstr "LISTENING"') do (
    echo    Killing process on port %WEB_PORT%...
    taskkill /F /PID %%a >nul 2>&1
)

timeout /t 1 /nobreak >nul

echo.
echo 🚀 Starting servers...
echo.

REM Create logs directory
if not exist logs mkdir logs

REM Start WebSocket Server
cd server
start /B cmd /c "set PORT= && node server.js > ..\logs\websocket-server.log 2>&1"
cd ..

timeout /t 2 /nobreak >nul

REM Start Web Controller Server
cd web-controller
start /B cmd /c "npx -y serve -l %WEB_PORT% > ..\logs\web-controller.log 2>&1"
cd ..

timeout /t 3 /nobreak >nul

echo ✅ WebSocket Server started
echo ✅ Web Controller started
echo.
echo ╔════════════════════════════════════════════════════════════╗
echo ║                    🎉 SERVERS READY                        ║
echo ╚════════════════════════════════════════════════════════════╝
echo.
echo ┌────────────────────────────────────────────────────────────┐
echo │  📱 Open on Mobile/Tablet:                                 │
echo │                                                            │
echo │     http://%LOCAL_IP%:%WEB_PORT%
echo │                                                            │
echo └────────────────────────────────────────────────────────────┘
echo.
echo ┌────────────────────────────────────────────────────────────┐
echo │  🔌 WebSocket Server URL (enter in web app):              │
echo │                                                            │
echo │     ws://%LOCAL_IP%:%WS_PORT%
echo │                                                            │
echo └────────────────────────────────────────────────────────────┘
echo.
echo ┌────────────────────────────────────────────────────────────┐
echo │  🎥 Vision Pro App Settings:                               │
echo │                                                            │
echo │     ws://%LOCAL_IP%:%WS_PORT%
echo │                                                            │
echo └────────────────────────────────────────────────────────────┘
echo.
echo 📊 Server Status:
echo    • WebSocket Server: http://%LOCAL_IP%:%WS_PORT%/health
echo    • Video API: http://%LOCAL_IP%:%WS_PORT%/api/videos
echo    • Web Controller: http://%LOCAL_IP%:%WEB_PORT%
echo.
echo 📝 Logs:
echo    • WebSocket: logs\websocket-server.log
echo    • Web Controller: logs\web-controller.log
echo.
echo 🛑 To stop servers, run: stop-all.bat
echo.
pause

