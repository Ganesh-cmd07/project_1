import 'package:flutter/material.dart';

/// Professional error handling utility for user-friendly error messages.
class ErrorHandler {
  /// Show a user-friendly error SnackBar with red background.
  static void showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Show a success SnackBar with green background.
  static void showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show a warning SnackBar with orange background.
  static void showWarning(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Show an error dialog.
  static void showErrorDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          title,
          style: const TextStyle(
              color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          )
        ],
      ),
    );
  }

  /// Log error to console (production-ready).
  static void logError(String tag, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('❌ [$tag] Error: $error');
    if (stackTrace != null) {
      debugPrint('Stack Trace:\n$stackTrace');
    }
  }

  /// Get user-friendly message from exception.
  static String getUserFriendlyMessage(dynamic error) {
    if (error is FormatException) {
      return 'Invalid data received from server. Please try again.';
    } else if (error.toString().contains('TimeoutException')) {
      return 'Request timed out. Please check your internet connection.';
    } else if (error.toString().contains('No route found')) {
      return 'No route found. Destination may be unreachable by road.';
    } else if (error.toString().contains('Failed host lookup')) {
      return 'No internet connection. Please check your network.';
    }
    return 'An error occurred. Please try again.';
  }
}
