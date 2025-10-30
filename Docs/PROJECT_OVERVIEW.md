# NeurXAxonChat: Project Overview & SwiftUI Implementation Guide

## Executive Summary

**NeurXAxonChat** is a sophisticated memory-augmented AI chat platform that transforms how users interact with language models by adding intelligent memory management, conversation organization, and advanced analytics. The system consists of a production-ready REST API (49 endpoints across 7 phases) and a SwiftUI native application that provides a seamless, feature-rich user experience.

**Platform Goals:**
- Extract business logic from UI into production REST APIs
- Enable multi-device synchronization and cross-platform access
- Create an intelligent memory system that contextualizes conversations
- Provide comprehensive analytics on learning and knowledge growth

---

## Core System Architecture

### Backend (Firebase Cloud Functions)

**Language:** TypeScript/Node.js
**Database:** Firestore (NoSQL)
**Storage:** Google Cloud Storage
**Authentication:** Firebase Authentication + Custom API Key validation

**49 REST Endpoints organized in 7 phases:**
- Phase 1: Core Memory API (4 endpoints)
- Phase 2: Conversation Management (7 endpoints)
- Phase 3: Artifact Management (8 endpoints)
- Phase 4: Settings & Projects (10 endpoints)
- Phase 5: Audio & Tool Execution (7 endpoints)
- Phase 6: Batch Operations & Import/Export (5 endpoints)
- Phase 7: Advanced Features & Analytics (8 endpoints)

### Frontend (SwiftUI Native App)

**Platform:** iOS/iPadOS/macOS (Universal SwiftUI)
**Architecture:** MVVM with Observation Framework
**State Management:** @StateObject, @ObservedObject, @Environment
**Networking:** URLSession with custom API client wrapper
**Local Storage:** Keychain (for sensitive data), UserDefaults (for preferences)

---

## Core Concepts & Mental Model

### 1. Memory System

The foundation of NeurXAxonChat is an intelligent memory system that learns from conversations:

**Memory Types:**
- **Fact** - Discrete pieces of information (e.g., "Python lists are mutable")
- **Procedure** - Step-by-step processes (e.g., "How to deploy using npm")
- **Context** - Situational knowledge (e.g., "User is learning web development")
- **Relationship** - Connections between other memories

**Key Attributes:**
```
Memory {
  id: UUID
  type: MemoryType
  content: String
  confidence: Float (0-1)
    - 0.0-0.3: hypothesis (learning/uncertain)
    - 0.3-0.7: uncertain (in progress)
    - 0.7-1.0: established (high confidence)
  tags: [String]
  projectId: UUID?
  createdAt: Date
  updatedAt: Date
  supersedesMemoryId: UUID? (which memory this replaces)
  context: String? (how this was learned)
}
```

**Memory Lifecycle:**
1. User converses with AI
2. AI response parsed for memory tags (`<memory>...</memory>`)
3. Memories extracted, validated, compressed
4. Stored in Firestore with user encryption
5. Used to contextualize future conversations
6. Updated/replaced as knowledge evolves

### 2. Conversation System

Conversations are the primary unit of interaction:

**Conversation Structure:**
```
Conversation {
  id: UUID
  title: String
  projectId: UUID (organize into projects)
  messages: [Message]
  injectedMemories: [Memory] (auto-retrieved from memory system)
  messageCount: Int
  archived: Bool
  createdAt: Date
  updatedAt: Date
}
```

**Message Structure:**
```
Message {
  id: UUID
  conversationId: UUID
  role: MessageRole (user|assistant|system)
  content: String
  audioUrl: String? (TTS generated)
  createdAt: Date
}
```

**Key Features:**
- Auto-inject relevant memories before sending to AI
- Encrypt message content at rest
- Support for audio generation (ElevenLabs TTS)
- Full message history retrieval with pagination

### 3. Artifact System

Capture code, scripts, and structured content from conversations:

**Artifact Types:**
- **code** - Programming code (Python, JavaScript, etc.)
- **text** - Structured text content
- **diagram** - Visual diagrams/architecture

