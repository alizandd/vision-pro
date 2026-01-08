/**
 * Test script to verify sphere360sbs format with VRCarRender001.mp4
 */

const WebSocket = require('ws');

const serverUrl = 'ws://localhost:8080';
// Make sure this matches the file hosted on your server
const testVideoUrl = 'http://localhost:8080/videos/VRCarRender001.mp4';

console.log('🧪 Testing Sphere 360 SBS Format...\n');

const ws = new WebSocket(serverUrl);

ws.on('open', () => {
    console.log('✅ Connected to WebSocket server\n');

    // Register as controller
    const registration = {
        type: 'register',
        deviceId: 'test-controller-' + Date.now(),
        deviceName: '360 SBS Test Controller',
        deviceType: 'controller'
    };

    ws.send(JSON.stringify(registration));
});

ws.on('message', (data) => {
    const message = JSON.parse(data.toString());

    if (message.type === 'registered') {
        console.log('✅ Registered successfully!');

        // Wait a moment for device list update
        setTimeout(() => {
            // Send play command with sphere360sbs format
            const playCommand = {
                type: 'command',
                action: 'play',
                videoUrl: testVideoUrl,
                videoFormat: 'sphere360sbs',  // The new format
                targetDevices: ['all']
            };

            console.log('\n📤 Sending play command with sphere360sbs format:');
            console.log(JSON.stringify(playCommand, null, 2));

            ws.send(JSON.stringify(playCommand));

            console.log('\n⏳ Check the Vision Pro Simulator console for log:');
            console.log('   "[VideoPlayer] ✅ Creating SPHERE mesh..."');

            setTimeout(() => {
                console.log('\n✅ Command sent. Closing.');
                ws.close();
                process.exit(0);
            }, 2000);
        }, 1000);
    }
});
