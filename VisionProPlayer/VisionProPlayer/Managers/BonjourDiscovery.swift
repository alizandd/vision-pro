import Foundation
import Network

/// A controller discovered on the local network.
///
/// Identity is the controller's stable `controllerId` (from the advertised TXT
/// record), never its IP address — the address is re-resolved from Bonjour on
/// every discovery, so a DHCP change can't strand the headset.
struct DiscoveredController: Identifiable, Hashable {
    /// Stable id published by the controller. Falls back to the Bonjour service
    /// name for older controllers that advertise no TXT record.
    let controllerId: String
    /// Human-readable name (TXT `name`, else the Bonjour service name).
    let name: String
    /// Bonjour service name — what the endpoint is registered under.
    let serviceName: String
    let host: String
    let port: UInt16
    /// Companion HTTP file-transfer port, advertised so it isn't assumed.
    let httpPort: UInt16
    /// Controller protocol version.
    let protocolVersion: Int

    var id: String { controllerId }

    var webSocketURL: String {
        "ws://\(host):\(port)"
    }

    var fileTransferBaseURL: String {
        "http://\(host):\(httpPort)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(controllerId)
    }

    static func == (lhs: DiscoveredController, rhs: DiscoveredController) -> Bool {
        lhs.controllerId == rhs.controllerId
    }
}

/// Discovers iOS Controller apps on the local network using Bonjour.
///
/// Owned by the app (not by Settings) and left running for the whole session, so
/// a headset that joins the network finds its controller and connects with no
/// user interaction and no manually typed IP address.
@MainActor
class BonjourDiscovery: ObservableObject {
    @Published var isSearching: Bool = false
    @Published var discoveredControllers: [DiscoveredController] = []

    /// Called when a controller should be connected to automatically:
    /// either the previously-used controller reappeared, or exactly one
    /// controller exists on the network and none was ever chosen.
    var onAutoConnect: ((DiscoveredController) -> Void)?

    /// Highest protocol version this app understands. Controllers advertising a
    /// newer major version are surfaced but never auto-connected.
    static let supportedProtocolVersion = 1

    private var browser: NWBrowser?
    private let serviceType = "_visionproctl._tcp"
    /// Controllers already handed to `onAutoConnect` this session, so a service
    /// re-announcement doesn't retrigger a connect storm.
    private var autoConnectedIds: Set<String> = []

    /// Start searching. Safe to call repeatedly.
    func startSearching() {
        // `isSearching` only flips once the browser reports `.ready`, so guard on
        // the browser itself — otherwise a second call during startup builds a
        // duplicate browser and every service gets resolved twice.
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        // `.bonjour` does NOT deliver TXT records — the descriptor has to be
        // `.bonjourWithTXTRecord`, or `result.metadata` is always `.none` and
        // the controller's id/ports/version never arrive.
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: parameters)

        browser?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[BonjourDiscovery] ✅ Browser ready, searching for controllers...")
                    self?.isSearching = true
                case .failed(let error):
                    print("[BonjourDiscovery] ❌ Browser failed: \(error)")
                    self?.isSearching = false
                    // A failed browser never recovers on its own — rebuild it so
                    // discovery survives transient network loss.
                    self?.restartAfterFailure()
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

    /// Stop searching.
    func stopSearching() {
        browser?.cancel()
        browser = nil
        isSearching = false
        print("[BonjourDiscovery] Stopped searching")
    }

    /// Forget which controllers were auto-connected, so the next sighting of the
    /// preferred controller reconnects. Used by the reconnect path.
    func allowReconnect() {
        autoConnectedIds.removeAll()
    }

    /// Re-resolve everything from scratch — used when the network changes or a
    /// connection attempt keeps failing against a stale address.
    func refresh() {
        print("[BonjourDiscovery] Refreshing — re-resolving all controllers")
        stopSearching()
        discoveredControllers.removeAll()
        autoConnectedIds.removeAll()
        startSearching()
    }

    /// The currently-visible controller matching a stored preference, if any.
    func controller(withId id: String) -> DiscoveredController? {
        discoveredControllers.first { $0.controllerId == id }
    }

    // MARK: - Private

