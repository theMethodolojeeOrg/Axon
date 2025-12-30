import Foundation
import CloudKit
import OSLog
import Combine

/// Service responsible for managing the user's shared CloudKit zone for AIP data portability.
/// Creates a CKShare that allows access from any device the user authenticates on.
@MainActor
public class UserDataZoneService: ObservableObject {
    public static let shared = UserDataZoneService()
    
    private let logger = Logger(subsystem: "com.axon", category: "UserDataZoneService")
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let publicDatabase: CKDatabase
    
    // Zone configuration
    private let sharedZoneName = "AxonSharedZone"
    private var sharedZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: sharedZoneName, ownerName: CKCurrentUserDefaultName)
    }
    
    // State
    @Published public var isZoneReady: Bool = false
    @Published public var currentShareURL: URL?
    @Published public var error: String?
    
    private init() {
        self.container = CKContainer(identifier: "iCloud.com.axon")
        self.privateDatabase = container.privateCloudDatabase
        self.publicDatabase = container.publicCloudDatabase
    }
    
    // MARK: - Zone Bootstrap
    
    /// Bootstrap the shared zone and create a CKShare.
    /// Must be called on the user's primary device.
    public func bootstrapSharedZone(bioID: String, displayName: String) async throws -> URL {
        logger.info("Bootstrapping shared zone for bioID: \(bioID)")
        
        // 1. Create the zone
        let zone = CKRecordZone(zoneID: sharedZoneID)
        
        do {
            let savedZone = try await privateDatabase.save(zone)
            logger.info("Created zone: \(savedZone.zoneID.zoneName)")
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists, that's fine
            logger.info("Zone already exists, continuing...")
        }
        
        // 2. Create a root record to share (CKShare needs a record)
        let rootRecordID = CKRecord.ID(recordName: "AxonRoot_\(bioID)", zoneID: sharedZoneID)
        let rootRecord = CKRecord(recordType: "AxonRoot", recordID: rootRecordID)
        rootRecord["bioID"] = bioID
        rootRecord["displayName"] = displayName
        rootRecord["createdAt"] = Date()
        
        try await privateDatabase.save(rootRecord)
        logger.info("Created root record")
        
        // 3. Create a CKShare for the zone
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "Axon Data - \(displayName)"
        share.publicPermission = .none // Only explicit participants
        
        let operation = CKModifyRecordsOperation(recordsToSave: [rootRecord, share], recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            privateDatabase.add(operation)
        }
        
        // 4. Get the share URL
        guard let shareURL = share.url else {
            throw UserDataZoneError.shareCreationFailed
        }
        
        self.currentShareURL = shareURL
        self.isZoneReady = true
        logger.info("Created share with URL: \(shareURL.absoluteString)")
        
        // 5. Publish to public registry
        try await publishToRegistry(bioID: bioID, displayName: displayName, shareURL: shareURL)
        
        return shareURL
    }
    
    // MARK: - Public Registry
    
    /// Publish the share URL to the public CloudKit database for discovery.
    private func publishToRegistry(bioID: String, displayName: String, shareURL: URL) async throws {
        let registryID = CKRecord.ID(recordName: "\(displayName).\(bioID)")
        let registryRecord = CKRecord(recordType: "AIPRegistry", recordID: registryID)
        
        registryRecord["bioID"] = bioID
        registryRecord["displayName"] = displayName
        registryRecord["shareURL"] = shareURL.absoluteString
        registryRecord["updatedAt"] = Date()
        
        try await publicDatabase.save(registryRecord)
        logger.info("Published to public registry: \(displayName).\(bioID)")
    }
    
    /// Look up a share URL from the public registry.
    public func lookupShareURL(identity: String) async throws -> URL? {
        // Identity format: "name.bioID"
        let recordID = CKRecord.ID(recordName: identity)
        
        do {
            let record = try await publicDatabase.record(for: recordID)
            if let urlString = record["shareURL"] as? String {
                return URL(string: urlString)
            }
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("No registry entry found for: \(identity)")
            return nil
        }
        
        return nil
    }
    
    // MARK: - Accept Share
    
    /// Accept a CKShare from another user's zone (roaming access).
    public func acceptShare(url: URL) async throws {
        logger.info("Accepting share from URL: \(url.absoluteString)")
        
        let metadata = try await container.shareMetadata(for: url)
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
        
        self.isZoneReady = true
        logger.info("Successfully accepted share")
    }
}

public enum UserDataZoneError: Error {
    case shareCreationFailed
    case registryLookupFailed
    case shareAcceptFailed
}
