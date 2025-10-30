# Axon iOS Setup Guide

This guide will help you complete the setup of your native SwiftUI application for NeurXAxonChat.

## What's Been Built

I've created a complete foundation for your iOS app with:

### ✅ Design System
- **Colors** ([AppColors.swift](Axon/DesignSystem/Colors/AppColors.swift)) - Mineral-inspired dark theme
- **Typography** ([AppTypography.swift](Axon/DesignSystem/Typography/AppTypography.swift)) - IBM Plex Sans-inspired fonts
- **Components** - Glass morphism cards and animations

### ✅ Services Layer
- **Authentication** ([AuthenticationService.swift](Axon/Services/Auth/AuthenticationService.swift)) - Firebase Auth integration
- **API Client** ([APIClient.swift](Axon/Services/API/APIClient.swift)) - REST API with auto token refresh
- **Conversation Service** ([ConversationService.swift](Axon/Services/Conversation/ConversationService.swift)) - Chat management
- **Memory Service** ([MemoryService.swift](Axon/Services/Memory/MemoryService.swift)) - Intelligent memory system

### ✅ Views
- **Authentication** ([AuthenticationView.swift](Axon/Views/Auth/AuthenticationView.swift)) - Sign in/up
- **Chat** ([ChatView.swift](Axon/Views/Chat/ChatView.swift), [ConversationListView.swift](Axon/Views/Chat/ConversationListView.swift)) - Full chat interface
- **Memory** ([MemoryListView.swift](Axon/Views/Memory/MemoryListView.swift)) - Memory browser with filtering
- **Settings** ([SettingsView.swift](Axon/Views/Settings/SettingsView.swift)) - User preferences

### ✅ Models
- Message, Conversation, Memory, and supporting types with Codable support

### ✅ Configuration
- Firebase configuration ([FirebaseConfig.swift](Axon/Config/FirebaseConfig.swift))
- Secure token storage ([SecureTokenStorage.swift](Axon/Utils/SecureTokenStorage.swift))
- Environment-aware setup (dev/staging/prod)

## Next Steps

### 1. Add Files to Xcode Project

**All the Swift files have been created in the file system, but Xcode doesn't know about them yet.**

To add them to your Xcode project:

1. Open Xcode
2. Right-click on the "Axon" group in the Project Navigator
3. Select "Add Files to 'Axon'..."
4. Navigate to the following folders and add them:
   - `Axon/Config`
   - `Axon/Services` (with all subfolders)
   - `Axon/Models`
   - `Axon/Views` (with all subfolders)
   - `Axon/Utils`
   - `Axon/DesignSystem` (with all subfolders)
5. Make sure "Copy items if needed" is **unchecked** (files are already in place)
6. Make sure "Create groups" is selected
7. Make sure the target "Axon" is checked
8. Click "Add"

### 2. Configure Firebase

#### Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **neurx-8f122**
3. Click the gear icon → Project Settings
4. In the "Your apps" section, find your iOS app (or create one if it doesn't exist)
5. Download `GoogleService-Info.plist`
6. Drag the file into your Xcode project root
7. Make sure "Copy items if needed" is checked
8. Make sure target "Axon" is selected

#### Update Info.plist (if needed)

Your Info.plist may need these Firebase keys. Check if they're already present:

```xml
<key>FirebaseAppID</key>
<string>YOUR_APP_ID_FROM_GOOGLE_SERVICE_FILE</string>

<key>FirebaseAPIKey</key>
<string>YOUR_API_KEY_FROM_GOOGLE_SERVICE_FILE</string>
```

### 3. Verify Pod Installation

Make sure all Firebase pods are installed:

```bash
cd /Users/tom/Documents/XCode_Projects/Axon
pod install
```

Then **open the .xcworkspace file** (not .xcodeproj):

```bash
open Axon.xcworkspace
```

### 4. Build and Test

1. Select a simulator or device
2. Press Cmd+B to build
3. Fix any compilation errors (there may be a few import issues)
4. Press Cmd+R to run

### 5. API Configuration

To connect to your backend API:

1. Update the API URLs in [FirebaseConfig.swift](Axon/Config/FirebaseConfig.swift):
   - Development: `http://localhost:5001/neurx-8f122/us-central1` (current)
   - Production: `https://api.neurx.org` (update this URL)

2. Set your API key (if required by your backend):
   - Option A: Environment variable `ADMIN_API_KEY` in Xcode build settings
   - Option B: Store in Keychain at runtime via settings

## Architecture Overview

```
Axon/
├── Config/                  # Firebase and app configuration
├── Services/
│   ├── Auth/               # Authentication service
│   ├── API/                # Network layer
│   ├── Conversation/       # Chat management
│   └── Memory/             # Memory system
├── Models/                 # Data models (Codable)
├── Views/
│   ├── Auth/               # Login/signup
│   ├── Chat/               # Chat interface
│   ├── Memory/             # Memory browser
│   ├── Settings/           # User settings
│   └── Components/         # Shared components
├── DesignSystem/
│   ├── Colors/             # App colors
│   ├── Typography/         # Text styles
│   └── Components/         # Reusable UI components
└── Utils/                  # Utilities (Keychain, etc.)
```

## Key Features Implemented

### Authentication
- Email/password sign in and sign up
- Automatic token management
- Secure keychain storage
- Auto-logout on token expiration

### Chat
- Create and manage conversations
- Real-time messaging
- Message history
- Auto-scroll to latest message

### Memory System
- Browse all memories
- Filter by type (fact, procedure, context, relationship)
- Search functionality
- Confidence scoring
- Manual memory creation

### Design
- Dark theme with mineral-inspired colors
- Glass morphism UI
- Smooth animations (200ms standard)
- Responsive layouts

## Troubleshooting

### Common Issues

**"No such module 'Firebase'"**
- Make sure you're opening `.xcworkspace`, not `.xcodeproj`
- Run `pod install` again

**"GoogleService-Info.plist not found"**
- Download from Firebase Console
- Make sure it's added to the Axon target

**Build errors about missing files**
- Add all the Swift files to the Xcode project (see Step 1)

**API requests failing**
- Check Firebase configuration
- Verify API URLs in FirebaseConfig.swift
- Make sure your backend is running

## Testing the App

### With Local Backend (Development)

1. Start your Firebase emulators:
   ```bash
   firebase emulators:start
   ```

2. The app will automatically connect to emulators in DEBUG mode

### With Production Backend

1. Change the build configuration to Release
2. Update API URLs in FirebaseConfig.swift
3. Build and run

## Next Features to Add

Some suggested enhancements:

1. **Streaming Responses** - Real-time message streaming from AI
2. **Artifacts System** - View and manage code/text artifacts
3. **Projects** - Organize conversations into projects
4. **Audio** - Voice input/output with ElevenLabs
5. **Analytics** - Memory graphs and insights
6. **Offline Mode** - Queue messages when offline
7. **Push Notifications** - For new memories or insights

## Resources

- [Firebase iOS Documentation](https://firebase.google.com/docs/ios/setup)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)
- [API Documentation](Docs/API_DOCUMENTATION.md)
- [Visual Design Guide](Docs/VISUAL_DESIGN_GUIDE.md)

---

**Need Help?**

If you encounter any issues:
1. Check the console logs (Cmd+Shift+Y in Xcode)
2. Review Firebase Console for authentication issues
3. Verify API endpoints are responding
4. Check that all files are added to the Xcode target

Good luck with your iOS app! 🚀