**Artifact Structure:**
```
Artifact {
  id: UUID
  type: ArtifactType
  language: String? (for code)
  title: String
  code: String (content)
  conversationId: UUID
  projectId: UUID?
  versionCount: Int
  archived: Bool
  createdAt: Date
  updatedAt: Date
  versions: [ArtifactVersion] (full history)
}
```

**Key Features:**
- Automatic extraction from LLM responses using XML parsing
- Version history tracking
- Fork/duplicate functionality
- Search and filter by type, conversation, or project

### 4. Project Organization

Group conversations, memories, and artifacts by domain:

**Project Structure:**
```
Project {
  id: UUID
  name: String
  description: String?
  icon: String? (emoji)
  conversationCount: Int
  memoryCount: Int
  artifactCount: Int
  archived: Bool
  createdAt: Date
  updatedAt: Date
}
```

**Project Analytics:**
- Conversation and memory counts
- Memory distribution (allocentric vs egoic)
- Confidence distribution (hypothesis/uncertain/established)
- Top tags (what's being learned)

### 5. Settings & Preferences

User-scoped configuration with cloud sync:

**Settings Structure:**
```
Settings {
  theme: Theme (light|dark|system)
  provider: LLMProvider (anthropic|openai|gemini)
  model: String (e.g., "claude-3-sonnet")
  apiKeys: {
    [provider]: String (encrypted)
  }
  tts: {
    provider: String (elevenlabs)
    voiceId: String
    model: String
    stability: Float
    similarityBoost: Float
  }
  keyboardShortcuts: {
    send: String
    newChat: String
  }
}
```

**Key Features:**
- Synced across devices via Firestore
- Encrypted API keys (never expose to client)
- Support for multiple LLM providers
- Customizable TTS voice settings

### 6. Analytics & Insights

Comprehensive learning analytics:

**Knowledge Map:**
- Nodes: memories, tags, projects
- Edges: relationships, tags, project membership
- Useful for graph visualizations (D3.js, Cytoscape pattern)
- Distribution metrics (confidence, tags, types)

**Learning Timeline:**
- Chronological events (memory created, updated, relationships added)
- Confidence progression tracking
- Learning velocity (memories per day)
- Time span metrics

**AI-Generated Insights:**
- Learning velocity trend
- Knowledge refinement status
- Active refinement (update ratio)
- Knowledge specialization (top tags)
- Diversification recommendations
- Learning consistency metrics
- Next learning areas predictions

**Completeness Score:**
- 0-1 scale based on:
  - Memory count (normalized)
  - Average confidence (40% weight)
  - Tag diversity (20% weight)
  - Activity consistency (10% weight)

### 7. Audio System

Text-to-speech generation and storage:

**Key Features:**
- ElevenLabs TTS integration
- Automatic text chunking (respects model character limits)
- Sequential generation with rate limiting
- Firebase Storage integration
- 7-day signed URLs for downloads
- Support for multiple voices and models

**Models:**
- `eleven_multilingual_v2` (10K char limit)
- `eleven_turbo_v2_5` (40K char limit)
- `eleven_flash_v2_5` (40K char limit)

### 8. Tool Execution

Framework for LLM tool use with permissions and rate limiting:

**Available Tools:**
- **text_search** (100/day) - Full-text memory search
- **code_execution** (50/day) - Execute code snippets
- **web_request** (100/day) - HTTP requests to external APIs

**Tool Execution Flow:**
1. LLM returns tool calls in JSON format
2. API parses and validates calls
3. Permission checking (role-based)
4. Rate limit enforcement
5. Tool execution
6. Results formatted for LLM context
7. Daily quotas reset at UTC midnight

### 9. Batch Operations

High-volume operations with consistency:

**Batch Modes:**
- **Sequential** - One operation at a time, stop on error
- **Parallel** - All operations at once
- **Transactional** - All-or-nothing execution

**Constraints:**
- Max 1000 operations per batch
- 50MB data limit
- Results tracked in Firestore for audit trail
- Partial failure handling

### 10. Import/Export System

Data portability and backup:

**Export Formats:**
- **JSON** - Full structured data
- **CSV** - Tabular format for spreadsheets
- **Markdown** - Human-readable format

**Import Strategies:**
- **skip** - Ignore duplicates (default)
- **overwrite** - Replace existing
- **merge** - Combine and reconcile

**Supported Data:**
- Memories with full metadata
- Conversations with complete message history
- Project associations preserved

---

## Authentication & Security

### Authentication Flow

**1. Firebase Authentication**
```
User → Sign In → Firebase Auth → ID Token
```

**2. API Key Validation**
```
Each Request → Query Parameter (?apiKey=ADMIN_KEY) → Server Validation
```

**3. Token Verification**
```
Authorization: Bearer <ID_Token> → Server Verifies → User ID Extracted
```

### Security Practices

- **API Keys:** Never exposed to client, validated server-side
- **Sensitive Data:** Encrypted at rest in Firestore
- **User Scoping:** All queries automatically filtered by user ID
- **CORS:** Restricted to allowed origins (localhost, production domain, Firebase hosting)
- **Storage:** Firebase Storage with signed URLs (7-day expiry)

### Keychain Integration (SwiftUI)

```swift
// Store sensitive data
KeychainManager.save(token, key: "firebase_id_token")
KeychainManager.save(apiKey, key: "admin_api_key")

// Retrieve for requests
let token = KeychainManager.retrieve(key: "firebase_id_token")
let apiKey = KeychainManager.retrieve(key: "admin_api_key")
```

---

## SwiftUI Implementation Architecture

### 1. Project Structure

```
NeurXAxonChat/
├── App/
│   ├── NeurXAxonChatApp.swift
│   └── RootView.swift
├── Models/
│   ├── Memory.swift
│   ├── Conversation.swift
│   ├── Artifact.swift
│   ├── Message.swift
│   ├── Project.swift
│   ├── Settings.swift
│   ├── APIModels.swift
│   └── Enums.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── MemoryViewModel.swift
│   ├── ProjectViewModel.swift
│   ├── SettingsViewModel.swift
│   ├── AnalyticsViewModel.swift
│   └── AudioViewModel.swift
├── Views/
│   ├── Chat/
│   │   ├── ChatView.swift
│   │   ├── ConversationListView.swift
│   │   ├── MessageBubbleView.swift
│   │   ├── InputView.swift
│   │   └── MemoryInjectionView.swift
│   ├── Memory/
│   │   ├── MemoryListView.swift
│   │   ├── MemoryDetailView.swift
│   │   ├── MemorySearchView.swift
│   │   └── MemoryChainView.swift
│   ├── Projects/
│   │   ├── ProjectListView.swift
│   │   ├── ProjectDetailView.swift
│   │   ├── ProjectAnalyticsView.swift
│   │   └── ProjectCreationView.swift
│   ├── Artifacts/
│   │   ├── ArtifactListView.swift
│   │   ├── ArtifactDetailView.swift
│   │   ├── CodeViewerView.swift
│   │   └── ArtifactVersionView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── ThemeSettingsView.swift
│   │   ├── ModelSelectionView.swift
│   │   ├── APIKeyManagementView.swift
│   │   └── TTSSettingsView.swift
│   ├── Analytics/
│   │   ├── AnalyticsDashboardView.swift
│   │   ├── KnowledgeMapView.swift
│   │   ├── TimelineView.swift
│   │   ├── InsightsView.swift
│   │   └── CompletionScoreView.swift
│   └── Shared/
│       ├── LoadingView.swift
│       ├── ErrorView.swift
│       └── EmptyStateView.swift
├── Services/
│   ├── APIClient.swift
│   ├── AuthenticationService.swift
│   ├── MemoryService.swift
│   ├── ConversationService.swift
│   ├── ArtifactService.swift
│   ├── AudioService.swift
│   ├── AnalyticsService.swift
│   └── StorageService.swift
├── Utilities/
│   ├── KeychainManager.swift
│   ├── DateFormatter.swift
│   ├── ColorPalette.swift
│   ├── Constants.swift
│   └── Extensions.swift
└── Resources/
    ├── Localizable.strings
    └── Assets.xcassets
```

### 2. Core MVVM Pattern

**ViewModel Template:**
```swift
@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var selectedConversation: Conversation?
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let apiClient: APIClient
    private let authService: AuthenticationService

    init(apiClient: APIClient, authService: AuthenticationService) {
        self.apiClient = apiClient
        self.authService = authService
    }

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        do {
            conversations = try await apiClient.getConversations(
                limit: 50,
                offset: 0,
                sort: "-updatedAt"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation(title: String, projectId: UUID?) async {
        do {
            let conversation = try await apiClient.createConversation(
                title: title,
                projectId: projectId
            )
            conversations.insert(conversation, at: 0)
            selectedConversation = conversation
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMessage(_ content: String, role: MessageRole) async {
        guard let conversation = selectedConversation else { return }

        do {
            let message = try await apiClient.addMessage(
                to: conversation.id,
                role: role,
                content: content
            )
            messages.append(message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### 3. View Pattern

**View Template:**
```swift
struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss

    init(viewModel: ChatViewModel = .default) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading {
                    LoadingView()
                } else if let errorMessage = viewModel.errorMessage {
                    ErrorView(message: errorMessage) {
                        Task {
                            await viewModel.loadConversations()
                        }
                    }
                } else if viewModel.conversations.isEmpty {
                    EmptyStateView(
                        icon: "bubble.left",
                        title: "No Conversations",
                        description: "Start a new conversation to begin"
                    )
                } else {
                    List {
                        ForEach(viewModel.conversations) { conversation in
                            NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                                ConversationRow(conversation: conversation)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        Task {
                            await viewModel.createConversation(
                                title: "New Conversation",
                                projectId: nil
                            )
                        }
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                await viewModel.loadConversations()
            }
        }
    }
}
```

### 4. API Client Service

**Key Pattern:**
```swift
@MainActor
class APIClient {
    private let session: URLSession
    private let baseURL: URL
    private let authService: AuthenticationService

