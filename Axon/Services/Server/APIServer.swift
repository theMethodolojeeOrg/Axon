//
//  APIServer.swift
//  Axon
//
//  Local OpenAI-compatible HTTP server for developer access.
//  Includes epistemic API endpoints for grounded context access.
//

import Foundation
import FlyingFox
import Combine

struct ServerStatus: Encodable, Sendable {
    let status: String
    let version: String
    let endpoints: [String]
    let epistemicEndpoints: [String]
}

struct ModelsResponse: Encodable, Sendable {
    let object: String = "list"
    let data: [ModelInfo]
}

struct ModelInfo: Encodable, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

@MainActor
class APIServer: ObservableObject {
    static let shared = APIServer()

    @Published var isRunning = false
    @Published var error: String?
    @Published var localURL: String = ""
    @Published var networkURL: String = ""

    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?
    private var password: String?

    private init() {}

    // MARK: - Server Control

    func start(port: UInt16, password: String?, allowExternal: Bool) async {
        guard !isRunning else { return }

        self.password = password

        // Create server with specified port
        server = HTTPServer(port: port)

        guard let server = server else { return }

        // Register routes
        await registerRoutes(on: server, password: password)

        // Start server in background task
        serverTask = Task {
            do {
                try await server.run()
            } catch {
                await MainActor.run {
                    self.error = "Server error: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }

        isRunning = true
        error = nil

        // Update URLs
        localURL = "http://localhost:\(port)"
        if allowExternal {
            networkURL = "http://\(getLocalIPAddress() ?? "0.0.0.0"):\(port)"
        } else {
            networkURL = ""
        }

        print("[APIServer] Server started on \(localURL)")
    }

    func stop() async {
        guard isRunning else { return }

        serverTask?.cancel()
        serverTask = nil
        server = nil
        isRunning = false
        localURL = ""
        networkURL = ""

        print("[APIServer] Server stopped")
    }

    // MARK: - Route Registration

    private func registerRoutes(on server: HTTPServer, password: String?) async {
        // Capture services for use in nonisolated route handlers
        let settingsStorage = SettingsStorage.shared
        let conversationService = ConversationService.shared

        // Health check endpoint
        await server.appendRoute("GET /server/status") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            let status = ServerStatus(
                status: "running",
                version: "1.0.0",
                endpoints: [
                    "/v1/chat/completions",
                    "/chat/completions",
                    "/models",
                    "/server/status"
                ],
                epistemicEndpoints: [
                    "/api/memories/ground",
                    "/api/memories/inject",
                    "/api/shift-logs",
                    "/api/learning/stats",
                    "/api/predicates"
                ]
            )

            return try self.jsonResponse(status)
        }

        // Register epistemic API endpoints
        await registerEpistemicRoutes(on: server, password: password)

        // Models endpoint - OpenAI compatible
        await server.appendRoute("GET /models") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            // Get current settings to determine available models
            let settings = settingsStorage.loadSettings() ?? AppSettings()
            var modelInfoList: [ModelInfo] = []

            // Check if using custom provider
            if let customProviderId = settings.selectedCustomProviderId,
               let customProvider = settings.customProviders.first(where: { $0.id == customProviderId }) {
                // Return custom provider's models
                for model in customProvider.models {
                    modelInfoList.append(ModelInfo(
                        id: model.modelCode,
                        object: "model",
                        created: 1686935002,
                        ownedBy: customProvider.providerName
                    ))
                }
            } else {
                // Return built-in provider's models
                let provider = settings.defaultProvider
                for model in provider.availableModels {
                    modelInfoList.append(ModelInfo(
                        id: model.id,
                        object: "model",
                        created: 1686935002,
                        ownedBy: provider.displayName
                    ))
                }
            }

            let models = ModelsResponse(data: modelInfoList)
            return try self.jsonResponse(models)
        }

        // Chat completions endpoint (without /v1 prefix for compatibility)
        await server.appendRoute("POST /chat/completions") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            // Authenticate request
            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    let error = OpenAIErrorResponse.from(
                        message: "Invalid or missing authentication",
                        type: "authentication_error",
                        code: "invalid_api_key"
                    )
                    return try self.jsonResponse(error, statusCode: .unauthorized)
                }
            }

