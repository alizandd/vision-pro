#!/bin/bash

# Vision Pro - Stop All Servers Script

echo ""
echo "🛑 Stopping Vision Pro servers..."
echo ""

# Stop WebSocket Server (port 8080)
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "   Stopping WebSocket Server (port 8080)..."
    lsof -ti:8080 | xargs kill -9 2>/dev/null
    echo "   ✅ WebSocket Server stopped"
else
    echo "   ℹ️  WebSocket Server is not running"
fi

# Stop Web Controller (port 3000)
if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "   Stopping Web Controller (port 3000)..."
    lsof -ti:3000 | xargs kill -9 2>/dev/null
    echo "   ✅ Web Controller stopped"
else
    echo "   ℹ️  Web Controller is not running"
fi

echo ""
echo "✅ All servers stopped"
echo ""




