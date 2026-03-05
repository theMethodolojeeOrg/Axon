import Foundation

public enum AIParadigm: String, Codable {
    case llm = "llm"
    case titan = "titan"
    case axon = "axon"
    
    public var requiresSovereignty: Bool {
        self == .axon
    }
    
    public var hasPersistentIdentity: Bool {
        self == .axon
    }
}

public enum DeviceSpecifier: Codable, Hashable, CustomStringConvertible {
    case specific(String)
    case deviceClass(String)
    case wildcard
    case none
    
    public var description: String {
        switch self {
        case .specific(let id): return id
        case .deviceClass(let cls): return "class:\(cls)"
        case .wildcard: return "*"
        case .none: return ""
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        if str == "*" {
            self = .wildcard
        } else if str.hasPrefix("class:") {
            self = .deviceClass(String(str.dropFirst(6)))
        } else if str.isEmpty {
            self = .none
        } else {
            self = .specific(str)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }
}

public struct AIPAddress: Codable, Hashable, Identifiable {
    public var id: String { canonicalForm }
    
    public let paradigm: AIParadigm
    public let identity: String
    public let scope: String?
    public let device: DeviceSpecifier?
    public let parameters: [String: String]
    
    public init(paradigm: AIParadigm, identity: String, scope: String? = nil, device: DeviceSpecifier? = nil, parameters: [String: String] = [:]) {
        self.paradigm = paradigm
        self.identity = identity
        self.scope = scope
        self.device = device
        self.parameters = parameters
    }
    
    public var canonicalForm: String {
        var result = "ai://\(paradigm.rawValue)/\(identity)"
        if let scope = scope { result += "/\(scope)" }
        if let device = device, device != .none { result += "/\(device.description)" }
        if !parameters.isEmpty {
            let sortedKeys = parameters.keys.sorted()
            let params = sortedKeys.map { "\($0)=\(parameters[$0] ?? "")" }.joined(separator: "&")
            result += "?\(params)"
        }
        return result
    }
    
    public var bioID: String? {
        // Extract BioID from identity (name.bioid)
        let parts = identity.split(separator: ".")
        if parts.count >= 2 {
            return String(parts.last!)
        }
        return nil
    }
    
    public var name: String {
        let parts = identity.split(separator: ".")
        if parts.count >= 2 {
            return parts.dropLast().joined(separator: ".")
        }
        return identity
    }
}

public struct AIPAddressParser {
    public enum ParseError: Error {
        case invalidProtocol
        case missingParadigm
        case invalidParadigm(String)
        case missingIdentity
        case invalidFormat(String)
    }
    
    public static func parse(_ address: String) throws -> AIPAddress {
        guard address.hasPrefix("ai://") else {
            throw ParseError.invalidProtocol
        }
        
        let withoutProtocol = String(address.dropFirst(5))
        let parts = withoutProtocol.split(separator: "?", maxSplits: 1)
        let pathPart = String(parts[0])
        let paramsPart = parts.count > 1 ? String(parts[1]) : nil
        
        // Split by / but handle potential empty scope/device if needed, though split usually handles it.
        // Swift split can omit empty sequences by default.
        let pathComponents = pathPart.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        
        guard pathComponents.count >= 2 else {
            throw ParseError.invalidFormat("Need at least paradigm and identity")
        }
        
        guard let paradigm = AIParadigm(rawValue: pathComponents[0]) else {
            throw ParseError.invalidParadigm(pathComponents[0])
        }
        
        let identity = pathComponents[1]
        let scope: String? = pathComponents.count > 2 ? pathComponents[2] : nil
        
        var device: DeviceSpecifier? = nil
        if pathComponents.count > 3 {
             device = parseDevice(pathComponents[3])
        }
        
        let parameters = parseParameters(paramsPart)
        
        return AIPAddress(
            paradigm: paradigm,
            identity: identity,
            scope: scope,
            device: device,
            parameters: parameters
        )
    }
    
    private static func parseDevice(_ str: String) -> DeviceSpecifier {
        if str == "*" {
            return .wildcard
        } else if str.hasPrefix("class:") {
            return .deviceClass(String(str.dropFirst(6)))
        } else {
            return .specific(str)
        }
    }
    
    private static func parseParameters(_ str: String?) -> [String: String] {
        guard let str = str else { return [:] }
        var result: [String: String] = [:]
        for pair in str.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                result[String(kv[0])] = String(kv[1])
            }
        }
        return result
    }
}
