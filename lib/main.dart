import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:project_1/screens/home_screen.dart';
import 'package:project_1/theme/app_theme.dart';

void main() async {
  // 1. Ensure Flutter bindings are ready
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚀 STARTUP: Flutter Bindings Initialized");

  try {
    // 2. Initialize Firebase FIRST
    debugPrint("🚀 STARTUP: Initializing Firebase...");
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🚀 STARTUP: Firebase Initialized");

    // 3. Authenticate SECOND (Unlocks the database for the Liar Algorithm)
    debugPrint("🚀 STARTUP: Signing in anonymously...");
    await FirebaseAuth.instance.signInAnonymously();
    debugPrint("✅ RainSafe Apex: Anonymous Auth Successful");
  } catch (e, stack) {
    debugPrint("❌ FIREBASE/AUTH ERROR: $e");
    debugPrint(stack.toString());
  }

  debugPrint("🚀 STARTUP: Calling runApp()...");
  runApp(const RainSafeApp());
}

class RainSafeApp extends StatelessWidget {
  const RainSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RainSafe Navigator',
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
 /// Entry point of the Rain Safe Navigator application.