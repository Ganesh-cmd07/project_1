import 'package:flutter/material.dart';
import 'map_screen.dart';

/// Home/landing screen for the Rain Safe Navigator application.
/// Displays the app logo, title, and tagline with a button to access the map.
/// 
/// IMPROVEMENTS:
/// - Added error handling for missing logo asset
/// - Fallback to Material Icon if logo.png is missing
/// - Proper centering and responsive design
class HomeScreen extends StatelessWidget {
  /// Creates a [HomeScreen] widget.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Center(
          child: Padding(
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
                
                const SizedBox(height: 50),
                
                // ✅ Open Map Button
                _buildMapButton(context),
                
                const SizedBox(height: 20),
                
                // ✅ Version Info (Optional)
                Text(
                  "v2.0 - 2026 Edition",
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

  /// Build logo with fallback if asset is missing
  Widget _buildLogo() {
    return Container(
      height: 150,
      width: 150,
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
            color: Colors.greenAccent.withValues(alpha: 0.3), // ✅ FIXED
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset(
          'assets/logo.png',
          height: 150,
          width: 150,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // ✅ FALLBACK: If logo.png is missing, show icon
            return Container(
              color: Colors.blue.shade800,
              child: const Icon(
                Icons.cloud_queue,
                size: 80,
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
          shadowColor: Colors.greenAccent.withValues(alpha: 0.5), // ✅ FIXED
        ),
        onPressed: () {
          // Navigate to MapScreen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MapScreen(),
            ),
          );
        },
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map, size: 24),
            SizedBox(width: 10),
            Text(
              "OPEN MAP",
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