    private var apiKey: String {
        ProcessInfo.processInfo.environment["ADMIN_API_KEY"] ?? ""
    }

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://us-central1-neurx-axon-chat.cloudfunctions.net")!,
        authService: AuthenticationService
    ) {
        self.session = session
        self.baseURL = baseURL
        self.authService = authService
    }

    // Generic request method
    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(endpoint)

        // Add API key to query params
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "apiKey", value: apiKey))
        if let queryParams = queryParams {
            queryItems.append(contentsOf: queryParams.map {
                URLQueryItem(name: $0.key, value: $0.value)
            })
        }
        components.queryItems = queryItems
        url = components.url!

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Add Firebase ID token
        let idToken = try await authService.getIDToken()
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return try JSONDecoder().decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 500...599:
            throw APIError.serverError
        default:
            throw APIError.unknown
        }
    }

    // Endpoint methods
    func getConversations(
        limit: Int = 50,
        offset: Int = 0,
        sort: String = "-updatedAt"
    ) async throws -> [Conversation] {
        let response: ConversationListResponse = try await request(
            endpoint: "api/conversations",
            queryParams: [
                "limit": String(limit),
                "offset": String(offset),
                "sort": sort
            ]
        )
        return response.data
    }

    func createConversation(
        title: String,
        projectId: UUID?
    ) async throws -> Conversation {
        let body = CreateConversationRequest(title: title, projectId: projectId)
        let response: APIResponse<Conversation> = try await request(
            endpoint: "api/conversations",
            method: "POST",
            body: body
        )
        return response.data
    }

    func addMessage(
        to conversationId: UUID,
        role: MessageRole,
        content: String
    ) async throws -> Message {
        let body = AddMessageRequest(role: role, content: content)
        let response: APIResponse<Message> = try await request(
            endpoint: "api/conversations/\(conversationId)/messages",
            method: "POST",
            body: body
        )
        return response.data
    }

    // ... Additional endpoint methods
}
```

### 5. Authentication Service

**Pattern:**
```swift
@MainActor
class AuthenticationService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?

    private var auth = Auth.auth()

    func signIn(email: String, password: String) async {
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            let idToken = try await result.user.getIDToken()

            // Store token in Keychain
            KeychainManager.save(idToken, key: "firebase_id_token")

            currentUser = User(
                id: result.user.uid,
                email: result.user.email ?? ""
            )
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func getIDToken() async throws -> String {
        if let cached = KeychainManager.retrieve(key: "firebase_id_token") {
            return cached
        }

        guard let user = auth.currentUser else {
            throw AuthError.notAuthenticated
        }

        let idToken = try await user.getIDToken()
        KeychainManager.save(idToken, key: "firebase_id_token")
        return idToken
    }

    func signOut() throws {
        try auth.signOut()
        KeychainManager.delete(key: "firebase_id_token")
        isAuthenticated = false
        currentUser = nil
    }
}
```

---

## Key User Flows

### 1. Chat with Memory Injection

```
User Types Message
    ↓
