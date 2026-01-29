# Firebase Integration Setup Guide

**Date**: January 25, 2026  
**Status**: ✅ **IMPLEMENTED - Ready for Configuration**

## Overview

Firebase integration has been implemented for the Rain Safe Navigator v2.0, enabling real-time crowd-sourced hazard reporting. The app now submits hazard reports to Firestore and can retrieve nearby hazards in real-time.

## What Was Added

### 1. **Dependencies** (pubspec.yaml)
```yaml
firebase_core: ^3.1.0       # Firebase initialization
cloud_firestore: ^5.0.1     # Real-time hazard database
```

### 2. **Firebase Service** (lib/services/firebase_service.dart)
Comprehensive Firebase integration service with:
- ✅ `submitHazardReport()` - Submit hazards to Firestore
- ✅ `getNearbyHazards()` - Fetch hazards within a radius
- ✅ `upvoteHazard()` - Community voting on hazards
- ✅ `resolveHazard()` - Mark hazards as resolved
- ✅ `getHazardStream()` - Real-time hazard updates

### 3. **Firebase Configuration** (lib/firebase_options.dart)
Template file for Firebase credentials (requires customization)

### 4. **Main App Initialization** (lib/main.dart)
Firebase initialization on app startup:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const RainSafeApp());
}
```

### 5. **Map Screen Integration** (lib/screens/map_screen.dart)
Updated `_submitHazardReport()` method:
- Calls `FirebaseService.submitHazardReport()`
- Proper error handling with user feedback
- Async/await pattern with `mounted` check

## Setup Instructions

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click "Create a new project"
3. Enter project name: `rain-safe-navigator` (or your choice)
4. Enable Google Analytics (optional)
5. Create project

### Step 2: Set Up Android

1. In Firebase Console, select your project
2. Click "Add app" → Select Android
3. Enter package name: `com.example.project_1`
4. Download `google-services.json`
5. Place file in: `android/app/google-services.json`

In `android/build.gradle.kts`, add:
```kotlin
plugins {
    id("com.google.gms.google-services") version "4.4.0" apply false
}
```

In `android/app/build.gradle.kts`, add:
```kotlin
plugins {
    id("com.google.gms.google-services")
}
```

### Step 3: Set Up iOS (Optional)

1. In Firebase Console, click "Add app" → Select iOS
2. Enter bundle ID: `com.example.project1` (from Xcode)
3. Download `GoogleService-Info.plist`
4. In Xcode, drag file to `Runner` folder
5. Ensure "Copy items if needed" is checked

### Step 4: Update Firebase Configuration

Edit `lib/firebase_options.dart` with your credentials:

```dart
static const FirebaseOptions android = FirebaseOptions(
  apiKey: 'YOUR_ANDROID_API_KEY',      // From google-services.json
  appId: '1:YOUR_PROJECT_NUMBER:android:YOUR_ANDROID_APP_ID',
  messagingSenderId: 'YOUR_PROJECT_NUMBER',
  projectId: 'your-firebase-project-id',  // Your project ID
  databaseURL: 'https://your-project-id.firebaseio.com',
);
```

**Where to find these values:**

1. Open `android/app/google-services.json`
2. Find section: `"client": [ { "client_info": { ... } } ]`
3. Extract:
   - `api_key[0].current_key` = apiKey
   - `client_id[0].client_id` = appId
   - `project_id` = projectId

### Step 5: Set Up Firestore Database

1. In Firebase Console, go to **Firestore Database**
2. Click "Create Database"
3. Select region: **asia-south1** (closest to India for lowest latency)
4. Choose "Start in test mode"
   - ⚠️ **Important**: Set security rules before production

### Step 6: Create Firestore Security Rules

In Firebase Console → Firestore → Rules, replace with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow reading all hazard reports
    match /hazard_reports/{document=**} {
      allow read: if request.auth != null || true;  // Public read for now
      allow create: if request.resource.data.latitude is number &&
                       request.resource.data.longitude is number &&
                       request.resource.data.hazardType is string;
      allow update: if resource.data.uid == request.auth.uid ||
                       request.resource.data.upvotes is number ||
                       request.resource.data.status is string;
      allow delete: if resource.data.uid == request.auth.uid;
    }
  }
}
```

