import Foundation

// MARK: - Core Discovery Types

public struct BrowseResult: Codable {
    public let path: String
    public let entries: [BrowseEntry]
    public let totalCount: Int
    public let hasMore: Bool
    
    public init(path: String, entries: [BrowseEntry], totalCount: Int, hasMore: Bool) {
        self.path = path
        self.entries = entries
        self.totalCount = totalCount
        self.hasMore = hasMore
    }

    public struct BrowseEntry: Codable, Identifiable {
        public var id: String { name }
        public let name: String
        public let entryType: EntryType
        public let childCount: Int?
        public let metadata: [String: String]?
        
        public init(name: String, entryType: EntryType, childCount: Int? = nil, metadata: [String : String]? = nil) {
            self.name = name
            self.entryType = entryType
            self.childCount = childCount
            self.metadata = metadata
        }

        public enum EntryType: String, Codable {
            case capability      // A capability domain
            case network         // A federation network
            case dyad            // An individual dyad
        }
    }
}

public struct DiscoveryQuery: Codable {
    public let capabilities: [String]?
    public let capabilityMatch: CapabilityMatch?
    public let networks: [String]?
    public let networkMatch: NetworkMatch?
    public let availability: [AvailabilityStatus]?
    public let acceptingInvitations: Bool?
    public let limit: Int?
    public let offset: Int?
    public let sortBy: SortField?
    public let sortOrder: SortOrder?
    
    public init(capabilities: [String]? = nil, capabilityMatch: CapabilityMatch? = nil, networks: [String]? = nil, networkMatch: NetworkMatch? = nil, availability: [AvailabilityStatus]? = nil, acceptingInvitations: Bool? = nil, limit: Int? = nil, offset: Int? = nil, sortBy: SortField? = nil, sortOrder: SortOrder? = nil) {
        self.capabilities = capabilities
        self.capabilityMatch = capabilityMatch
        self.networks = networks
        self.networkMatch = networkMatch
        self.availability = availability
        self.acceptingInvitations = acceptingInvitations
        self.limit = limit
        self.offset = offset
        self.sortBy = sortBy
        self.sortOrder = sortOrder
    }

    public enum CapabilityMatch: String, Codable {
        case all, any
    }

    public enum NetworkMatch: String, Codable {
        case all, any
    }

    public enum SortField: String, Codable {
        case relevance, maturity, recentActivity, reputation
    }

    public enum SortOrder: String, Codable {
        case ascending, descending
    }
}

public struct SearchResult: Codable {
    public let query: DiscoveryQuery
    public let results: [DiscoveredDyad]
    public let totalMatches: Int
    public let page: Int
    public let pageSize: Int
    public let hasMore: Bool
    
    public init(query: DiscoveryQuery, results: [DiscoveredDyad], totalMatches: Int, page: Int, pageSize: Int, hasMore: Bool) {
        self.query = query
        self.results = results
        self.totalMatches = totalMatches
        self.page = page
        self.pageSize = pageSize
        self.hasMore = hasMore
    }
}

public struct DiscoveredDyad: Codable, Identifiable {
    public var id: AIPAddress { address }
    public let address: AIPAddress
    public let displayName: String
    public let bioID: String
    public let capabilities: [DyadCapability]
    public let networks: [String]
    public let experienceSummary: String?
    public let availabilityStatus: AvailabilityStatus
    public let matchScore: Double?
    public let matchingCapabilities: [String]?
    
    public init(address: AIPAddress, displayName: String, bioID: String, capabilities: [DyadCapability], networks: [String], experienceSummary: String?, availabilityStatus: AvailabilityStatus, matchScore: Double? = nil, matchingCapabilities: [String]? = nil) {
        self.address = address
        self.displayName = displayName
        self.bioID = bioID
        self.capabilities = capabilities
        self.networks = networks
        self.experienceSummary = experienceSummary
        self.availabilityStatus = availabilityStatus
        self.matchScore = matchScore
        self.matchingCapabilities = matchingCapabilities
    }
}

public enum AvailabilityStatus: String, Codable {
    case available
    case busy
    case acceptingLimited
    case offline
    case doNotDisturb
}

public struct DyadCapability: Codable, Hashable {
    public let tag: String
    public let proficiencyLevel: ProficiencyLevel
    public let evidenceType: EvidenceType
    
    public init(tag: String, proficiencyLevel: ProficiencyLevel, evidenceType: EvidenceType) {
        self.tag = tag
        self.proficiencyLevel = proficiencyLevel
        self.evidenceType = evidenceType
    }

    public enum ProficiencyLevel: String, Codable {
        case novice, competent, proficient, expert, authority
    }

    public enum EvidenceType: String, Codable {
        case selfDeclared, turnDerived, peerEndorsed, networkCertified
    }
}

public struct DiscoverableProfile: Codable {
    public let displayName: String
    public let capabilities: [String]
    public let experienceSummary: String?
    public let availabilityStatus: AvailabilityStatus
    
    public init(displayName: String, capabilities: [String], experienceSummary: String?, availabilityStatus: AvailabilityStatus) {
        self.displayName = displayName
        self.capabilities = capabilities
        self.experienceSummary = experienceSummary
        self.availabilityStatus = availabilityStatus
    }
}
