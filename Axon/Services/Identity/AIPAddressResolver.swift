import Foundation
import OSLog
import Combine

/// Resolves AIP addresses to data endpoints.
/// Integrates with BioID, UserDataZoneService, and DiscoveryService.
@MainActor
public class AIPAddressResolver: ObservableObject {
    public static let shared = AIPAddressResolver()
    
    private let logger = Logger(subsystem: "com.axon", category: "AIPAddressResolver")
    
    private init() {}
    
    /// Resolve an AIP address string to a usable endpoint.
    public func resolve(_ addressString: String) async throws -> AIPResolutionResult {
        // 1. Parse the address
        let address: AIPAddress
        do {
            address = try AIPAddressParser.parse(addressString)
        } catch {
            return .invalidAddress("Failed to parse address: \(error.localizedDescription)")
        }
        
        logger.info("Resolving address: \(address.canonicalForm)")
        
        // 2. Check paradigm
        guard address.paradigm == .axon else {
            // For LLM/Titan, we might route to external services
            return .notSupported("Only 'axon' paradigm is currently supported locally")
        }
        
        // 3. Extract BioID
        guard let bioID = address.bioID else {
            return .invalidAddress("Address missing BioID component")
        }
        
        // 4. Check if this is our address
        if let myBioID = BioIDService.shared.currentBioID, myBioID == bioID {
            logger.info("Address resolves to local dyad")
            return .localDyad(address)
        }
        
        // 5. Look up in public registry
        if let shareURL = try await UserDataZoneService.shared.lookupShareURL(identity: address.identity) {
            logger.info("Found share URL in registry")
            return .remoteDyad(address, shareURL: shareURL)
        }
        
        // 6. Try federation discovery
        let discoveryResult = try await DiscoveryService.shared.resolve(address)
        switch discoveryResult {
        case .resolved(let endpoint):
            return .federatedEndpoint(endpoint)
        case .notFound(let reason):
            return .notFound(reason)
        case .error(let message):
            return .resolverError(message)
        }
    }
    
    /// Convenience: Resolve and automatically set up access mode.
    public func resolveAndPrepare(_ addressString: String) async throws -> AIPResolutionResult {
        let result = try await resolve(addressString)
        
        // If remote dyad, configure roaming access
        if case .remoteDyad(let address, let shareURL) = result {
            try await RoamingAccessService.shared.startRoamingSession(shareURL: shareURL)
            logger.info("Roaming session prepared for \(address.canonicalForm)")
        }
        
        return result
    }
}

public enum AIPResolutionResult {
    case localDyad(AIPAddress)
    case remoteDyad(AIPAddress, shareURL: URL)
    case federatedEndpoint(AIPEndpoint)
    case notFound(String)
    case notSupported(String)
    case invalidAddress(String)
    case resolverError(String)
    
    public var isSuccess: Bool {
        switch self {
        case .localDyad, .remoteDyad, .federatedEndpoint:
            return true
        default:
            return false
        }
    }
}
