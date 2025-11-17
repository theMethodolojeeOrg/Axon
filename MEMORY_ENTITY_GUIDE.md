# MemoryEntity Core Data Setup

## Important: Naming Convention

**Entity Name:** `MemoryEntity` (NOT just "Memory")

This avoids naming conflicts with the existing `Memory` Swift struct. Following the same pattern as:

- `ConversationEntity` → generates `ConversationEntity` class
- `MessageEntity` → generates `MessageEntity` class
- `MemoryEntity` → generates `MemoryEntity` class

## Instructions for Adding MemoryEntity to Axon.xcdatamodeld

1. Open `Axon.xcdatamodeld` in Xcode
2. Click the "+" button at the bottom to add a new entity
3. Name it: **`MemoryEntity`** (exactly as written, case-sensitive)
4. Set Code Generation to: **`Class Definition`**
5. Set Codegen to: **`Class Definition`** (in Data Model Inspector)
6. Check the box for "Sync with CloudKit" if you want iCloud sync (optional)

## Attributes to Add

Add the following attributes:

| Attribute Name | Type | Optional | Default Value |
|----------------|------|----------|---------------|
| id | String | No | "" |
| userId | String | No | "" |
| content | String | No | "" |
| type | String | No | "fact" |
| confidence | Double | No | 0.0 |
| tags | Transformable | Yes | nil |
| metadata | Transformable | Yes | nil |
| sourceConversationId | String | Yes | nil |
| sourceMessageId | String | Yes | nil |
| sourceTimestamp | Date | Yes | nil |
| relatedMemoryIds | Transformable | Yes | nil |
| createdAt | Date | No | (current date) |
| updatedAt | Date | No | (current date) |
| lastAccessedAt | Date | Yes | nil |
| accessCount | Integer 32 | No | 0 |
| syncStatus | String | Yes | "synced" |
| locallyModified | Boolean | No | NO |

## Important Configuration

### For Transformable Attributes:
- **tags**: Set Value Transformer Name to `NSSecureUnarchiveFromData`, Custom Class to `[String]`
- **metadata**: Set Value Transformer Name to `NSSecureUnarchiveFromData`, Custom Class to `NSDictionary`
- **relatedMemoryIds**: Set Value Transformer Name to `NSSecureUnarchiveFromData`, Custom Class to `[String]`

### Uniqueness Constraint:
1. Click on the entity
2. In the Data Model Inspector (right panel)
3. Under "Constraints", add a uniqueness constraint on: `id`

## After Adding the Entity

Once you've added the entity in Xcode:
1. Build the project (Cmd+B) to generate the entity class
2. The MemorySyncManager code below will be able to use it
3. Memories will persist across app restarts
