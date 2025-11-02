# Add Firebase via Swift Package Manager

## ✅ CocoaPods Removed

I've successfully removed:
- ❌ Pods/ folder
- ❌ Podfile
- ❌ Podfile.lock
- ❌ Axon.xcworkspace
- ❌ Derived data cache

Now you can use the regular **Axon.xcodeproj** file! 🎉

## 📦 Add Firebase Packages

Follow these steps to add Firebase via Swift Package Manager:

### Step 1: Open Project
```bash
open Axon.xcodeproj
```

Or just double-click `Axon.xcodeproj` in Finder.

### Step 2: Add Package Dependencies

1. In Xcode, go to **File** menu → **Add Package Dependencies...**
   (Or right-click project in Navigator → **Add Package Dependencies...**)

2. In the search field at the top, paste:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```

3. Xcode will fetch the package info. When it appears, you'll see options:
   - **Dependency Rule**: Select "Up to Next Major Version"
   - **Version**: Should show **12.5.0** (or latest)

4. Click **Add Package**

### Step 3: Select Products

Xcode will show a list of Firebase products. Select these:

**Core (Required):**
- ✅ **FirebaseAnalytics** - Analytics and core functionality
- ✅ **FirebaseAuth** - Authentication
- ✅ **FirebaseFirestore** - Cloud Firestore database
- ✅ **FirebaseFunctions** - Cloud Functions
- ✅ **FirebaseStorage** - Cloud Storage

**Optional (Recommended):**
- ✅ **FirebaseMessaging** - Push notifications
- ✅ **FirebaseCrashlytics** - Crash reporting
- ✅ **FirebasePerformance** - Performance monitoring

Make sure they're all being added to the **Axon** target (should be selected by default).

### Step 4: Click Add Package

Click the **Add Package** button at the bottom right.

Xcode will download and integrate the packages. This may take a minute.

### Step 5: Verify Installation

After installation completes:

1. In Project Navigator (left sidebar), you should see:
   - A **Dependencies** group at the bottom
   - Under it: **Package Dependencies** → **firebase-ios-sdk**

2. Click on your project name at the top of Navigator
3. Select the **Axon** target
4. Go to **General** tab
5. Scroll to **Frameworks, Libraries, and Embedded Content**
6. You should see all the Firebase frameworks listed

## ✨ That's It!

No more workspace files, no more pod commands. Just pure Xcode goodness!

## Next Steps

Now you can:

1. **Add your Swift files** (if not already added):
   - Right-click "Axon" group → "Add Files to 'Axon'..."
   - Select: Config, Services, Models, Views, Utils, DesignSystem folders
   - Uncheck "Copy items if needed"
   - Check target "Axon"

2. **Add GoogleService-Info.plist**:
   - Download from Firebase Console
   - Drag into Xcode project root
   - Check "Copy items if needed"
   - Check target "Axon"

3. **Clean and Build**:
   - Press **Shift+Cmd+K** to clean
   - Press **Cmd+B** to build
   - Press **Cmd+R** to run!

## 🎯 Quick Commands

```bash
# Open the project (use .xcodeproj now, not .xcworkspace!)
open Axon.xcodeproj

# If you ever need to reset SPM cache
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/Developer/Xcode/DerivedData/Axon-*
```

## 🔧 Troubleshooting

### Package resolution fails
- Go to **File** → **Packages** → **Reset Package Caches**
- Try adding the package again

### Can't find Firebase modules
- Make sure you added the packages to the correct target
- Clean build folder (Shift+Cmd+K) and rebuild

### Xcode crashes during package fetch
- Quit Xcode
- Delete derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData/Axon-*`
- Reopen and try again

## 📊 Before vs After

### Before (CocoaPods):
```bash
$ ls
Axon.xcodeproj
Axon.xcworkspace  ← Must use this
Podfile
Podfile.lock
Pods/             ← 100+ MB of files

# Must run:
$ pod install
```

### After (SPM):
```bash
$ ls
Axon.xcodeproj    ← Just use this!

# No extra commands needed!
```

---

**You're all set!** Add the Firebase packages in Xcode and you're ready to build. 🚀

The imports in our code are already correct and will work perfectly with SPM:
```swift
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
```

No code changes needed! ✨
