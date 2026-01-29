// Firebase configuration file generated for Rain Safe Navigator.
//
// Run the following command to generate this file:
// `flutterfire configure --project=your-project-id`
//
// This file contains Firebase configuration for different platforms.
// Update the values with your actual Firebase project credentials.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Default Firebase options for use across all platforms.
/// Update these values from your Firebase Console:
/// https://console.firebase.google.com
class DefaultFirebaseOptions {
  /// Android Firebase configuration.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: '1:YOUR_PROJECT_NUMBER:android:YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_PROJECT_NUMBER',
    projectId: 'your-firebase-project-id',
    databaseURL: 'https://your-firebase-project-id.firebaseio.com',
  );

  /// iOS Firebase configuration.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: '1:YOUR_PROJECT_NUMBER:ios:YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_PROJECT_NUMBER',
    projectId: 'your-firebase-project-id',
    databaseURL: 'https://your-firebase-project-id.firebaseio.com',
    iosBundleId: 'com.example.rainSafeNavigator',
  );

  /// Returns the appropriate Firebase options for the current platform.
  static FirebaseOptions get currentPlatform {
    return android; // Update based on platform detection if needed
  }
}
