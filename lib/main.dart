import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:project_1/screens/home_screen.dart';
import 'package:project_1/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚀 STARTUP: Flutter Bindings Initialized");

  // Start Firebase in background (don't await)
  _initializeFirebase();

  debugPrint("🚀 STARTUP: Starting RainSafe Navigator...");
  runApp(const RainSafeApp());
}

Future<void> _initializeFirebase() async {
  try {
    debugPrint("🔥 Initializing Firebase...");
    
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    debugPrint("✅ Firebase Initialized Successfully");

    debugPrint("🔐 Signing in anonymously...");
    final userCredential = await FirebaseAuth.instance.signInAnonymously();
    
    debugPrint("✅ Anonymous Auth Successful: ${userCredential.user?.uid}");
    
  } catch (e) {
    debugPrint("⚠️ FIREBASE INITIALIZATION FAILED (non-fatal)");
    debugPrint("   Error: $e");
    debugPrint("   App will continue without hazard reporting features");
  }
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