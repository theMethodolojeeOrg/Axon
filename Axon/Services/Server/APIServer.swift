//
//  APIServer.swift
//  Axon
//
//  Local OpenAI-compatible HTTP server for developer access
//

import Foundation
import FlyingFox
import Combine

struct ServerStatus: Encodable, Sendable {
    let status: String
    let version: String
    let endpoints: [String]
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
                ]
            )

            return try self.jsonResponse(status)
        }

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
}
