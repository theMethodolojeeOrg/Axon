# Fix Build Issues Guide

## The Main Issue

You're seeing "Unable to find module dependency" errors because:
1. You might be opening `Axon.xcodeproj` instead of `Axon.xcworkspace`
2. The workspace needs to be properly opened to link the Firebase pods

## ✅ Solution

### Step 1: Close Xcode Completely
Close all Xcode windows.

### Step 2: Open the WORKSPACE File
**This is critical!** You MUST open the `.xcworkspace` file, NOT the `.xcodeproj` file.

```bash
cd /Users/tom/Documents/XCode_Projects/Axon
open Axon.xcworkspace
```

Or from Finder:
- Navigate to `/Users/tom/Documents/XCode_Projects/Axon`
- Double-click `Axon.xcworkspace` (the white icon with multiple squares)
- DO NOT open `Axon.xcodeproj`

### Step 3: Clean Build Folder
Once the workspace is open:
1. In Xcode menu: **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. Wait for it to complete

### Step 4: Build Again
Press Cmd+B to build. The Firebase modules should now be found!

## If You Still See Errors

### Check 1: Verify You're Using Workspace
Look at the Xcode window title - it should say "Axon.xcworkspace" not "Axon.xcodeproj"

### Check 2: Verify Pods Are Linked
1. In Xcode Project Navigator (left sidebar)
2. You should see a "Pods" folder/group at the bottom
3. If you don't see it, you're not using the workspace

### Check 3: Re-run Pod Install
If needed, run this in Terminal:

```bash
cd /Users/tom/Documents/XCode_Projects/Axon
pod install
open Axon.xcworkspace
```

## Common Mistakes ❌

1. ❌ Opening `Axon.xcodeproj` - This won't work!
2. ❌ Having both .xcodeproj and .xcworkspace open
3. ❌ Not cleaning build folder after switching to workspace

## The Right Way ✅

1. ✅ Always open `Axon.xcworkspace`
2. ✅ Verify "Pods" folder is visible in Project Navigator
3. ✅ Clean and rebuild after opening workspace

## What I Fixed

I've already updated these files to use the correct Firebase imports:
- ✅ `AxonApp.swift` - Changed to FirebaseCore, FirebaseAuth, FirebaseFirestore
- ✅ `AuthenticationService.swift` - Changed to FirebaseCore, FirebaseAuth
- ✅ `APIClient.swift` - Changed to FirebaseCore, FirebaseAuth
- ✅ `FirebaseConfig.swift` - Changed to FirebaseCore, FirebaseFirestore, FirebaseFunctions

## Quick Test

After opening the workspace and building:
1. You should see **36 pods** in the Pods folder
2. Build should succeed (Cmd+B)
3. You might still need to add the Swift files we created earlier
4. You'll need GoogleService-Info.plist to run the app

## Next: Add Your Swift Files

Once the build errors are resolved, you need to add the Swift files:
1. Right-click "Axon" group in Project Navigator
2. "Add Files to 'Axon'..."
3. Select these folders: Config, Services, Models, Views, Utils, DesignSystem
4. Uncheck "Copy items if needed"
5. Check target "Axon"
6. Click Add

---

**Remember**: Always use `.xcworkspace` when working with CocoaPods! 🔥
