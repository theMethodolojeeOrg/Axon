import CoreData

@objc(MemoryEntity)
public class MemoryEntity: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<MemoryEntity> {
        return NSFetchRequest<MemoryEntity>(entityName: "MemoryEntity")
    }

    @NSManaged public var id: String?
    @NSManaged public var userId: String?
    @NSManaged public var content: String?
    @NSManaged public var type: String?
    @NSManaged public var confidence: Double
    @NSManaged public var tags: NSObject?
    @NSManaged public var metadata: NSDictionary?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var lastAccessedAt: Date?
    @NSManaged public var accessCount: Int32
    @NSManaged public var syncStatus: String?
    @NSManaged public var locallyModified: Bool
    @NSManaged public var sourceConversationId: String?
    @NSManaged public var sourceMessageId: String?
    @NSManaged public var sourceTimestamp: Date?
    @NSManaged public var relatedMemoryIds: NSObject?

    public var tagsArray: [String] {
        get {
            return (tags as? [String]) ?? []
        }
        set {
            tags = newValue as NSArray
        }
    }

    public var relatedMemoryIdsArray: [String] {
        get {
            return (relatedMemoryIds as? [String]) ?? []
        }
        set {
            relatedMemoryIds = newValue as NSArray
        }
    }
}
