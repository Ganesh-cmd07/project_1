import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A premium bottom-sheet language selector with flag icons and smooth animations.
class LanguageSelector extends StatelessWidget {
  final String currentLanguage;
  final Map<String, String> languageNames;
  final ValueChanged<String> onLanguageSelected;

  const LanguageSelector({
    super.key,
    required this.currentLanguage,
    required this.languageNames,
    required this.onLanguageSelected,
  });

  /// Show the language selector as a modal bottom sheet.
  static Future<String?> show(
    BuildContext context, {
    required String currentLanguage,
    required Map<String, String> languageNames,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => LanguageSelector(
        currentLanguage: currentLanguage,
        languageNames: languageNames,
        onLanguageSelected: (code) => Navigator.pop(ctx, code),
      ),
    );
  }

  // Map language codes to flag emojis
  static const Map<String, String> _flags = {
    'en-IN': '🇬🇧',
    'hi-IN': '🇮🇳',
    'te-IN': '🇮🇳',
    'ta-IN': '🇮🇳',
    'kn-IN': '🇮🇳',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.translate, color: Colors.white70, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Voice Language',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${languageNames.length} available',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Language list
          ...languageNames.entries.map((entry) {
            final isSelected = entry.key == currentLanguage;
            final flag = _flags[entry.key] ?? '🌐';

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onLanguageSelected(entry.key);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color: isSelected ? Colors.blue : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Flag
                      Text(flag, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 16),

                      // Language name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.value,
                              style: TextStyle(
                                color: isSelected ? Colors.blue[200] : Colors.white,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            Text(
                              entry.key,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Checkmark
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check, color: Colors.white, size: 14),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