            // Parse request body
            let chatRequest: ChatCompletionRequest
            do {
                let bodyData = try await request.bodyData

                // Debug: Print raw body
                #if DEBUG
                if let bodyString = String(data: bodyData, encoding: .utf8) {
                    print("[APIServer] Request body: \(bodyString)")
                }
                #endif

                chatRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: bodyData)
            } catch {
                #if DEBUG
                print("[APIServer] Decoding error: \(error)")
                #endif
                let error = OpenAIErrorResponse.from(
                    message: "Invalid request body: \(error.localizedDescription)",
                    type: "invalid_request_error"
                )
                return try self.jsonResponse(error, statusCode: .badRequest)
            }

            // Process the chat completion
            do {
                let response = try await self.handleChatCompletion(
                    request: chatRequest,
                    settingsStorage: settingsStorage,
                    conversationService: conversationService
                )
                return try self.jsonResponse(response)
            } catch {
                let errorResponse = OpenAIErrorResponse.from(
                    message: error.localizedDescription,
                    type: "server_error"
                )
                return try self.jsonResponse(errorResponse, statusCode: .internalServerError)
            }
        }

        // Main OpenAI-compatible chat completions endpoint (with /v1 prefix)
        await server.appendRoute("POST /v1/chat/completions") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            // Authenticate request
            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    let error = OpenAIErrorResponse.from(
                        message: "Invalid or missing authentication",
                        type: "authentication_error",
                        code: "invalid_api_key"
                    )
                    return try self.jsonResponse(error, statusCode: .unauthorized)
                }
            }

            // Parse request body
            let chatRequest: ChatCompletionRequest
            do {
                let bodyData = try await request.bodyData

                // Debug: Print raw body
                #if DEBUG
                if let bodyString = String(data: bodyData, encoding: .utf8) {
                    print("[APIServer] Request body: \(bodyString)")
                }
                #endif

                chatRequest = try JSONDecoder().decode(ChatCompletionRequest.self, from: bodyData)
            } catch {
                #if DEBUG
                print("[APIServer] Decoding error: \(error)")
                #endif
                let error = OpenAIErrorResponse.from(
                    message: "Invalid request body: \(error.localizedDescription)",
                    type: "invalid_request_error"
                )
                return try self.jsonResponse(error, statusCode: .badRequest)
            }

            // Process the chat completion
            do {
                let response = try await self.handleChatCompletion(
                    request: chatRequest,
                    settingsStorage: settingsStorage,
                    conversationService: conversationService
                )
                return try self.jsonResponse(response)
            } catch {
                let errorResponse = OpenAIErrorResponse.from(
                    message: error.localizedDescription,
                    type: "server_error"
                )
                return try self.jsonResponse(errorResponse, statusCode: .internalServerError)
            }
        }
    }

    // MARK: - Chat Completion Handler

    private func handleChatCompletion(
        request: ChatCompletionRequest,
        settingsStorage: SettingsStorage,
        conversationService: ConversationService
    ) async throws -> ChatCompletionResponse {
        // Get current settings
        let settings = settingsStorage.loadSettings() ?? AppSettings()

        // Extract messages
        let messages = request.messages
        guard !messages.isEmpty else {
            throw NSError(domain: "APIServer", code: 400, userInfo: [NSLocalizedDescriptionKey: "Messages array cannot be empty"])
        }

        // Find or create conversation
        // For OpenAI compatibility, we'll create a new conversation for each request
        // or use the first message as the title
        let title = messages.first?.content.prefix(50).description ?? "API Conversation"
        let conversation = try await conversationService.createConversation(title: String(title))

        // Extract user message (last non-system message)
        let userMessages = messages.filter { $0.role == "user" }
        guard let lastUserMessage = userMessages.last else {
            throw NSError(domain: "APIServer", code: 400, userInfo: [NSLocalizedDescriptionKey: "No user message found"])
        }

        // Send message and get response
        // Note: The orchestrate endpoint will handle memory injection based on settings
        // unless explicitly disabled via disableMemories parameter
        _ = try await conversationService.sendMessage(
            conversationId: conversation.id,
            content: lastUserMessage.content
        )

        // Get the assistant's response
        let conversationMessages = try await conversationService.getMessages(conversationId: conversation.id)
        guard let assistantMessage = conversationMessages.last, assistantMessage.role == .assistant else {
            throw NSError(domain: "APIServer", code: 500, userInfo: [NSLocalizedDescriptionKey: "No assistant response received"])
        }

        // Build OpenAI-compatible response
        let response = ChatCompletionResponse.from(
            conversationId: conversation.id,
            messages: conversationMessages,
            assistantMessage: assistantMessage,
            model: request.model,
            usage: assistantMessage.tokens
        )

        return response
    }

    // MARK: - Authentication

    nonisolated private func authenticate(request: HTTPRequest, password: String) -> Bool {
        // Check Authorization header (Bearer token)
        if let authHeader = request.headers[HTTPHeader.authorization] {
            let token = authHeader.replacingOccurrences(of: "Bearer ", with: "")
            return token == password
        }

        return false
    }

    // MARK: - Response Helpers

    nonisolated private func jsonResponse<T: Encodable>(_ data: T, statusCode: HTTPStatusCode = .ok) throws -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let jsonData = try encoder.encode(data)

        return HTTPResponse(
            statusCode: statusCode,
            headers: [
                .contentType: "application/json",
                HTTPHeader("Access-Control-Allow-Origin"): "*",
                HTTPHeader("Access-Control-Allow-Methods"): "GET, POST, OPTIONS",
                HTTPHeader("Access-Control-Allow-Headers"): "Content-Type, Authorization"
            ],
            body: jsonData
        )
    }

    // MARK: - Network Utilities

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }

        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" {  // WiFi interface
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                              socklen_t(interface.ifa_addr.pointee.sa_len),
                              &hostname,
                              socklen_t(hostname.count),
                              nil,
                              socklen_t(0),
                              NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }

        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Epistemic API Routes

    private func registerEpistemicRoutes(on server: HTTPServer, password: String?) async {
        let memoryService = MemoryService.shared
        let epistemicEngine = EpistemicEngine.shared
        let salienceService = SalienceService.shared
        let learningLoopService = LearningLoopService.shared
        let predicateLogger = PredicateLogger.shared

        // GET /api/memories/ground?q={query}
        // Ground a query against memories and return epistemic context
        await server.appendRoute("GET /api/memories/ground") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            // Authenticate if password is set
            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
            }

            // Extract query parameter
            guard let url = URL(string: request.path),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let query = components.queryItems?.first(where: { $0.name == "q" })?.value else {
                return try self.jsonResponse(
                    EpistemicErrorResponse(error: "Missing query parameter 'q'"),
                    statusCode: .badRequest
                )
            }

            // Perform grounding
            let correlationId = await predicateLogger.startCorrelation()
            defer { Task { await predicateLogger.endCorrelation() } }

            let memories = await memoryService.memories
            let context = await epistemicEngine.ground(
                userMessage: query,
                memories: memories,
                correlationId: correlationId
            )

            // Build response
            let response = EpistemicGroundResponse(
                query: query,
                groundedFacts: context.groundedFacts.map { fact in
                    EpistemicFactResponse(
                        id: fact.id,
                        content: fact.content,
                        confidence: fact.confidence,
                        source: fact.source,
                        evidence: fact.evidence
                    )
                },
                compositeConfidence: context.compositeConfidence,
                shiftLogId: context.shiftLog.id,
                epistemicBoundaries: EpistemicBoundariesResponse(
                    grounded: context.shiftLog.epistemicScope.grounded,
                    unknown: context.shiftLog.epistemicScope.unknown,
                    assumptions: context.shiftLog.epistemicScope.assumptions
                )
            )

            return try self.jsonResponse(response)
        }

        // POST /api/memories/inject
        // Get formatted memory injection for a conversation context
        await server.appendRoute("POST /api/memories/inject") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
            }

            // Parse request
            struct InjectRequest: Decodable {
                let messages: [String]
                let maxTokens: Int?
            }

            let injectRequest: InjectRequest
            do {
                let bodyData = try await request.bodyData
                injectRequest = try JSONDecoder().decode(InjectRequest.self, from: bodyData)
            } catch {
                return try self.jsonResponse(
                    EpistemicErrorResponse(error: "Invalid request body"),
                    statusCode: .badRequest
                )
            }

            let correlationId = await predicateLogger.startCorrelation()
            defer { Task { await predicateLogger.endCorrelation() } }

            // Create mock messages from strings
            let mockMessages = injectRequest.messages.enumerated().map { index, content in
                Message(
                    conversationId: "api-request",
                    role: index % 2 == 0 ? .user : .assistant,
                    content: content
                )
            }

            let memories = await memoryService.memories
            let result = await salienceService.injectSalient(
                conversation: mockMessages,
                memories: memories,
                availableTokens: injectRequest.maxTokens ?? 2000,
                correlationId: correlationId
            )

            let response = SalienceInjectResponse(
                injectionBlock: result.injectionBlock,
                selectedMemoryCount: result.selectedMemories.count,
                totalCandidates: result.totalCandidates,
                tokenCount: result.tokenCount,
                confidence: result.epistemicContext.compositeConfidence
            )

            return try self.jsonResponse(response)
        }

        // GET /api/shift-logs
        // Get recent shift logs for debugging/transparency
        await server.appendRoute("GET /api/shift-logs") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
            }

            // For now, return predicate logs as shift log proxies
            let predicates = await predicateLogger.predicates.suffix(50)
            let response = PredicateLogsResponse(
                predicates: predicates.map { pred in
                    PredicateLogResponse(
                        id: pred.id,
                        event: pred.event,
                        predicate: pred.predicate,
                        passed: pred.passed,
                        scope: pred.scope.rawValue,
                        correlationId: pred.correlationId,
                        timestamp: pred.timestamp.ISO8601Format()
                    )
                }
            )

            return try self.jsonResponse(response)
        }

        // GET /api/learning/stats
        // Get learning loop statistics
        await server.appendRoute("GET /api/learning/stats") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
            }

            let stats = await learningLoopService.getLearningStats()
            let response = LearningStatsResponse(
                totalPredictions: stats.totalPredictions,
                confirmedCount: stats.confirmedCount,
                contradictedCount: stats.contradictedCount,
                refinedCount: stats.refinedCount,
                averageReliability: stats.averageReliability,
                memoriesTracked: stats.memoriesTracked,
                confirmationRate: stats.confirmationRate,
                contradictionRate: stats.contradictionRate
            )

            return try self.jsonResponse(response)
        }

        // GET /api/predicates?correlationId={id}
        // Get predicate proof tree for a correlation
        await server.appendRoute("GET /api/predicates") { [weak self] request in
            guard let self = self else {
                return HTTPResponse(statusCode: .internalServerError)
            }

            if let password = password, !password.isEmpty {
                guard self.authenticate(request: request, password: password) else {
                    return HTTPResponse(statusCode: .unauthorized)
                }
            }

            // Check for correlationId parameter
            if let url = URL(string: request.path),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let correlationId = components.queryItems?.first(where: { $0.name == "correlationId" })?.value {
                // Return predicates for specific correlation
                let predicates = await predicateLogger.predicates(for: correlationId)
                let reliability = await predicateLogger.compositeReliability(for: correlationId)

                let response = PredicateTreeResponse(
                    correlationId: correlationId,
                    predicateCount: predicates.count,
                    compositeReliability: reliability,
                    predicates: predicates.map { pred in
                        PredicateLogResponse(
                            id: pred.id,
                            event: pred.event,
                            predicate: pred.predicate,
                            passed: pred.passed,
                            scope: pred.scope.rawValue,
                            correlationId: pred.correlationId,
                            timestamp: pred.timestamp.ISO8601Format()
                        )
                    }
                )
                return try self.jsonResponse(response)
            } else {
                // Return all recent predicates
                let predicates = await predicateLogger.predicates.suffix(100)
                let response = PredicateLogsResponse(
                    predicates: predicates.map { pred in
                        PredicateLogResponse(
                            id: pred.id,
                            event: pred.event,
                            predicate: pred.predicate,
                            passed: pred.passed,
                            scope: pred.scope.rawValue,
                            correlationId: pred.correlationId,
                            timestamp: pred.timestamp.ISO8601Format()
                        )
                    }
                )
                return try self.jsonResponse(response)
            }
        }
    }
}

