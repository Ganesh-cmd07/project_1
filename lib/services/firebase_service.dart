import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import '../models/route_model.dart';
import '../services/api_service.dart';
import '../utils/error_handler.dart';

/// Service for Firebase integration with crowd-sourced hazard reporting.
/// 
/// Implements the "Anti-Prankster Filter" with:
/// - Identity: Anonymous Auth to track User IDs (Prankster Filter Phase 1)
/// - Reputation: "Liar Algorithm" to shadow-ban unreliable users (Phase 2)
/// - Multi-factor verification (3+ confirmations required)
/// - Trust scoring based on sensor cross-check
/// - Geo-hashing for scalability
/// - 4-hour TTL for auto-cleanup
class FirebaseService {
  static const String _tag = 'FirebaseService';
  static const String _hazardsCollection = 'hazards';
  static const String _usersCollection = 'users'; // New: To track reputation
  static const Duration _reportExpirationHours = Duration(hours: 4);

  static late final FirebaseFirestore _firestore;
  static late final FirebaseAuth _auth;

  /// Initialize Firebase services (Firestore + Auth).
  static Future<void> initialize() async {
    try {
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      
      await _firestore.enableNetwork();
      
      // IDENTITY: Sign in anonymously to track user
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
        ErrorHandler.logError(_tag, 'Signed in anonymously: ${_auth.currentUser?.uid}');
      } else {
        ErrorHandler.logError(_tag, 'User already signed in: ${_auth.currentUser?.uid}');
      }

      ErrorHandler.logError(_tag, 'Firebase initialized (Auth + Firestore)');
    } catch (e) {
      ErrorHandler.logError(_tag, 'Firebase initialization error: $e');
      rethrow;
    }
  }

  /// Get current User ID.
  static String? get currentUserId => _auth.currentUser?.uid;

  /// Check user's reputation (The "Liar Algorithm").
  /// Returns false if user is shadow-banned.
  static Future<bool> _isUserTrusted(String uid) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(uid).get();
      if (!doc.exists) return true; // New users are trusted by default

      final reputation = (doc.data()?['reputation'] as num?)?.toDouble() ?? 1.0;
      return reputation > 0.3; // Threshold for shadow-ban
    } catch (e) {
      ErrorHandler.logError(_tag, 'Reputation check failed: $e');
      return true; // Fail safe
    }
  }

  /// Submit a hazard report with validation and ID tracking.
  static Future<bool> submitHazardReport(
    HazardReport report,
    ApiService apiService,
  ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      ErrorHandler.logError(_tag, '❌ Submission failed: No user ID');
      return false;
    }

    // LIAR ALGORITHM: Check if user is banned
    final isTrusted = await _isUserTrusted(uid);
    if (!isTrusted) {
      ErrorHandler.logError(_tag, '🚫 Shadow-ban: User report ignored (Low Reputation)');
      // Return true to fake success to the prankster (Shadow ban)
      return true;
    }

    try {
      // SENSOR CROSS-CHECK: Validate against weather data
      double adjustedTrustScore = report.trustScore;
      bool weatherValidated = false;
      
      if (report.hazardType.toLowerCase().contains('waterlog') ||
          report.hazardType.toLowerCase().contains('flood')) {
        final weather = await apiService.getWeatherAtLocation(report.location);
        
        if (weather != null) {
          final rainIntensity = (weather['rain'] as num?)?.toDouble() ?? 0.0;
          final weatherCode = (weather['weathercode'] as int?) ?? 0;
          final isRaining = weatherCode >= 51 && weatherCode <= 99;
          
          if (rainIntensity == 0.0 && !isRaining) {
            adjustedTrustScore = 0.2; // Suspicious
            ErrorHandler.logError(_tag, '⚠️ Suspicious: Flood claimed with 0mm rain');
          } else if (rainIntensity >= 5.0 || isRaining) {
            adjustedTrustScore = 0.75; // Confirmed by rain
            weatherValidated = true;
          }
        }
      }

      // 4-hour TTL
      final expiresAt = DateTime.now().add(_reportExpirationHours);

      final reportData = {
        'userId': uid, // IDENTITY
        'location': {
          'latitude': report.location.latitude,
          'longitude': report.location.longitude,
          'geohash': _generateGeohash(
            report.location.latitude,
            report.location.longitude,
          ),
        },
        'hazardType': report.hazardType,
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'trustScore': adjustedTrustScore,
        'status': 'pending', // Always starts as pending
        'confirmationCount': 0,
        'severity': _calculateSeverity(report.hazardType),
        'weatherValidated': weatherValidated,
      };

      final docRef = await _firestore.collection(_hazardsCollection).add(reportData);

      ErrorHandler.logError(
        _tag,
        '✅ Hazard Reported [ID: ${docRef.id}]\n'
        '   User: $uid\n'
        '   Trust: $adjustedTrustScore (Weather Validated: $weatherValidated)',
      );

      return true;
      
    } catch (e) {
      ErrorHandler.logError(_tag, '❌ Hazard submission error: $e');
      rethrow; // RETHROW so MapScreen can show specific error
    }
  }

  /// Confirm a hazard report (crowdsourced verification).
  static Future<bool> confirmHazard(String hazardDocId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      final docRef = _firestore.collection(_hazardsCollection).doc(hazardDocId);
      final doc = await docRef.get();

      if (!doc.exists) return false;

      // Prevent user from confirming own report
      final ownerId = doc.data()?['userId'] as String?;
      if (ownerId == uid) {
        ErrorHandler.logError(_tag, '⚠️ Cannot confirm own report');
        return false;
      }

      // Check if user already confirmed (using a subcollection or array - simplified here)
      // For MVP, we allow one confirmation per session logic, but ideally use subcollection.
      
      final currentCount = (doc.data()?['confirmationCount'] as int?) ?? 0;
      final currentTrust = (doc.data()?['trustScore'] as num?)?.toDouble() ?? 0.5;
      
      final newCount = currentCount + 1;
      final newTrust = (currentTrust + 0.15).clamp(0.0, 1.0);

      await docRef.update({
        'confirmationCount': newCount,
        'trustScore': newTrust,
        'status': newCount >= 3 ? 'verified' : 'pending',
      });

      // LIAR ALGORITHM REWARD: Boost owner's reputation
      if (ownerId != null && newCount == 3) {
        _updateUserReputation(ownerId, 0.1); // +0.1 reputation for verified report
      }

      return true;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Confirmation error: $e');
      return false;
    }
  }

  /// Reject a hazard report (flag as prank).
  static Future<bool> rejectHazard(String hazardDocId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;

    try {
      final docRef = _firestore.collection(_hazardsCollection).doc(hazardDocId);
      final doc = await docRef.get();

      if (!doc.exists) return false;

      final ownerId = doc.data()?['userId'] as String?;
      final currentTrust = (doc.data()?['trustScore'] as num?)?.toDouble() ?? 0.5;

      // Penalty
      final newTrust = (currentTrust - 0.3).clamp(0.0, 1.0);

      await docRef.update({
        'status': newTrust < 0.3 ? 'rejected' : 'disputed',
        'trustScore': newTrust,
      });

      // LIAR ALGORITHM PENALTY: Slash owner's reputation
      if (ownerId != null) {
        _updateUserReputation(ownerId, -0.2); // -0.2 reputation for fake report
      }
      
      return true;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Rejection error: $e');
      return false;
    }
  }

  /// Update a user's global reputation score.
  static Future<void> _updateUserReputation(String uid, double delta) async {
    try {
      final docRef = _firestore.collection(_usersCollection).doc(uid);
      
      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(docRef);
        
        double currentRep;
        if (!doc.exists) {
          currentRep = 1.0; // Start with full reputation
        } else {
          currentRep = (doc.data()?['reputation'] as num?)?.toDouble() ?? 1.0;
        }

        final newRep = (currentRep + delta).clamp(0.0, 5.0); // Max rep 5.0

        transaction.set(docRef, {
          'reputation': newRep,
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        ErrorHandler.logError(_tag, 'User $uid reputation updated: $currentRep -> $newRep');
      });
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to update user reputation: $e');
    }
  }

  /// Fetch active hazard reports.
  static Future<List<HazardReport>> getNearbyHazards(
    double latitude,
    double longitude, {
    double radiusKm = 5.0,
  }) async {
    // Existing logic remains similar but ensures we only get active hazards
    try {
      final now = DateTime.now();
      final snapshot = await _firestore
          .collection(_hazardsCollection)
          .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
          .where('status', whereIn: ['pending', 'verified'])
          .orderBy('expiresAt', descending: false)
          .limit(50)
          .get();

      final reports = <HazardReport>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final loc = data['location'] as Map<String, dynamic>;
        final lat = (loc['latitude'] as num).toDouble();
        final lon = (loc['longitude'] as num).toDouble();

        if (_calculateDistance(latitude, longitude, lat, lon) <= radiusKm) {
          reports.add(HazardReport(
            location: LatLng(lat, lon),
            hazardType: data['hazardType'] as String,
            timestamp: (data['timestamp'] as Timestamp).toDate(),
            trustScore: (data['trustScore'] as num).toDouble(),
            status: _parseStatus(data['status'] as String),
            confirmationCount: data['confirmationCount'] as int,
          ));
        }
      }
      return reports;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Error fetching hazards: $e');
      return [];
    }
  }

  static Stream<List<HazardReport>> getHazardStream() {
     // Same logic as before but ensures types are correct
     final now = DateTime.now();
     return _firestore
        .collection(_hazardsCollection)
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(now))
        .where('status', whereIn: ['pending', 'verified'])
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
             final data = doc.data();
             final loc = data['location'] as Map<String, dynamic>;
             return HazardReport(
               location: LatLng(loc['latitude'], loc['longitude']),
               hazardType: data['hazardType'],
               timestamp: (data['timestamp'] as Timestamp).toDate(),
               trustScore: (data['trustScore'] as num).toDouble(),
               status: _parseStatus(data['status']),
               confirmationCount: data['confirmationCount'],
             );
          }).toList();
        });
  }

  // Helpers
  static String _generateGeohash(double lat, double lon) {
    final latIndex = ((lat + 90) / 180 * 1000).floor();
    final lonIndex = ((lon + 180) / 360 * 1000).floor();
    return '${latIndex}_$lonIndex';
  }

  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return const Distance().as(LengthUnit.Kilometer, LatLng(lat1, lon1), LatLng(lat2, lon2));
  }

  static int _calculateSeverity(String type) {
    if (type.toLowerCase().contains('accident')) return 3;
    if (type.toLowerCase().contains('road')) return 2;
    return 1;
  }

  static HazardStatus _parseStatus(String status) {
    return HazardStatus.values.firstWhere(
      (e) => e.toString().split('.').last == status,
      orElse: () => HazardStatus.pending,
    );
  }


}
