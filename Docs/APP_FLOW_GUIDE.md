# NeurX AxonChat - App Flow Guide

## 🎯 Design Goal

Create a ChatGPT/Claude-style experience where:
- Chat is **always** the primary focus
- Conversations are managed via **slide-out sidebar**
- Users can **quickly start new chats** without leaving the main view
- Navigation is **intuitive** and follows industry standards

## 📱 User Journey

### First Launch

```
1. App Opens
   ↓
2. User sees Authentication Screen
   - Sign in or Sign up
   ↓
3. User authenticates
   ↓
4. Welcome Screen appears
   - Logo and branding
   - Suggested prompt cards
   - Input bar ready to type
```

### Starting First Conversation

```
1. Welcome Screen displayed
   ↓
2. User either:
   - Taps a suggested prompt card, OR
   - Types directly in input bar
   ↓
3. Message sent
   ↓
4. New conversation auto-created
   - First message becomes title
   ↓
5. Chat interface loads
   - User message appears
   - AI response streams in
   - Conversation continues
```

### Navigating Between Conversations

```
1. User in active chat
   ↓
2. User taps hamburger icon (☰)
   ↓
3. Sidebar slides in from left
   - Shows conversation list
   - Shows current selection
   ↓
4. User taps different conversation
   ↓
5. Sidebar closes
   ↓
6. New conversation loads
   - Messages appear
   - Ready to continue chatting
```

### Starting New Chat

```
1. User in any view
   ↓
2. User taps:
   - New Chat button in sidebar, OR
   - Pencil icon (✎) in toolbar
   ↓
3. Current chat clears
   ↓
4. Welcome screen appears
   ↓
5. Ready for new conversation
```

## 🗂️ Screen Hierarchy

```
AxonApp
├── AuthenticationView (if not logged in)
│   ├── Sign In form
│   └── Sign Up form
│
└── AppContainerView (if logged in)
    ├── ChatContainerView (main view, always visible)
    │   ├── WelcomeView (for new chats)
    │   │   ├── Logo
    │   │   ├── Suggested Prompts
    │   │   └── Input Bar
    │   │
    │   └── ExistingChatView (for active chats)
    │       ├── Message List
    │       └── Input Bar
    │
    └── SidebarView (overlay, slides in)
        ├── Header
        │   ├── App title
        │   └── New Chat button
        │
        ├── Section Tabs
        │   ├── Chats
        │   ├── Memory
        │   └── Settings
        │
        ├── Content Area
        │   ├── Conversations List (if Chats selected)
        │   ├── Memory View (if Memory selected)
        │   └── Settings View (if Settings selected)
        │
        └── Footer
            ├── User profile
            └── Menu (sign out)
```

## 🎨 UI Components

### 1. Welcome Screen
**Purpose**: Engage users starting a new chat

**Elements**:
- Large logo icon (brain.head.profile)
- App name and tagline
- 4 suggested prompt cards:
  - Explain a concept
  - Write code
  - Remember something
  - Create a plan
- Always-visible input bar

**Interaction**:
- Tap prompt card → Auto-fills input and sends
- Type in input bar → Normal message flow

### 2. Chat View
**Purpose**: Main conversation interface

**Elements**:
- Navigation bar:
  - Left: Hamburger menu (☰)
  - Center: Conversation title
  - Right: New chat icon (✎)
- Message list:
  - User messages (right, green-tinted)
  - AI messages (left, mercury-tinted)
  - Auto-scroll to latest
- Input bar:
  - Text field (multi-line, max 5 lines)
  - Send button (disabled if empty)
  - Loading indicator when sending

**Interaction**:
- Type message → Send button activates
- Tap send → Message appears, AI responds
- Scroll messages → View history
- Tap hamburger → Open sidebar

### 3. Sidebar
**Purpose**: Navigate between chats, access features

**Elements**:
- Header:
  - App name
  - User name
  - Close button (×)
  - New Chat button (prominent)
- Section tabs:
  - Chats (default)
  - Memory
  - Settings
- Conversation list:
  - Title
  - Last message preview
  - Relative time
  - Selection indicator
- Footer:
  - User avatar
  - Email
  - Menu (ellipsis)

**Interaction**:
- Tap conversation → Switch to that chat
- Tap New Chat → Clear and start fresh
- Tap Memory → View memories
- Tap Settings → App preferences
- Tap outside → Close sidebar
- Tap × → Close sidebar

## 🔄 State Management

### App State
```swift
@StateObject authService    // Authentication status
@State showSidebar          // Sidebar visibility
@State selectedConversation // Current conversation
@State showNewChat          // New chat mode
```

### Conversation State
```swift
@Published conversations     // List of all chats
@Published currentConversation // Active conversation
@Published messages          // Current chat messages
@Published isLoading         // API call status
```

### Memory State
```swift
@Published memories          // All memories
@Published isLoading         // Loading status
@Published error             // Error state
```

## 🎯 Key Interactions

### Message Flow
```
1. User types in input bar
2. User taps send button
3. Message text captured
4. Input cleared immediately
5. Loading indicator shows
6. If no conversation:
   - Create new conversation
   - Use message as title (truncated)
7. Send message to API
8. User message appears in chat
9. AI response streams in
10. Loading indicator hides
```

### Sidebar Toggle
```
1. User taps hamburger icon
2. State updated: showSidebar = true
3. Animation starts (200ms)
4. Overlay fades in (black 30%)
5. Sidebar slides from left
6. Conversation list visible
7. User can interact with sidebar
8. Tap outside or × → Reverse animation
```

### Conversation Switch
```
1. Sidebar open
2. User taps conversation row
3. State updated: selectedConversation = tapped item
4. Sidebar closes (animated)
5. Messages cleared
6. Loading indicator shows
7. API call: fetch messages
8. Messages populate
9. Auto-scroll to bottom
10. Ready for input
```

## 📐 Layout Specifications

### Dimensions
- **Sidebar width**: 80% of screen width
- **Input bar height**: Auto (1-5 lines)
- **Navigation bar**: Standard iOS height
- **Prompt cards**: Full width - 32pt padding
- **Message bubbles**: Max 80% screen width

### Spacing
- **Section padding**: 16pt
- **Card spacing**: 12pt
- **Message spacing**: 16pt
- **Input padding**: 12pt

### Colors
- **Background**: #161a1b (substrate primary)
- **Sidebar**: #1e2324 (substrate secondary)
- **User messages**: #5f7f5f + 20% opacity (lichen)
- **AI messages**: #1e2324 (substrate secondary)
- **Accent**: #3f6f7a (mercury)

## 🚀 Performance Optimizations

1. **Lazy loading**: Conversations and messages load on demand
2. **Virtual scrolling**: Messages use LazyVStack
3. **Image caching**: Profile images cached
4. **State management**: Shared singletons for services
5. **Smooth animations**: 200ms standard timing

## ✨ Polish Details

1. **Auto-scroll**: Messages auto-scroll to latest
2. **Keyboard handling**: Input stays above keyboard
3. **Loading states**: Clear indicators during API calls
4. **Error handling**: Graceful error messages
5. **Empty states**: Helpful messages when no content
6. **Pull to refresh**: Update conversations and messages
7. **Haptic feedback**: On key interactions (optional)

---

**Result**: A polished, professional AI chat app that feels familiar and intuitive! 🎉
