import 'package:flutter/material.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ✅ Start Location Input
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: startController,
            decoration: const InputDecoration(
              hintText: "From: Current Location",
              prefixIcon: Icon(Icons.my_location, color: Colors.green),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // ✅ Destination Input with Search Icon
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: TextField(
            controller: endController,
            onSubmitted: (_) => onSearchPressed(),
            decoration: InputDecoration(
              hintText: "To: Enter Destination City",
              prefixIcon: const Icon(Icons.location_on, color: Colors.red),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.blueAccent),
                onPressed: onSearchPressed,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      ],
    );
  }
}