// MARK: - Epistemic API Response Types

struct EpistemicErrorResponse: Encodable {
    let error: String
}

struct EpistemicGroundResponse: Encodable {
    let query: String
    let groundedFacts: [EpistemicFactResponse]
    let compositeConfidence: Double
    let shiftLogId: String
    let epistemicBoundaries: EpistemicBoundariesResponse
}

struct EpistemicFactResponse: Encodable {
    let id: String
    let content: String
    let confidence: Double
    let source: String
    let evidence: String?
}

struct EpistemicBoundariesResponse: Encodable {
    let grounded: [String]
    let unknown: [String]
    let assumptions: [String]
}

struct SalienceInjectResponse: Encodable {
    let injectionBlock: String
    let selectedMemoryCount: Int
    let totalCandidates: Int
    let tokenCount: Int
    let confidence: Double
}

struct PredicateLogsResponse: Encodable {
    let predicates: [PredicateLogResponse]
}

struct PredicateLogResponse: Encodable {
    let id: String
    let event: String
    let predicate: String
    let passed: Bool
    let scope: String
    let correlationId: String
    let timestamp: String
}

struct PredicateTreeResponse: Encodable {
    let correlationId: String
    let predicateCount: Int
    let compositeReliability: Double
    let predicates: [PredicateLogResponse]
}

struct LearningStatsResponse: Encodable {
    let totalPredictions: Int
    let confirmedCount: Int
    let contradictedCount: Int
    let refinedCount: Int
    let averageReliability: Double
    let memoriesTracked: Int
    let confirmationRate: Double
    let contradictionRate: Double
}
