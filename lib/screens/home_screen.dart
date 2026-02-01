import 'package:flutter/material.dart';
import 'map_screen.dart';

/// Home/landing screen for the Rain Safe Navigator application.
/// Displays the app logo, title, and tagline with a button to access the map.
/// 
/// IMPROVEMENTS:
/// - Added error handling for missing logo asset
/// - Fallback to Material Icon if logo.png is missing
/// - Proper centering and responsive design
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _startController = TextEditingController(text: "Current Location");
  final _endController = TextEditingController();

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ✅ Logo with Error Handling
                _buildLogo(),
                
                const SizedBox(height: 30),
                
                // ✅ App Title
                const Text(
                  "RainSafe Navigator",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                
                const SizedBox(height: 10),
                
                // ✅ Tagline
                const Text(
                  "Avoid rain. Drive safe. Reach faster.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                
                const SizedBox(height: 40),

                // ✅ TRIP PLANNER CARD
                Card(
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.grey.shade800),
                  ),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        _buildTextField(
                          controller: _startController,
                          icon: Icons.my_location,
                          hint: "Start Location",
                          isStart: true,
                        ),
                        const SizedBox(height: 15),
                        _buildTextField(
                          controller: _endController,
                          icon: Icons.location_on,
                          hint: "Where to?",
                          isStart: false,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // ✅ Open Map Button
                _buildMapButton(context),
                
                const SizedBox(height: 20),
                
                // ✅ Version Info (Optional)
                Text(
                  "v2.1 - 2026 Edition",
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    required bool isStart,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: isStart ? Colors.blue : Colors.red),
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.black54,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
      ),
    );
  }

  /// Build logo with fallback if asset is missing
  Widget _buildLogo() {
    return Container(
      height: 120, // Slightly smaller to fit inputs
      width: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade700,
            Colors.green.shade600,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/logo.png',
          height: 120,
          width: 120,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.blue.shade800,
              child: const Icon(
                Icons.cloud_queue,
                size: 60,
                color: Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }

  /// Build the "Open Map" button with gradient styling
  Widget _buildMapButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 8,
          shadowColor: Colors.greenAccent.withValues(alpha: 0.5),
        ),
        onPressed: () {
          // Navigate to MapScreen with input values
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MapScreen(
                startPoint: _startController.text.trim(),
                endPoint: _endController.text.trim(),
              ),
            ),
          );
        },
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 24), // Changed to Search icon
            SizedBox(width: 10),
            Text(
              "FIND SAFE ROUTE",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}