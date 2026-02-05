import SwiftUI

@main
struct iOSControllerApp: App {
    @StateObject private var deviceManager = DeviceManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceManager)
        }
    }
}