App Retrieves Relevant Memories (GET /api/memories/retrieve?query=...)
    ↓
Display Injected Memories (optional, collapsible)
    ↓
Send Message + Memory Context to LLM
    ↓
Receive Response
    ↓
Parse Response for:
    - Memories (<memory> tags)
    - Artifacts (<artifact> tags)
    - Tool Calls (optional)
    ↓
Extract & Store:
    - New memories
    - New artifacts
    - Tool execution results
    ↓
Update Conversation History
```

### 2. Memory Management

```
User Browses Memories by:
    - Search (full-text)
    - Tags
    - Confidence level
    - Type (fact/procedure/context)
    - Project
    ↓
View Memory Details:
    - Content
    - Confidence (with visual indicator)
    - Tags
    - Created/Updated dates
    - Related memories (chain)
    - Evolution history (supersession)
    ↓
Actions:
    - Edit confidence
    - Update tags
    - View relationships
    - See which conversations created it
    - Export/backup
```

### 3. Project Organization

```
Create Project (name, description, emoji icon)
    ↓
Assign Conversations to Project
    ↓
View Project Analytics:
    - Conversation count
    - Memory count
    - Artifact count
    - Top tags (learning domains)
    - Confidence distribution
    - Memory evolution
    ↓
Filter All Views by Project:
    - Conversations
    - Memories
    - Artifacts
