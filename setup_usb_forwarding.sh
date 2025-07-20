#!/bin/bash
# Setup USB forwarding for iOS app communication

echo "🔌 Setting up USB forwarding for cortex iOS app..."

# Check if ios command is installed
if ! command -v ios &> /dev/null; then
    echo "❌ ios command not found. Please install it first."
    exit 1
fi

# Kill any existing tunnels and forwards
echo "🧹 Cleaning up existing tunnels and forwards..."
pkill -f "ios tunnel" 2>/dev/null || true
pkill -f "ios forward" 2>/dev/null || true
sleep 1 # Give processes a moment to die

# Start the iOS tunnel in userspace
echo "🚇 Starting iOS tunnel (userspace)..."
ios tunnel start --userspace &
TUNNEL_PID=$!

# Wait a moment for tunnel to establish
sleep 2

# Start USB forwarding for WDA (iPhone port 8100 -> Mac port 8100)
echo "📱 Starting WDA USB forwarding (iPhone:8100 -> Mac:8100)..."
ios forward 8100 8100 &
WDA_FORWARD_PID=$!

# Start USB forwarding for our app server (Mac port 8090 -> iPhone port 8090)
echo "🖥️  Starting App Server USB forwarding (Mac:8090 -> iPhone:8090)..."
ios forward 8090 8090 &
APP_SERVER_FORWARD_PID=$!

echo "✅ USB forwarding setup complete!"
echo "   Tunnel PID: $TUNNEL_PID"
echo "   WDA forwarding PID: $WDA_FORWARD_PID"
echo "   App Server forwarding PID: $APP_SERVER_FORWARD_PID"
echo ""
echo "📋 Next steps:"
echo "   1. Start the Mac screenshot server: python3 mac_screenshot_server.py"
echo "   2. Make sure WDA is running on your iPhone (blue 'Running Tests' pill)"
echo "   3. Build and run the iOS app on your phone"
echo ""
echo "🛑 To stop forwarding later, run:"
echo "   kill $TUNNEL_PID $WDA_FORWARD_PID $APP_SERVER_FORWARD_PID"

# Create a cleanup script
cat > cleanup_forwarding.sh << EOF
#!/bin/bash
echo "🧹 Stopping USB forwarding and tunnel..."
kill $TUNNEL_PID $WDA_FORWARD_PID $APP_SERVER_FORWARD_PID 2>/dev/null || true
pkill -f "ios tunnel" 2>/dev/null || true
pkill -f "ios forward" 2>/dev/null || true
echo "✅ USB forwarding and tunnel stopped"
rm cleanup_forwarding.sh
EOF

chmod +x cleanup_forwarding.sh
echo "   Or run: ./cleanup_forwarding.sh"