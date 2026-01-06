#!/bin/bash

# Vision Pro - Start All Servers Script
# This script starts both WebSocket server and Web Controller
# and displays all necessary addresses

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Vision Pro - Starting All Servers                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get local IP address
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    LOCAL_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)
else
    # Linux
    LOCAL_IP=$(hostname -I | awk '{print $1}')
fi

if [ -z "$LOCAL_IP" ]; then
    echo "⚠️  Could not detect IP address. Using localhost."
    LOCAL_IP="localhost"
fi

echo "🔍 Detected IP Address: $LOCAL_IP"
echo ""

# Check and install dependencies if needed
echo "📦 Checking dependencies..."
if [ ! -d "$(dirname "$0")/server/node_modules" ]; then
    echo "   Installing server dependencies..."
    cd "$(dirname "$0")/server"
    npm install --silent
    cd ..
    echo "   ✅ Dependencies installed"
else
    echo "   ✅ Dependencies already installed"
fi
echo ""

# Check if ports are in use
WS_PORT=8080
WEB_PORT=3000

if lsof -Pi :$WS_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port $WS_PORT is already in use. Killing existing process..."
    lsof -ti:$WS_PORT | xargs kill -9 2>/dev/null
    sleep 1
fi

if lsof -Pi :$WEB_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "⚠️  Port $WEB_PORT is already in use. Killing existing process..."
    lsof -ti:$WEB_PORT | xargs kill -9 2>/dev/null
    sleep 1
fi

echo "🚀 Starting servers..."
echo ""

# Create logs directory if it doesn't exist
mkdir -p "$(dirname "$0")/logs"

# Start WebSocket Server
cd "$(dirname "$0")/server"
unset PORT
nohup node server.js > ../logs/websocket-server.log 2>&1 &
WS_PID=$!
cd ..

sleep 2

# Start Web Controller Server
cd "$(dirname "$0")/web-controller"
nohup npx -y serve -l $WEB_PORT > ../logs/web-controller.log 2>&1 &
WEB_PID=$!
cd ..

sleep 3

# Verify servers are running
if ps -p $WS_PID > /dev/null 2>&1; then
    echo "✅ WebSocket Server started (PID: $WS_PID)"
else
    echo "❌ WebSocket Server failed to start"
fi

if ps -p $WEB_PID > /dev/null 2>&1; then
    echo "✅ Web Controller started (PID: $WEB_PID)"
else
    echo "❌ Web Controller failed to start"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    🎉 SERVERS READY                        ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  📱 Open on Mobile/Tablet:                                 │"
echo "│                                                            │"
echo "│     http://$LOCAL_IP:$WEB_PORT"
echo "│                                                            │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  🔌 WebSocket Server URL (enter in web app):              │"
echo "│                                                            │"
echo "│     ws://$LOCAL_IP:$WS_PORT"
echo "│                                                            │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  🎥 Vision Pro App Settings:                               │"
echo "│                                                            │"
echo "│     ws://$LOCAL_IP:$WS_PORT"
echo "│                                                            │"
echo "└────────────────────────────────────────────────────────────┘"
echo ""
echo "📊 Server Status:"
echo "   • WebSocket Server: http://$LOCAL_IP:$WS_PORT/health"
echo "   • Video API: http://$LOCAL_IP:$WS_PORT/api/videos"
echo "   • Web Controller: http://$LOCAL_IP:$WEB_PORT"
echo ""
echo "📝 Logs:"
echo "   • WebSocket: logs/websocket-server.log"
echo "   • Web Controller: logs/web-controller.log"
echo ""
echo "🛑 To stop servers, run: ./stop-all.sh"
echo ""

