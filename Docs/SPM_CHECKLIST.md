# Swift Package Manager Setup Checklist

## ✅ Completed

- [x] Removed CocoaPods files (Pods/, Podfile, workspace)
- [x] Cleaned derived data cache
- [x] Opened Axon.xcodeproj

## 📦 Firebase Package Setup (Do This Now)

### In Xcode:

1. **Add Package Dependencies**
   - [ ] Go to **File** → **Add Package Dependencies...**
   - [ ] Paste URL: `https://github.com/firebase/firebase-ios-sdk`
   - [ ] Click **Add Package**

2. **Select These Products** (check all):
   - [ ] FirebaseAnalytics
   - [ ] FirebaseAuth
   - [ ] FirebaseFirestore
   - [ ] FirebaseFunctions
   - [ ] FirebaseStorage
   - [ ] FirebaseMessaging
   - [ ] FirebaseCrashlytics
   - [ ] FirebasePerformance

3. **Verify Target**
   - [ ] Make sure "Axon" target is selected
   - [ ] Click **Add Package**

4. **Wait for Download**
   - [ ] Wait for Xcode to download packages (1-2 minutes)
   - [ ] Check Project Navigator for "Dependencies" folder

## 📁 Add Source Files (After Firebase is added)

1. **Add Swift Files**
   - [ ] Right-click "Axon" group in Project Navigator
   - [ ] Select "Add Files to 'Axon'..."
   - [ ] Add these folders:
     - [ ] Config/
     - [ ] Services/ (with subfolders)
     - [ ] Models/
     - [ ] Views/ (with subfolders)
     - [ ] Utils/
     - [ ] DesignSystem/ (with subfolders)
   - [ ] **Uncheck** "Copy items if needed"
   - [ ] **Check** target "Axon"
   - [ ] Click "Add"

## 🔥 Firebase Configuration

1. **Get GoogleService-Info.plist**
   - [ ] Go to [Firebase Console](https://console.firebase.google.com/)
   - [ ] Select project: **neurx-8f122**
   - [ ] Project Settings → Your Apps
   - [ ] Download `GoogleService-Info.plist`

2. **Add to Xcode**
   - [ ] Drag `GoogleService-Info.plist` into Xcode (project root)
   - [ ] **Check** "Copy items if needed"
   - [ ] **Check** target "Axon"
   - [ ] Click "Finish"

## 🏗️ Build and Run

1. **Clean Build**
   - [ ] Press **Shift+Cmd+K** (Product → Clean Build Folder)

2. **Build Project**
   - [ ] Press **Cmd+B**
   - [ ] Verify no errors

3. **Run App**
   - [ ] Select a simulator (iPhone 15 Pro recommended)
   - [ ] Press **Cmd+R**
   - [ ] App should launch with auth screen! 🎉

## 🎯 Expected Results

After completing all steps, you should see:

1. ✅ No "Unable to find module" errors
2. ✅ Firebase packages in Dependencies section
3. ✅ All Swift files visible in Project Navigator
4. ✅ App builds successfully
5. ✅ Authentication screen appears on launch

## 📊 Your Project Structure

```
Axon.xcodeproj/          ← Your project file
├── Axon/
│   ├── Config/          ← Firebase configuration
│   ├── Services/        ← Auth, API, Conversation, Memory
│   ├── Models/          ← Data models
│   ├── Views/           ← UI screens
│   │   ├── Auth/
│   │   ├── Chat/
│   │   ├── Memory/
│   │   ├── Settings/
│   │   └── Components/
│   ├── Utils/           ← Helpers
│   ├── DesignSystem/    ← Colors, Typography, Components
│   ├── AxonApp.swift
│   └── GoogleService-Info.plist  ← Add this!
└── Dependencies/        ← SPM packages (auto-managed)
    └── firebase-ios-sdk
```

## 🚨 Common Issues

### "Cannot find FirebaseAuth in scope"
→ Make sure you added the Firebase packages (Step 1 above)

### "No such module 'FirebaseCore'"
→ Clean build folder (Shift+Cmd+K) and rebuild

### Swift files not showing up
→ Make sure you added them to the project (Step 2 above)

### App crashes on launch
→ Make sure GoogleService-Info.plist is added (Step 3 above)

## 🎉 Success!

When everything works:
- ✅ No workspace file needed
- ✅ Just use Axon.xcodeproj
- ✅ Faster builds
- ✅ Simpler workflow
- ✅ Modern dependency management

---

**Current Status**: CocoaPods removed ✅, ready for SPM setup!

**Next Action**: Add Firebase packages in Xcode (see steps above)
