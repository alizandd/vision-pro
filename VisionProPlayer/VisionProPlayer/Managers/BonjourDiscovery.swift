import Foundation
import Network

/// Discovered controller service
struct DiscoveredController: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: UInt16
    
    var webSocketURL: String {
        "ws://\(host):\(port)"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: DiscoveredController, rhs: DiscoveredController) -> Bool {
        lhs.id == rhs.id
    }
}

/// Discovers iOS Controller apps on the local network using Bonjour
@MainActor
class BonjourDiscovery: ObservableObject {
    @Published var isSearching: Bool = false
    @Published var discoveredControllers: [DiscoveredController] = []
    
    private var browser: NWBrowser?
    private let serviceType = "_visionproctl._tcp"
    
    /// Start searching for controllers
    func startSearching() {
        guard !isSearching else { return }
        
        // Clear existing discoveries
        discoveredControllers.removeAll()
        
        // Create browser parameters
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // Create browser
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[BonjourDiscovery] ✅ Browser ready, searching for controllers...")
                    self?.isSearching = true
                case .failed(let error):
                    print("[BonjourDiscovery] ❌ Browser failed: \(error)")
                    self?.isSearching = false
                case .cancelled:
                    print("[BonjourDiscovery] Browser cancelled")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                self?.handleBrowseResults(results, changes: changes)
            }
        }
        
        browser?.start(queue: .main)
        print("[BonjourDiscovery] Starting search for \(serviceType)...")
    }
    
    /// Stop searching
    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
        print("[BonjourDiscovery] Stopped searching")
    }
    
    /// Resolve a discovered service to get its IP address and port
    func resolveController(_ controller: DiscoveredController, completion: @escaping (String?) -> Void) {
        // The controller already has resolved host and port
        completion(controller.webSocketURL)
    }
    
    // MARK: - Private Methods
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                handleServiceFound(result)
            case .removed(let result):
                handleServiceRemoved(result)
            case .changed(old: _, new: let newResult, flags: _):
                handleServiceFound(newResult)
            default:
                break
            }
        }
    }
    
    private func handleServiceFound(_ result: NWBrowser.Result) {
        guard case .service(let name, let type, let domain, _) = result.endpoint else {
            return
        }
        
        print("[BonjourDiscovery] Found service: \(name) (\(type) in \(domain))")
        
        // Resolve the service to get the actual host and port
        resolveService(result) { [weak self] host, port in
            Task { @MainActor in
                guard let self = self, let host = host, let port = port else { return }
                
                let controller = DiscoveredController(
                    id: "\(name)-\(host)-\(port)",
                    name: name,
                    host: host,
                    port: port
                )
                
                // Add if not already present
                if !self.discoveredControllers.contains(where: { $0.id == controller.id }) {
                    self.discoveredControllers.append(controller)
                    print("[BonjourDiscovery] ✅ Resolved controller: \(controller.name) at \(controller.webSocketURL)")
                }
            }
        }
    }
    
    private func handleServiceRemoved(_ result: NWBrowser.Result) {
        guard case .service(let name, _, _, _) = result.endpoint else {
            return
        }
        
        discoveredControllers.removeAll { $0.name == name }
        print("[BonjourDiscovery] Service removed: \(name)")
    }
    
    private func resolveService(_ result: NWBrowser.Result, completion: @escaping (String?, UInt16?) -> Void) {
        // Create a connection to resolve the endpoint
        let parameters = NWParameters.tcp
        let connection = NWConnection(to: result.endpoint, using: parameters)
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                // Get the resolved endpoint
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = endpoint {
                    
                    // Extract IP address from host
                    var hostString: String?
                    switch host {
                    case .ipv4(let ipv4):
                        hostString = "\(ipv4)"
                    case .ipv6(let ipv6):
                        hostString = "[\(ipv6)]"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        break
                    }
                    
                    connection.cancel()
                    completion(hostString, port.rawValue)
                } else {
                    connection.cancel()
                    completion(nil, nil)
                }
                
            case .failed(_), .cancelled:
                completion(nil, nil)
                
            default:
                break
            }
        }
        
        connection.start(queue: .main)
        
        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if connection.state != .ready && connection.state != .cancelled {
                connection.cancel()
                completion(nil, nil)
            }
        }
    }
}
