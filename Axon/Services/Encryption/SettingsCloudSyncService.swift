import Foundation
import FirebaseAuth
import FirebaseFirestore

final class SettingsCloudSyncService {
    static let shared = SettingsCloudSyncService()
    private init() {}

    enum SettingsCloudSyncError: LocalizedError {
        case notAuthenticated
        case notFound
        case invalidFormat

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "User is not authenticated."
            case .notFound:
                return "Settings not found in cloud."
            case .invalidFormat:
                return "Settings data is in invalid format."
            }
        }
    }

    func pushSettings(_ settings: AppSettings) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SettingsCloudSyncError.notAuthenticated
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(settings)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw SettingsCloudSyncError.invalidFormat
        }

        let payload: [String: Any] = [
            "app": [
                "blob": jsonString,
                "version": settings.version,
                "updatedAt": FieldValue.serverTimestamp()
            ]
        ]

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("settings")
            .document("appSettings")

        try await ref.setData(payload, merge: true)
    }

    func pullSettings() async throws -> AppSettings {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw SettingsCloudSyncError.notAuthenticated
        }

        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection("settings")
            .document("appSettings")

        let snapshot = try await ref.getDocument()
        guard let data = snapshot.data(),
              let app = data["app"] as? [String: Any],
              let blob = app["blob"] as? String,
              let blobData = blob.data(using: .utf8) else {
            throw SettingsCloudSyncError.notFound
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let settings = try decoder.decode(AppSettings.self, from: blobData)
        return settings
    }
}
