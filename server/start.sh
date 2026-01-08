#!/bin/bash
# Vision Pro Server Startup Script
# This script ensures the server uses the correct port (8080)
# by unsetting the PORT environment variable if set by Cursor

echo "Starting Vision Pro Server..."

# Unset PORT environment variable to avoid conflicts
unset PORT

# Start the server
node server.js





