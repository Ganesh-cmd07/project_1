import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_model.dart';
import '../utils/error_handler.dart';

/// Service for Firebase integration with crowd-sourced hazard reporting.
/// Handles real-time hazard submission and retrieval from Firestore.
class FirebaseService {
  static const String _tag = 'FirebaseService';
  static const String _hazardsCollection = 'hazard_reports';
  static const Duration _reportExpirationHours = Duration(hours: 24);

  /// Firestore instance (lazy-loaded).
  static late final FirebaseFirestore _firestore;

  /// Initialize Firebase Firestore.
  static Future<void> initialize() async {
    try {
      _firestore = FirebaseFirestore.instance;

      // Enable offline persistence for better UX
      await _firestore.enableNetwork();

      ErrorHandler.logError(_tag, 'Firebase Firestore initialized');
    } catch (e) {
      ErrorHandler.logError(_tag, 'Firebase initialization error: $e');
      rethrow;
    }
  }

  /// Submit a hazard report to Firestore.
  ///
  /// Stores the hazard with timestamp, location, and type.
  /// Automatically expires reports after 24 hours.
  static Future<bool> submitHazardReport(HazardReport report) async {
    try {
      // Calculate expiration time (24 hours from now)
      final expiresAt = DateTime.now().add(_reportExpirationHours);

      final reportData = {
        ...report.toJson(),
        'submittedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'upvotes': 0,
        'severity': _calculateSeverity(report.hazardType),
        'status': 'active',
      };

      // Submit to Firestore
      await _firestore.collection(_hazardsCollection).add(reportData);

      ErrorHandler.logError(
        _tag,
        'Hazard reported: ${report.hazardType} at ${report.location}',
      );

      return true;
    } on FirebaseException catch (e) {
      final message = _getFirebaseErrorMessage(e);
      ErrorHandler.logError(_tag, 'Firebase error: $message');
      rethrow;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Hazard submission error: $e');
      rethrow;
    }
  }

  /// Fetch active hazard reports within a radius (in km).
  ///
  /// Returns hazards near the given location that are still active.
  static Future<List<HazardReport>> getNearbyHazards(
    double latitude,
    double longitude, {
    double radiusKm = 5.0,
  }) async {
    try {
      final now = DateTime.now();

      // Query recent hazards (simplified - no geo-hashing in this version)
      // For production, use GeoFlutterFire or implement geo-hashing
      final snapshot = await _firestore
          .collection(_hazardsCollection)
          .where('status', isEqualTo: 'active')
          .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
          .orderBy('expiresAt', descending: false)
          .limit(50)
          .get();

      final reports = <HazardReport>[];

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final report = HazardReport(
            location: _parseLocation(data),
            hazardType: (data['hazardType'] as String?) ?? 'Unknown',
            timestamp: ((data['submittedAt'] as Timestamp?)?.toDate()) ??
                DateTime.now(),
          );
          reports.add(report);
        } catch (e) {
          ErrorHandler.logError(_tag, 'Error parsing hazard: $e');
        }
      }

      return reports;
    } on FirebaseException catch (e) {
      final message = _getFirebaseErrorMessage(e);
      ErrorHandler.logError(_tag, 'Firebase query error: $message');
      return [];
    } catch (e) {
      ErrorHandler.logError(_tag, 'Nearby hazards error: $e');
      return [];
    }
  }

  /// Upvote a hazard report to increase visibility.
  ///
  /// Increments the upvote count for a hazard.
  static Future<bool> upvoteHazard(String hazardDocId) async {
    try {
      await _firestore.collection(_hazardsCollection).doc(hazardDocId).update({
        'upvotes': FieldValue.increment(1),
      });

      ErrorHandler.logError(_tag, 'Hazard upvoted: $hazardDocId');
      return true;
    } on FirebaseException catch (e) {
      final message = _getFirebaseErrorMessage(e);
      ErrorHandler.logError(_tag, 'Firebase error: $message');
      return false;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Upvote error: $e');
      return false;
    }
  }

  /// Resolve/close a hazard report.
  ///
  /// Marks a hazard as resolved when the situation is no longer present.
  static Future<bool> resolveHazard(String hazardDocId) async {
    try {
      await _firestore.collection(_hazardsCollection).doc(hazardDocId).update({
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      ErrorHandler.logError(_tag, 'Hazard resolved: $hazardDocId');
      return true;
    } on FirebaseException catch (e) {
      final message = _getFirebaseErrorMessage(e);
      ErrorHandler.logError(_tag, 'Firebase error: $message');
      return false;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Resolve error: $e');
      return false;
    }
  }

  /// Stream of active hazard reports for real-time updates.
  ///
  /// Useful for updating hazard markers on the map in real-time.
  static Stream<List<HazardReport>> getHazardStream() {
    try {
      final now = DateTime.now();

      return _firestore
          .collection(_hazardsCollection)
          .where('status', isEqualTo: 'active')
          .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
          .orderBy('expiresAt', descending: false)
          .snapshots()
          .map((snapshot) {
        final reports = <HazardReport>[];

        for (final doc in snapshot.docs) {
          try {
            final data = doc.data();
            final report = HazardReport(
              location: _parseLocation(data),
              hazardType: (data['hazardType'] as String?) ?? 'Unknown',
              timestamp: ((data['submittedAt'] as Timestamp?)?.toDate()) ??
                  DateTime.now(),
            );
            reports.add(report);
          } catch (e) {
            ErrorHandler.logError(_tag, 'Error parsing hazard: $e');
          }
        }

        return reports;
      }).handleError((error) {
        ErrorHandler.logError(_tag, 'Stream error: $error');
        return <HazardReport>[];
      });
    } catch (e) {
      ErrorHandler.logError(_tag, 'Stream creation error: $e');
      return Stream.value([]);
    }
  }

  // ====================================================================
  // PRIVATE HELPER METHODS
  // ====================================================================

  /// Calculate severity level based on hazard type.
  static int _calculateSeverity(String hazardType) {
    switch (hazardType.toLowerCase()) {
      case 'accident':
        return 3; // Highest priority
      case 'road block':
        return 2;
      case 'waterlogging':
        return 1;
      default:
        return 0;
    }
  }

  /// Parse location from Firestore document data.
  static LatLng _parseLocation(Map<String, dynamic> data) {
    final latitude = (data['latitude'] as num?)?.toDouble() ?? 0.0;
    final longitude = (data['longitude'] as num?)?.toDouble() ?? 0.0;

    return LatLng(latitude, longitude);
  }

  /// Convert Firebase errors to user-friendly messages.
  static String _getFirebaseErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'Permission denied. Please check Firestore rules.';
      case 'network-error':
        return 'Network error. Please check your connection.';
      case 'unavailable':
        return 'Firebase is temporarily unavailable.';
      case 'unauthenticated':
        return 'Authentication required. Please sign in.';
      default:
        return 'Firebase error: ${e.code}';
    }
  }
}
