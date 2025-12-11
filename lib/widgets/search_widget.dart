import 'package:flutter/material.dart';

/// Custom search widget for RainSafe navigation.
/// Provides input fields for start and end locations with a search button.
class RainSafeSearchWidget extends StatelessWidget {
  final TextEditingController startController;
  final TextEditingController endController;
  final VoidCallback onSearchPressed;

  const RainSafeSearchWidget({
    super.key,
    required this.startController,
    required this.endController,
    required this.onSearchPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black87,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Start location input
            TextField(
              controller: startController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'From',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.my_location, color: Colors.cyan),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[900],
              ),
            ),
            const SizedBox(height: 10),
            // End location input
            TextField(
              controller: endController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'To',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.location_on, color: Colors.red),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.grey[900],
              ),
            ),
            const SizedBox(height: 10),
            // Search button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onSearchPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Find Safe Route',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