### Step 7: Install Dependencies

```bash
cd c:\dev\project_1
flutter pub get
```

### Step 8: Test Firebase Connection

Run the app:
```bash
flutter run
```

Test hazard reporting:
1. Open the app
2. Enter start and end locations
3. Calculate a route
4. During navigation, click "Report Hazard" (red button)
5. Select a hazard type (Waterlogging/Accident/Road Block)
6. Check Firebase Console → Firestore to see the submitted report

## Firebase Data Structure

### Hazard Reports Collection
```
hazard_reports/
├── {docId}/
│   ├── latitude: number          # Hazard location latitude
│   ├── longitude: number         # Hazard location longitude
│   ├── hazardType: string        # "Waterlogging" | "Accident" | "Road Block"
│   ├── timestamp: timestamp      # When hazard was observed
│   ├── submittedAt: timestamp    # Server timestamp (auto)
│   ├── expiresAt: timestamp      # 24 hours from submission
│   ├── upvotes: number           # Community upvotes (starts at 0)
│   ├── severity: number          # 3=Accident, 2=RoadBlock, 1=Waterlogging
│   └── status: string            # "active" | "resolved"
```

## API Reference

### Submit Hazard Report
```dart
final report = HazardReport(
  location: LatLng(17.3850, 78.4867),
  hazardType: 'Waterlogging',
  timestamp: DateTime.now(),
);

await FirebaseService.submitHazardReport(report);
```

### Get Nearby Hazards
```dart
final hazards = await FirebaseService.getNearbyHazards(
  latitude: 17.3850,
  longitude: 78.4867,
  radiusKm: 5.0,
);
```

### Stream Real-Time Hazards
```dart
FirebaseService.getHazardStream().listen((hazards) {
  // Update markers on map with real-time hazards
  print('Found ${hazards.length} hazards');
});
```

### Upvote Hazard
```dart
await FirebaseService.upvoteHazard(hazardDocId);
```

### Resolve Hazard
```dart
await FirebaseService.resolveHazard(hazardDocId);
```

## Error Handling

Firebase errors are automatically converted to user-friendly messages:

| Error | Message |
|-------|---------|
| permission-denied | Permission denied. Please check Firestore rules. |
| network-error | Network error. Please check your connection. |
| unavailable | Firebase is temporarily unavailable. |
| unauthenticated | Authentication required. Please sign in. |

## Next Steps

### Phase 2: Enhanced Features
- [ ] Implement geo-hashing for efficient nearby queries
- [ ] Add user authentication (Firebase Auth)
- [ ] Real-time hazard markers on map
- [ ] User profiles and hazard history
- [ ] Hazard severity weighting in route calculation

### Phase 3: Analytics
- [ ] Track hazard report frequency
- [ ] Analyze common hazard locations
- [ ] Generate heat maps of danger zones
- [ ] Safety statistics dashboard

### Phase 4: Community Features
- [ ] User karma/reputation system
- [ ] Admin dashboard for moderation
- [ ] Machine learning for spam detection
- [ ] Integrations with local authorities

## Production Deployment Checklist

- [ ] Update `firebase_options.dart` with production credentials
- [ ] Set up strict Firestore security rules (not test mode)
- [ ] Enable authentication if required
- [ ] Configure Firebase backup policies
- [ ] Set up monitoring and alerts
- [ ] Test on real devices
- [ ] Deploy to Play Store / App Store

## Troubleshooting

### Firebase initialization fails
- Verify `google-services.json` is in `android/app/`
- Check project ID matches in `firebase_options.dart`
- Run `flutter clean` and `flutter pub get`

### Firestore write fails
- Check security rules in Firebase Console
- Verify network connectivity
- Check app has internet permission in `AndroidManifest.xml`

### Real-time updates not working
- Verify Firestore security rules allow read access
- Check that `getHazardStream()` subscription is active
- Verify no stream errors in logs

## Documentation

- [Firebase Dart Documentation](https://firebase.flutter.dev/)
- [Cloud Firestore Documentation](https://firebase.google.com/docs/firestore)
- [Flutter Fire GitHub](https://github.com/firebase/flutterfire)

---

**Status**: Implementation complete and ready for Firebase project setup ✅  
**Deployment**: Follow setup instructions above before production deployment