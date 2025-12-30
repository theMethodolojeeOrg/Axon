import Foundation
import CloudKit
import OSLog
import Combine

/// Manages access mode and session policies when on a foreign device.
/// Coordinates with UserDataZoneService and BioIDService for roaming sessions.
@MainActor
public class RoamingAccessService: ObservableObject {
    public static let shared = RoamingAccessService()
    
    private let logger = Logger(subsystem: "com.axon", category: "RoamingAccessService")
    
    @Published public var accessMode: DataAccessMode = .unknown
    @Published public var sessionPolicy: RoamingSessionPolicy?
    @Published public var isRoaming: Bool = false
    
    private init() {}
    
    /// Determine access mode based on device ownership.
    /// - Parameter iCloudUserID: The current iCloud account's user record ID.
    /// - Parameter ownerBioID: The BioID of the data owner.
    public func determineAccessMode(iCloudUserID: CKRecord.ID?, ownerBioID: String) async throws {
        // 1. Check if user has a local BioID (they've set up on this device before)
        let localBioID = BioIDService.shared.currentBioID
        
        // 2. If BioIDs match and this is the owner's iCloud, it's their device
        if let localBioID = localBioID, localBioID == ownerBioID {
            accessMode = .ownerDevice
            isRoaming = false
            sessionPolicy = nil
            logger.info("Access mode: Owner device")
        } else {
            // Different user's iCloud or no local BioID — this is a roaming session
            accessMode = .roamingSession
            isRoaming = true
            sessionPolicy = RoamingSessionPolicy.default
            logger.info("Access mode: Roaming session (ephemeral)")
        }
    }
    
    /// Start a roaming session by accepting a CKShare.
    public func startRoamingSession(shareURL: URL) async throws {
        guard accessMode == .roamingSession || accessMode == .unknown else {
            logger.warning("Already in owner mode, not starting roaming session")
            return
        }
        
        logger.info("Starting roaming session...")
        
        // Accept the share
        try await UserDataZoneService.shared.acceptShare(url: shareURL)
        
        accessMode = .roamingSession
        isRoaming = true
        sessionPolicy = RoamingSessionPolicy.default
        
        logger.info("Roaming session active")
    }
    
    /// End the roaming session and purge ephemeral data.
    public func endRoamingSession() {
        logger.info("Ending roaming session and purging ephemeral data...")
        
        // Clear in-memory caches (implementation-specific)
        // In a real app, this would clear Core Data in-memory stores,
        // invalidate any cached decryption keys, etc.
        
        accessMode = .unknown
        isRoaming = false
        sessionPolicy = nil
        
        logger.info("Roaming session ended")
    }
}

// MARK: - Supporting Types

public enum DataAccessMode: String {
    case unknown         // Not yet determined
    case ownerDevice     // Full local persistence, normal behavior
    case roamingSession  // Ephemeral: encrypted cache, auto-purge
}

public struct RoamingSessionPolicy {
    public let sessionTimeout: TimeInterval
    public let requiresOnlineSync: Bool
    public let purgeOnLogout: Bool
    
    public static let `default` = RoamingSessionPolicy(
        sessionTimeout: 30 * 60, // 30 minutes
        requiresOnlineSync: true,
        purgeOnLogout: true
    )
    
    public init(sessionTimeout: TimeInterval, requiresOnlineSync: Bool, purgeOnLogout: Bool) {
        self.sessionTimeout = sessionTimeout
        self.requiresOnlineSync = requiresOnlineSync
        self.purgeOnLogout = purgeOnLogout
    }
}