    private func restartAfterFailure() {
        browser?.cancel()
        browser = nil
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.startSearching()
        }
    }

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
        guard case .service(let serviceName, let type, let domain, _) = result.endpoint else {
            return
        }

        print("[BonjourDiscovery] Found service: \(serviceName) (\(type) in \(domain))")

        // Pull identity and ports out of the TXT record when present.
        var txtName: String?
        var txtWSPort: UInt16?
        var txtHTTPPort: UInt16?
        var txtVersion: Int?
        var txtId: String?

        if case .bonjour(let txt) = result.metadata {
            txtName = txt["name"]
            txtWSPort = txt["ws"].flatMap(UInt16.init)
            txtHTTPPort = txt["http"].flatMap(UInt16.init)
            txtVersion = txt["v"].flatMap(Int.init)
            txtId = txt["id"]
        }

        resolveService(result) { [weak self] host, resolvedPort in
            Task { @MainActor in
                guard let self = self, let host = host, let resolvedPort = resolvedPort else {
                    print("[BonjourDiscovery] ⚠️ Could not resolve \(serviceName)")
                    return
                }

                let controller = DiscoveredController(
                    // No TXT record (older controller) → fall back to the service
                    // name so it is still identifiable, just less stable.
                    controllerId: txtId ?? "name:\(serviceName)",
                    name: txtName ?? serviceName,
                    serviceName: serviceName,
                    host: host,
                    port: txtWSPort ?? resolvedPort,
                    httpPort: txtHTTPPort ?? 8081,
                    protocolVersion: txtVersion ?? 0
                )

                if let index = self.discoveredControllers.firstIndex(where: { $0.controllerId == controller.controllerId }) {
                    // Address may have changed (DHCP) — always take the fresh one.
                    self.discoveredControllers[index] = controller
                } else {
                    self.discoveredControllers.append(controller)
                }
                print("[BonjourDiscovery] ✅ Resolved controller: \(controller.name) at \(controller.webSocketURL) (id=\(controller.controllerId), v=\(controller.protocolVersion))")

                self.evaluateAutoConnect()
            }
        }
    }

    private func handleServiceRemoved(_ result: NWBrowser.Result) {
        guard case .service(let serviceName, _, _, _) = result.endpoint else {
            return
        }

        if let removed = discoveredControllers.first(where: { $0.serviceName == serviceName }) {
            autoConnectedIds.remove(removed.controllerId)
        }
        discoveredControllers.removeAll { $0.serviceName == serviceName }
        print("[BonjourDiscovery] Service removed: \(serviceName)")
    }

    /// Decides whether a discovered controller should be connected to without
    /// asking the user.
    ///
    /// - The controller the headset used last always wins, as soon as it appears.
    /// - Otherwise, if exactly one controller is on the network and the user has
    ///   never chosen one, take it — that's the zero-config case.
    /// - With several unknown controllers, stay put and let the user pick in
    ///   Settings rather than guessing.
    private func evaluateAutoConnect() {
        guard let handler = onAutoConnect else { return }

        if let preferredId = AppConfiguration.preferredControllerId,
           let preferred = controller(withId: preferredId) {
            guard !autoConnectedIds.contains(preferred.controllerId) else { return }
            autoConnectedIds.insert(preferred.controllerId)
            print("[BonjourDiscovery] 🎯 Auto-connecting to preferred controller: \(preferred.name)")
            handler(preferred)
            return
        }

        guard AppConfiguration.preferredControllerId == nil else {
            // A controller was chosen before but isn't here yet — wait for it
            // instead of hijacking the headset onto a different one.
            return
        }

        let candidates = discoveredControllers.filter {
            $0.protocolVersion <= Self.supportedProtocolVersion
        }
        guard candidates.count == 1, let only = candidates.first else {
            if candidates.count > 1 {
                print("[BonjourDiscovery] \(candidates.count) controllers found and none chosen — waiting for the user to pick")
            }
            return
        }
        guard !autoConnectedIds.contains(only.controllerId) else { return }
        autoConnectedIds.insert(only.controllerId)
        print("[BonjourDiscovery] 🎯 Single controller on the network — auto-connecting to \(only.name)")
        handler(only)
    }

    private func resolveService(_ result: NWBrowser.Result, completion: @escaping (String?, UInt16?) -> Void) {
        let connection = NWConnection(to: result.endpoint, using: NWParameters.tcp)
        // The completion must fire exactly once — state updates and the timeout
        // race each other.
        let hasCompleted = CompletionGuard()

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var hostString: String?
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, _) = endpoint {
                    switch host {
                    case .ipv4(let ipv4):
                        hostString = "\(ipv4)".components(separatedBy: "%").first
                    case .ipv6(let ipv6):
                        hostString = "[\(ipv6)]"
                    case .name(let name, _):
                        hostString = name
                    @unknown default:
                        break
                    }
                }
                let resolvedPort: UInt16?
                if let endpoint = connection.currentPath?.remoteEndpoint,
                   case .hostPort(_, let port) = endpoint {
                    resolvedPort = port.rawValue
                } else {
                    resolvedPort = nil
                }
                connection.cancel()
                if hasCompleted.claim() { completion(hostString, resolvedPort) }

            case .failed, .cancelled:
                if hasCompleted.claim() { completion(nil, nil) }

            default:
                break
            }
        }

        connection.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard !hasCompleted.isClaimed else { return }
            connection.cancel()
            if hasCompleted.claim() { completion(nil, nil) }
        }
    }
}

/// One-shot latch so a completion handler can't be invoked twice.
private final class CompletionGuard {
    private var claimed = false
    private let lock = NSLock()

    var isClaimed: Bool {
        lock.lock(); defer { lock.unlock() }
        return claimed
    }

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
