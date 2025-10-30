# Axon iOS Setup Checklist

Use this checklist to complete the setup:

## ☐ Step 1: Add Files to Xcode

- [ ] Open Xcode project
- [ ] Right-click "Axon" group → "Add Files to 'Axon'..."
- [ ] Add the following folders (make sure "Create groups" is selected):
  - [ ] `Config/`
  - [ ] `Services/` (with all subfolders)
  - [ ] `Models/`
  - [ ] `Views/` (with all subfolders)
  - [ ] `Utils/`
  - [ ] `DesignSystem/` (with all subfolders)
- [ ] Verify target "Axon" is checked for all files
- [ ] Uncheck "Copy items if needed"

## ☐ Step 2: Firebase Configuration

- [ ] Go to [Firebase Console](https://console.firebase.google.com/)
- [ ] Select project **neurx-8f122**
- [ ] Download `GoogleService-Info.plist`
- [ ] Drag file into Xcode project root
- [ ] Check "Copy items if needed"
- [ ] Verify it's added to "Axon" target

## ☐ Step 3: Verify Dependencies

- [ ] Run `pod install` in terminal
- [ ] Close Xcode
- [ ] Open `Axon.xcworkspace` (NOT .xcodeproj)
- [ ] Verify Firebase pods are present in "Pods" section

## ☐ Step 4: Build and Test

- [ ] Select a simulator (iPhone 15 Pro recommended)
- [ ] Press Cmd+B to build
- [ ] Fix any compilation errors
- [ ] Press Cmd+R to run
- [ ] Test authentication (sign up)
- [ ] Test creating a conversation
- [ ] Test sending a message
- [ ] Test memory view

## ☐ Step 5: API Configuration

- [ ] Update API URLs in `Config/FirebaseConfig.swift` if needed
- [ ] Configure API key (if required by backend)
- [ ] Test API connectivity

## Files Created (27 total)

### Configuration (2)
- ✅ `Config/FirebaseConfig.swift`
- ✅ `Utils/SecureTokenStorage.swift`

### Services (5)
- ✅ `Services/Auth/AuthenticationService.swift`
- ✅ `Services/API/APIClient.swift`
- ✅ `Services/Conversation/ConversationService.swift`
- ✅ `Services/Memory/MemoryService.swift`
- ✅ `Utils/ErrorHandler.swift`

### Models (4)
- ✅ `Models/Message.swift`
- ✅ `Models/Conversation.swift`
- ✅ `Models/Memory.swift`
- ✅ `Models/AnyCodable.swift`

### Design System (6)
- ✅ `DesignSystem/Colors/AppColors.swift`
- ✅ `DesignSystem/Typography/AppTypography.swift`
- ✅ `DesignSystem/Components/AppAnimations.swift`
- ✅ `DesignSystem/Components/GlassCard.swift`

### Views (7)
- ✅ `Views/Auth/AuthenticationView.swift`
- ✅ `Views/Chat/ChatView.swift`
- ✅ `Views/Chat/ConversationListView.swift`
- ✅ `Views/Memory/MemoryListView.swift`
- ✅ `Views/Settings/SettingsView.swift`
- ✅ `Views/Components/MainTabView.swift`

### Updated Files (1)
- ✅ `AxonApp.swift` - Modified to integrate Firebase and authentication

### Documentation (2)
- ✅ `SETUP_GUIDE.md`
- ✅ `CHECKLIST.md` (this file)

## Common Issues

**Build Error: "No such module 'Firebase'"**
→ Make sure you're opening `.xcworkspace`, not `.xcodeproj`

**Runtime Error: "GoogleService-Info.plist not found"**
→ Download from Firebase Console and add to project

**API requests failing**
→ Check Firebase configuration and backend API URLs

**UI not showing design system colors**
→ Verify all DesignSystem files are added to target

## Testing Authentication

1. Launch app
2. Should show authentication screen
3. Click "Sign Up" tab
4. Enter:
   - Display Name: Test User
   - Email: test@example.com
   - Password: password123
5. Click "Create Account"
6. Should navigate to main app with 3 tabs

## Testing Chat

1. Navigate to "Chat" tab
2. Tap "+" to create conversation
3. Enter title: "Test Chat"
4. Type a message and send
5. Should see message in chat view

## Testing Memory

1. Navigate to "Memory" tab
2. Tap "+" to create memory
3. Fill in details and create
4. Should see memory in list
5. Test filter chips
6. Test search

## Next Steps After Setup

- [ ] Connect to production API
- [ ] Test with real backend data
- [ ] Customize UI colors/fonts if needed
- [ ] Add streaming support for messages
- [ ] Implement push notifications
- [ ] Add offline support
- [ ] Integrate artifacts system
- [ ] Add voice input/output

---

**Status**: Initial setup complete, ready for Xcode integration
**Last Updated**: October 29, 2025
