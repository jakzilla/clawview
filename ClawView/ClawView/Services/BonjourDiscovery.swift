import Foundation
import Network
import Combine

// MARK: - Bonjour Discovery Service

@MainActor
class BonjourDiscovery: ObservableObject {
    @Published var discoveredHosts: [DiscoveredHost] = []
    @Published var isSearching: Bool = false

    private var browser: NWBrowser?

    struct DiscoveredHost: Identifiable, Equatable {
        let id = UUID()
        let hostname: String
        let port: Int
        let name: String

        static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
            lhs.hostname == rhs.hostname && lhs.port == rhs.port
        }
    }

    func startDiscovery() {
        isSearching = true
        discoveredHosts = []

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_openclaw._tcp", domain: nil), using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    break // Browsing
                case .failed(let error):
                    print("Bonjour browser failed: \(error)")
                    self?.isSearching = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor in
                for change in changes {
                    switch change {
                    case .added(let result):
                        if case .service(let name, let type, let domain, _) = result.endpoint {
                            // Resolve the endpoint
                            self?.resolveEndpoint(result.endpoint, name: name)
                        }
                    case .removed(let result):
                        if case .service(let name, _, _, _) = result.endpoint {
                            self?.discoveredHosts.removeAll { $0.name == name }
                        }
                    default:
                        break
                    }
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser

        // Auto-stop after 10s
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                self.isSearching = false
            }
        }
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    private func resolveEndpoint(_ endpoint: NWEndpoint, name: String) {
        // Use NWConnection to resolve the actual host/port
        let connection = NWConnection(to: endpoint, using: .tcp)

        connection.stateUpdateHandler = { [weak self] state in
            if case .preparing = state {
                // Extract host/port from the resolved endpoint
                if let remote = connection.currentPath?.remoteEndpoint,
                   case .hostPort(let host, let port) = remote {
                    Task { @MainActor in
                        let hostStr: String
                        switch host {
                        case .name(let hostname, _):
                            hostStr = hostname
                        case .ipv4(let addr):
                            hostStr = "\(addr)"
                        case .ipv6(let addr):
                            hostStr = "\(addr)"
                        @unknown default:
                            hostStr = name
                        }
                        let discovered = DiscoveredHost(
                            hostname: hostStr,
                            port: Int(port.rawValue),
                            name: name
                        )
                        if !(self?.discoveredHosts.contains(discovered) ?? false) {
                            self?.discoveredHosts.append(discovered)
                        }
                        connection.cancel()
                    }
                }
            }
        }

        connection.start(queue: .main)
    }
}
