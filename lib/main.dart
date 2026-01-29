import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:project_1/screens/map_screen.dart';

/// Entry point of the Rain Safe Navigator application.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const RainSafeApp());
}

/// Root widget of the Rain Safe Navigator application.
/// Provides Material Design theme and initializes the home screen.
class RainSafeApp extends StatelessWidget {
  /// Creates a [RainSafeApp] widget.
  const RainSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RainSafe Navigator',
      theme: ThemeData(brightness: Brightness.dark, primaryColor: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

/// Home screen for route planning and navigation setup.
/// Allows users to input start and end locations for safe route calculation.
class HomeScreen extends StatefulWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Controller for the start location input field.
  final TextEditingController _startController =
      TextEditingController(text: "Current Location");

  /// Controller for the end location input field.
  final TextEditingController _endController = TextEditingController();

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RainSafe Navigator")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Plan Your Safe Route",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
            // Start location input
            TextField(
              controller: _startController,
              decoration: InputDecoration(
                hintText: "From (e.g., Current Location or address)",
                prefixIcon: const Icon(Icons.my_location),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            // End location input
            TextField(
              controller: _endController,
              decoration: InputDecoration(
                hintText: "To (destination address)",
                prefixIcon: const Icon(Icons.location_on),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 40),
            // Navigate button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final String start = _startController.text.trim();
                  final String end = _endController.text.trim();

                  if (end.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text("Please enter a destination")),
                    );
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapScreen(
                        startPoint: start.isEmpty ? "Current Location" : start,
                        endPoint: end,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  "Find Safe Route",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
