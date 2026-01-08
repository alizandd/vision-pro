/**
 * Test script to verify video format is being sent correctly
 * Run this to send a play command with hemisphere180sbs format
 */

const WebSocket = require('ws');

const serverUrl = 'ws://localhost:8080';
const testVideoUrl = 'http://localhost:8080/videos/BigBuckBunny.mp4';

console.log('🧪 Testing Video Format Transmission...\n');

const ws = new WebSocket(serverUrl);

ws.on('open', () => {
    console.log('✅ Connected to WebSocket server\n');

    // Register as controller
    const registration = {
        type: 'register',
        deviceId: 'test-controller-' + Date.now(),
        deviceName: 'Format Test Controller',
        deviceType: 'controller'
    };

    ws.send(JSON.stringify(registration));
    console.log('📤 Sent registration:', JSON.stringify(registration, null, 2));
});

ws.on('message', (data) => {
    const message = JSON.parse(data.toString());
    console.log('\n📥 Received:', JSON.stringify(message, null, 2));

    if (message.type === 'registered') {
        console.log('\n✅ Registered successfully!');

        // Check if there are any Vision Pro devices connected
        if (message.devices && message.devices.length > 0) {
            const visionProDevices = message.devices.filter(d => d.deviceType !== 'controller');

            if (visionProDevices.length > 0) {
                console.log(`\n📱 Found ${visionProDevices.length} Vision Pro device(s)`);

                // Send play command with hemisphere180sbs format
                const playCommand = {
                    type: 'command',
                    action: 'play',
                    videoUrl: testVideoUrl,
                    videoFormat: 'hemisphere180sbs',  // This is the format we're testing!
                    targetDevices: ['all']
                };

                console.log('\n📤 Sending play command with hemisphere180sbs format:');
                console.log(JSON.stringify(playCommand, null, 2));

                ws.send(JSON.stringify(playCommand));

                console.log('\n⏳ Check the Vision Pro Simulator console for these log messages:');
                console.log('   "[VideoPlayer] ✅ Creating HEMISPHERE mesh..."');
                console.log('   "[ImmersiveView] Immersive format - centering at origin"');
                console.log('   "[ImmersiveView] Applied 180° rotation for immersive content"');

                // Wait a bit then close
                setTimeout(() => {
                    console.log('\n✅ Test complete! Check simulator logs for verification.');
                    ws.close();
                    process.exit(0);
                }, 3000);
            } else {
                console.log('\n⚠️  No Vision Pro devices connected.');
                console.log('   Please make sure the Vision Pro app is running in the simulator.');
                ws.close();
                process.exit(1);
            }
        } else {
            console.log('\n⚠️  No devices connected yet.');
            console.log('   Please make sure the Vision Pro app is running in the simulator.');
            ws.close();
            process.exit(1);
        }
    }
});

ws.on('error', (error) => {
    console.error('❌ WebSocket error:', error.message);
    process.exit(1);
});

ws.on('close', () => {
    console.log('\n🔌 Connection closed');
});

// Timeout after 10 seconds
setTimeout(() => {
    console.log('\n⏰ Test timed out');
    ws.close();
    process.exit(1);
}, 10000);