```

### 4. Audio Generation & Playback

```
User Triggers Audio Generation (button on message)
    ↓
Send Text to TTS (POST /api/audio/generate)
    ↓
Server Chunks Text (respects model limits)
    ↓
Generate Each Chunk with ElevenLabs
    ↓
Upload to Firebase Storage
    ↓
Return Signed URLs (7-day expiry)
    ↓
Download & Cache Locally
    ↓
Play in AVPlayer
    ↓
Allow Speed Control, Repeat, Skip
```

### 5. Analytics Dashboard

```
View Knowledge Map:
    - Nodes: memories, tags, projects
    - Edges: relationships
    - Color/size: confidence, frequency
    ↓
View Timeline:
    - Memory creation events
    - Confidence progression
    - Update history
    ↓
Read Insights:
    - Learning velocity (memories/day)
    - Knowledge specialization (top tags)
    - Confidence trends
    - Next learning areas
    ↓
Completeness Score:
    - Visual gauge (0-1)
    - Breakdown by factor
    - Recommendations
```

---

## Data Synchronization Strategy

### Real-time Sync Pattern

**For List Views (Conversations, Memories, etc):**
```swift
// Load initial data
await viewModel.loadConversations()

// Refresh on foreground
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    Task {
        await viewModel.loadConversations()
    }
}

// Pull-to-refresh
.refreshable {
    await viewModel.loadConversations()
}

// Periodic background sync
.task {
    for await _ in Timer.publish(every: 30, on: .main, in: .common).autoconnect() {
        await viewModel.loadConversations()
    }
}
```

**For Detail Views:**
```swift
// Load specific item
await viewModel.loadConversation(id: conversationId)

// Re-load when returning to view
.onAppear {
    Task {
        await viewModel.refreshCurrentConversation()
    }
}

