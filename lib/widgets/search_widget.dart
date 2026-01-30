/// A custom search widget for location input with autocomplete suggestions.
/// Provides typeahead functionality for both start and end locations.
library;
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class RainSafeSearchWidget extends StatefulWidget {
  /// Controller for the start location input field.
  final TextEditingController startController;

  /// Controller for the end location input field.
  final TextEditingController endController;

  /// Callback invoked when the search is pressed.
  final VoidCallback onSearchPressed;

  /// Creates a [RainSafeSearchWidget].
  const RainSafeSearchWidget({
    super.key,
    required this.startController,
    required this.endController,
    required this.onSearchPressed,
  });

  @override
  State<RainSafeSearchWidget> createState() => _RainSafeSearchWidgetState();
}

class _RainSafeSearchWidgetState extends State<RainSafeSearchWidget> {
  final ApiService _api = ApiService();

  List<String> _suggestions = [];
  bool _showSuggestions = false;
  bool _isTypingInStart = false;

  void _onTextChanged(String query, bool isStartField) async {
    setState(() {
      _isTypingInStart = isStartField;
    });

    if (query.isEmpty) {
      final history = await _api.getPlaceSuggestions("");
      if (mounted) {
        setState(() {
          _suggestions = history;
          _showSuggestions = history.isNotEmpty;
        });
      }
      return;
    }

    final results = await _api.getPlaceSuggestions(query);

    if (mounted) {
      setState(() {
        _suggestions = results;
        _showSuggestions = results.isNotEmpty;
      });
    }
  }

  void _onSuggestionTapped(String value) {
    setState(() {
      if (_isTypingInStart) {
        widget.startController.text = value;
      } else {
        widget.endController.text = value;
      }
      _showSuggestions = false;
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // THE SEARCH CARD (Black Background)
        Card(
          elevation: 8,
          color: Colors.grey[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                // Start Location Field
                _buildTextField(
                  controller: widget.startController,
                  icon: Icons.my_location,
                  hint: "Start (or 'Current Location')",
                  isStart: true,
                ),
                Divider(height: 1, thickness: 0.5, color: Colors.grey[700]),

                // Destination Field
                _buildTextField(
                  controller: widget.endController,
                  icon: Icons.location_on,
                  hint: "Where to?",
                  isStart: false,
                ),

                const SizedBox(height: 8),

                // Search Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _showSuggestions = false);
                      widget.onSearchPressed();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Find Safe Route",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),

        // THE SUGGESTION LIST (Black Background)
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 5))
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (ctx, i) =>
                    Divider(height: 1, color: Colors.grey[800]),
                itemBuilder: (ctx, index) {
                  final option = _suggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.history, size: 18, color: Colors.grey),
                    title: Text(option,
                        style: const TextStyle(fontSize: 14, color: Colors.white)),
                    onTap: () => _onSuggestionTapped(option),
                  );
                },
              ),
            ),
          ),
      ],
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
      onChanged: (val) => _onTextChanged(val, isStart),
      onTap: () {
        if (controller.text.isEmpty) _onTextChanged("", isStart);
      },
      decoration: InputDecoration(
        icon: Icon(icon, color: isStart ? Colors.blue : Colors.redAccent),
        border: InputBorder.none,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade600),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                onPressed: () {
                  controller.clear();
                  _onTextChanged("", isStart);
                },
              )
            : null,
      ),
    );
  }
}