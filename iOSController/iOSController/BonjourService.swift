import Foundation
import Network

/// Bonjour Service for advertising the controller to Vision Pro devices
@MainActor
class BonjourService: ObservableObject {
    @Published var isAdvertising: Bool = false
    @Published var serviceName: String = "iOS Vision Pro Controller"
    
    private var listener: NWListener?
    private let serviceType = "_visionproctl._tcp"
    
    /// Start advertising the service
    func startAdvertising(port: UInt16) {
        guard !isAdvertising else { return }
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            
            // Create listener for Bonjour advertising
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
            
            // Set up Bonjour service
            listener?.service = NWListener.Service(
                name: serviceName,
                type: serviceType
            )
            
            listener?.serviceRegistrationUpdateHandler = { [weak self] change in
                Task { @MainActor in
                    switch change {
                    case .add(let endpoint):
                        print("[Bonjour] ✅ Service registered: \(endpoint)")
                        self?.isAdvertising = true
                    case .remove(let endpoint):
                        print("[Bonjour] Service removed: \(endpoint)")
                        self?.isAdvertising = false
                    @unknown default:
                        break
                    }
                }
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        print("[Bonjour] Listener ready")
                    case .failed(let error):
                        print("[Bonjour] Listener failed: \(error)")
                        self?.isAdvertising = false
                    case .cancelled:
                        self?.isAdvertising = false
                    default:
                        break
                    }
                }
            }
            
            // We don't need to handle connections here, just advertise
            listener?.newConnectionHandler = { connection in
                // Close any connections to this listener - actual WebSocket server handles connections
                connection.cancel()
            }
            
            listener?.start(queue: .main)
            print("[Bonjour] Starting advertisement on port \(port)...")
            
        } catch {
            print("[Bonjour] Failed to start: \(error)")
        }
    }
    
    /// Stop advertising
    func stopAdvertising() {
        listener?.cancel()
        listener = nil
        isAdvertising = false
        print("[Bonjour] Stopped advertising")
    }
    
    /// Update service name
    func updateServiceName(_ name: String) {
        serviceName = name
        // If already advertising, restart to update name
        if isAdvertising, let port = listener?.port?.rawValue {
            stopAdvertising()
            startAdvertising(port: port)
        }
    }
}