// Stream new messages (polling for now, WebSocket future)
.task {
    for await _ in Timer.publish(every: 5, on: .main, in: .common).autoconnect() {
        await viewModel.checkForNewMessages()
    }
}
```

### Local Caching Pattern

```swift
@MainActor
class StorageService {
    private let fileManager = FileManager.default
    private lazy var cacheURL = fileManager.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    )[0].appendingPathComponent("NeurXAxonChat")

    func cacheConversations(_ conversations: [Conversation]) throws {
        let data = try JSONEncoder().encode(conversations)
        let url = cacheURL.appendingPathComponent("conversations.json")
        try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        try data.write(to: url)
    }

    func getCachedConversations() -> [Conversation]? {
        let url = cacheURL.appendingPathComponent("conversations.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Conversation].self, from: data)
    }

    func cacheAudioURL(_ url: URL, for messageId: UUID) throws {
        let audioData = try Data(contentsOf: url)
        let fileName = "\(messageId).mp3"
        let cacheFile = cacheURL.appendingPathComponent(fileName)
        try audioData.write(to: cacheFile)
    }

    func getCachedAudioURL(for messageId: UUID) -> URL? {
        let fileName = "\(messageId).mp3"
        let cacheFile = cacheURL.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: cacheFile.path) ? cacheFile : nil
    }
}
```

---

## UI/UX Patterns & Conventions

### Color & Theme System

```swift
enum Theme {
    case light
    case dark
    case system
}

struct ColorPalette {
    // Semantic colors
    let primary: Color      // Brand color (blue)
    let secondary: Color    // Secondary (purple)
    let accent: Color       // Accent (orange)
    let background: Color
    let secondaryBackground: Color
    let tertiary: Color     // Tertiary background
    let text: Color
    let secondaryText: Color

    // Semantic colors for confidence
    let confidenceHigh: Color      // Green (0.7-1.0)
    let confidenceMedium: Color    // Yellow (0.4-0.7)
    let confidenceLow: Color       // Red (0.0-0.4)

    // Status colors
    let success: Color
    let warning: Color
    let error: Color
}
```

### Confidence Visualization

```swift
struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "chart.bar.fill")
                .foregroundColor(confidenceColor)

            Text(confidenceLabel)
                .font(.caption)
                .foregroundColor(confidenceColor)

            ProgressView(value: confidence)
                .tint(confidenceColor)
                .frame(height: 4)
        }
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.7...1.0:
            return .green    // Established
        case 0.4..<0.7:
            return .yellow   // Uncertain
        default:
            return .red      // Hypothesis
        }
    }

    private var confidenceLabel: String {
        switch confidence {
        case 0.7...1.0:
            return "Established"
        case 0.4..<0.7:
            return "Uncertain"
        default:
            return "Hypothesis"
        }
    }
}
```

### Loading State Handling

```swift
enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case error(Error)
}

struct ContentView<Content: View>: View {
    let state: LoadingState<Conversation>
    let content: (Conversation) -> Content

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            LoadingView()
        case .loaded(let conversation):
            content(conversation)
        case .error(let error):
            ErrorView(message: error.localizedDescription)
        }
    }
}
```

### Empty State Pattern

```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding(24)
    }
}
```

---

## Performance Considerations

### Memory Management

**Large Lists:**
```swift
// Use .id(_:) to ensure list identity
List {
    ForEach(conversations, id: \.id) { conversation in
        ConversationRow(conversation: conversation)
    }
}

// Paginate large datasets
var paginatedConversations: [Conversation] {
    Array(conversations.prefix(50)) // Load 50 at a time
}

func loadMore() {
    offset += 50
    Task { await viewModel.loadConversations() }
}
```

**Image Caching:**
```swift
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSData>()

    func loadImage(url: URL) async -> Image? {
        let key = url.lastPathComponent as NSString

        if let cached = cache.object(forKey: key) {
            return Image(uiImage: UIImage(data: cached as Data)!)
        }

        let data = try? Data(contentsOf: url)
        if let data = data {
            cache.setObject(data as NSData, forKey: key)
            return Image(uiImage: UIImage(data: data)!)
        }

        return nil
    }
}
```

### Network Optimization

**Request Batching:**
```swift
// Load conversation + messages + memories in parallel
async let conversations = apiClient.getConversations()
async let memories = apiClient.getMemories(limit: 10)
async let projects = apiClient.getProjects()

let (convs, mems, projs) = try await (conversations, memories, projects)
```

**Pagination Strategy:**
```swift
@MainActor
class ConversationViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    private var offset = 0
    private let pageSize = 50
    private var hasMoreToLoad = true

    func loadMore() async {
        guard hasMoreToLoad else { return }

        do {
            let newConversations = try await apiClient.getConversations(
                limit: pageSize,
                offset: offset
            )

            conversations.append(contentsOf: newConversations)
            offset += pageSize
            hasMoreToLoad = newConversations.count == pageSize
        } catch {
            // Handle error
        }
    }
}
```

---

## Testing Strategy

### Unit Tests for ViewModels

```swift
@MainActor
class ChatViewModelTests: XCTestCase {
    var viewModel: ChatViewModel!
    var mockAPIClient: MockAPIClient!

    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        viewModel = ChatViewModel(apiClient: mockAPIClient)
    }

    func testLoadConversations() async {
        // Arrange
        let expected = [Conversation.mock(), Conversation.mock()]
        mockAPIClient.getConversationsResult = expected

        // Act
        await viewModel.loadConversations()

        // Assert
        XCTAssertEqual(viewModel.conversations, expected)
        XCTAssertFalse(viewModel.isLoading)
    }
}
```

### Integration Tests for API Client

```swift
class APIClientTests: XCTestCase {
    var sut: APIClient!
    var urlSession: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: config)
        sut = APIClient(session: urlSession)
    }

    func testGetConversations() async throws {
        // Setup mock response
        MockURLProtocol.mockResponse = (
            response: HTTPURLResponse(url: URL(string: "https://api.test")!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
            data: try JSONEncoder().encode([Conversation.mock()])
        )

        // Test
        let conversations = try await sut.getConversations()

        XCTAssertEqual(conversations.count, 1)
    }
}
```

---

## Development Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Project setup with Firebase integration
- [ ] Authentication (sign in/sign up)
- [ ] Basic chat view with message display
- [ ] API client setup

### Phase 2: Core Features (Week 2-3)
- [ ] Conversation list and detail views
- [ ] Memory extraction and display
- [ ] Artifact detection and viewing
- [ ] Settings synchronization

### Phase 3: Project Organization (Week 3-4)
- [ ] Project CRUD
- [ ] Project filtering and stats
- [ ] Memory organization by project
- [ ] Project analytics dashboard

### Phase 4: Advanced Features (Week 4-5)
- [ ] Audio generation and playback
- [ ] Memory relationship visualization
- [ ] Analytics dashboard (timeline, insights)
- [ ] Knowledge map visualization

### Phase 5: Polish & Optimization (Week 5-6)
- [ ] Performance optimization
- [ ] Offline support
- [ ] App icon and branding
- [ ] Accessibility improvements
- [ ] App Store preparation

---

## Common Pitfalls to Avoid

1. **Token Refresh:** Always refresh ID token before making requests
   ```swift
   let idToken = try await authService.getIDToken() // Handles refresh
   ```

2. **Memory Leaks:** Use `[weak self]` in async closures
   ```swift
   Task { [weak self] in
       await self?.loadData()
   }
   ```

3. **UI on Main Thread:** Use `@MainActor` on ViewModels
   ```swift
   @MainActor
   class MyViewModel: ObservableObject { }
   ```

4. **Pagination:** Always check `hasMore` before loading more
   ```swift
   if pagination.hasMore {
       await loadMore()
   }
   ```

5. **Error Handling:** Show user-friendly error messages, log detailed errors
   ```swift
   catch {
       errorMessage = "Failed to load conversations"
       logger.error("\(error)")
   }
   ```

---

## Questions for Implementation?

- **API Documentation:** See `API_DOCUMENTATION.md`
- **Roadmap:** See `API_ABSTRACTION_ROADMAP.md`
- **Backend Implementation:** TypeScript/Firebase Cloud Functions in `functions/src/`
- **UI/UX Specifications:** Design patterns documented above

---

**Project Status:** Backend API complete and production-ready (49 endpoints, 7 phases)
**Next Step:** SwiftUI implementation using architecture and patterns documented above

**Last Updated:** October 28, 2025
