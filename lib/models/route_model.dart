import 'package:latlong2/latlong.dart';

// ==========================================
// VEHICLE TYPES
// ==========================================

/// Vehicle types with specific risk thresholds for rain.
enum VehicleType {
  /// Motorcycle/bike vehicle type
  bike,
  
  /// Car vehicle type
  car,
  
  /// Truck vehicle type
  truck,
  
  /// Bus vehicle type
  bus;

  /// Icon representation for each vehicle type.
  String get icon {
    switch (this) {
      case VehicleType.bike:
        return '🏍️';
      case VehicleType.car:
        return '🚗';
      case VehicleType.truck:
        return '🚚';
      case VehicleType.bus:
        return '🚌';
    }
  }

  /// Display name for the vehicle type.
  String get displayName {
    switch (this) {
      case VehicleType.bike:
        return 'Bike';
      case VehicleType.car:
        return 'Car';
      case VehicleType.truck:
        return 'Truck';
      case VehicleType.bus:
        return 'Bus';
    }
  }

  /// Rain threshold in mm/hr for each vehicle type.
  /// Bikes are most vulnerable, trucks/buses more resilient.
  double get rainThreshold {
    switch (this) {
      case VehicleType.bike:
        return 5.0; // High sensitivity for two-wheelers
      case VehicleType.car:
        return 15.0; // Lower sensitivity
      case VehicleType.truck:
        return 10.0;
      case VehicleType.bus:
        return 12.0;
    }
  }
}

// ==========================================
// GPS POLLING CONFIGURATION
// ==========================================

/// GPS polling configuration for thermal/battery optimization.
class GPSPollingConfig {
  /// Get optimal distance filter based on navigation state.
  /// 
  /// THERMAL/BATTERY GUARD: Reduces GPS polling on straightaways to prevent overheating.
  static int getDistanceFilter({
    required bool isNavigating,
    required bool isStraightaway,
    required bool isInCity,
  }) {
    if (!isNavigating) return 10; // Normal tracking
    if (isStraightaway) return 50; // On straightaway, save battery
    if (isInCity) return 5; // High accuracy in city
    return 10; // Default
  }
}

// ==========================================
// HAZARD STATUS & REPORTING
// ==========================================

/// Status of a hazard report in the verification lifecycle.
enum HazardStatus {
  /// Awaiting verification
  pending,
  
  /// Confirmed by 3+ users
  verified,
  
  /// Flagged as false
  rejected,
  
  /// Time-to-live expired
  expired;
}

/// Hazard report with trust scoring and verification.
/// 
/// ANTI-PRANKSTER FILTER: Includes trust score and sensor cross-check validation.
class HazardReport {
  /// The geographical location of the hazard.
  final LatLng location;

  /// The type of hazard (e.g., "Waterlogging", "Accident", "Road Block").
  final String hazardType;

  /// The timestamp when the report was created.
  final DateTime timestamp;

  /// Trust score (0.0 to 1.0) based on sensor cross-check and user history.
  final double trustScore;

  /// Current verification status.
  final HazardStatus status;

  /// Number of independent confirmations.
  final int confirmationCount;

  /// Creates a [HazardReport].
  HazardReport({
    required this.location,
    required this.hazardType,
    required this.timestamp,
    this.trustScore = 0.5,
    this.status = HazardStatus.pending,
    this.confirmationCount = 0,
  });

  /// Convert to JSON for Firestore storage.
  Map<String, dynamic> toJson() {
    return {
      'location': {
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'hazardType': hazardType,
      'timestamp': timestamp.toIso8601String(),
      'trustScore': trustScore,
      'status': status.toString().split('.').last,
      'confirmationCount': confirmationCount,
      'expiresAt': timestamp.add(const Duration(hours: 4)).toIso8601String(),
    };
  }

  /// Create from Firestore document.
  factory HazardReport.fromJson(Map<String, dynamic> json) {
    final location = json['location'] as Map<String, dynamic>?;
    return HazardReport(
      location: LatLng(
        (location?['latitude'] as num?)?.toDouble() ?? 0.0,
        (location?['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      hazardType: (json['hazardType'] as String?) ?? 'Unknown',
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ?? DateTime.now(),
      trustScore: (json['trustScore'] as num?)?.toDouble() ?? 0.5,
      status: _parseStatus((json['status'] as String?) ?? 'pending'),
      confirmationCount: (json['confirmationCount'] as int?) ?? 0,
    );
  }

  /// Copy with updated verification status.
  HazardReport copyWith({
    double? trustScore,
    HazardStatus? status,
    int? confirmationCount,
  }) {
    return HazardReport(
      location: location,
      hazardType: hazardType,
      timestamp: timestamp,
      trustScore: trustScore ?? this.trustScore,
      status: status ?? this.status,
      confirmationCount: confirmationCount ?? this.confirmationCount,
    );
  }

  /// Parse status string to enum.
  static HazardStatus _parseStatus(String status) {
    switch (status.toLowerCase()) {
      case 'verified':
        return HazardStatus.verified;
      case 'rejected':
        return HazardStatus.rejected;
      case 'expired':
        return HazardStatus.expired;
      default:
        return HazardStatus.pending;
    }
  }
}

// ==========================================
// ROUTE MODEL
// ==========================================

/// Represents a calculated route with weather and elevation analysis.
class RouteModel {
  /// List of coordinates forming the route path.
  final List<LatLng> points;

  /// Turn-by-turn navigation steps.
  final List<RouteStep> steps;

  /// Weather alerts along the route.
  final List<WeatherAlert> weatherAlerts;

  /// Elevation dips (potential waterlogging zones).
  final List<ElevationDip> elevationDips;

  /// Total distance in meters.
  final double distanceMeters;

  /// Estimated duration in minutes.
  final int durationMinutes;

  /// Estimated duration in seconds (for precise calculations).
  final int durationSeconds;

  /// Risk level: "Safe", "Medium", or "High".
  final String riskLevel;

  /// Whether rain is detected along the route.
  final bool isRaining;

  /// Hydroplaning risk for high-speed segments in rain.
  final bool hydroplaningRisk;

  /// Whether route includes unpaved roads.
  final bool hasUnpavedRoads;

  /// Creates a [RouteModel].
  RouteModel({
    required this.points,
    required this.steps,
    required this.weatherAlerts,
    required this.elevationDips,
    required this.distanceMeters,
    required this.durationMinutes,
    required this.durationSeconds,
    required this.riskLevel,
    required this.isRaining,
    required this.hydroplaningRisk,
    required this.hasUnpavedRoads,
  });

  /// Convert to JSON for offline storage.
  Map<String, dynamic> toJson() {
    return {
      'points': points.map((p) => {'lat': p.latitude, 'lon': p.longitude}).toList(),
      'steps': steps.map((s) => s.toJson()).toList(),
      'weatherAlerts': weatherAlerts.map((w) => w.toJson()).toList(),
      'elevationDips': elevationDips.map((e) => e.toJson()).toList(),
      'distanceMeters': distanceMeters,
      'durationMinutes': durationMinutes,
      'durationSeconds': durationSeconds,
      'riskLevel': riskLevel,
      'isRaining': isRaining,
      'hydroplaningRisk': hydroplaningRisk,
      'hasUnpavedRoads': hasUnpavedRoads,
    };
  }

  /// Create from stored JSON.
  factory RouteModel.fromJson(Map<String, dynamic> json) {
    return RouteModel(
      points: (json['points'] as List<dynamic>)
          .map((p) => LatLng(p['lat'], p['lon']))
          .toList(),
      steps: (json['steps'] as List<dynamic>)
          .map((s) => RouteStep.fromJson(s))
          .toList(),
      weatherAlerts: (json['weatherAlerts'] as List<dynamic>)
          .map((w) => WeatherAlert.fromJson(w))
          .toList(),
      elevationDips: (json['elevationDips'] as List<dynamic>)
          .map((e) => ElevationDip.fromJson(e))
          .toList(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationMinutes: json['durationMinutes'] as int,
      durationSeconds: json['durationSeconds'] as int,
      riskLevel: json['riskLevel'] as String,
      isRaining: json['isRaining'] as bool,
      hydroplaningRisk: json['hydroplaningRisk'] as bool? ?? false,
      hasUnpavedRoads: json['hasUnpavedRoads'] as bool? ?? false,
    );
  }

  /// Create from OSRM API response.
  factory RouteModel.fromOsrmJson(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>?;
    final coordinates = (geometry?['coordinates'] as List<dynamic>?) ?? [];

    final points = coordinates
        .map((coord) {
          final coordList = coord as List<dynamic>;
          return LatLng(
            (coordList[1] as num).toDouble(),
            (coordList[0] as num).toDouble(),
          );
        })
        .toList();

    final legs = (json['legs'] as List<dynamic>?) ?? [];
    final allSteps = <RouteStep>[];

    for (final leg in legs) {
      final legMap = leg as Map<String, dynamic>;
      final steps = (legMap['steps'] as List<dynamic>?) ?? [];
      for (final step in steps) {
        allSteps.add(RouteStep.fromOsrmJson(step as Map<String, dynamic>));
      }
    }

    final distance = (json['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['duration'] as num?)?.toDouble() ?? 0.0;

    return RouteModel(
      points: points,
      steps: allSteps,
      weatherAlerts: [],
      elevationDips: [],
      distanceMeters: distance,
      durationMinutes: (duration / 60).round(),
      durationSeconds: duration.round(),
      riskLevel: 'Unknown',
      isRaining: false,
      hydroplaningRisk: false,
      hasUnpavedRoads: false,
    );
  }

  /// Copy with weather analysis results.
  RouteModel copyWithWeather({
    bool? isRaining,
    String? riskLevel,
    List<WeatherAlert>? weatherAlerts,
    List<ElevationDip>? elevationDips,
    bool? hydroplaningRisk,
    bool? hasUnpavedRoads,
  }) {
    return RouteModel(
      points: points,
      steps: steps,
      weatherAlerts: weatherAlerts ?? this.weatherAlerts,
      elevationDips: elevationDips ?? this.elevationDips,
      distanceMeters: distanceMeters,
      durationMinutes: durationMinutes,
      durationSeconds: durationSeconds,
      riskLevel: riskLevel ?? this.riskLevel,
      isRaining: isRaining ?? this.isRaining,
      hydroplaningRisk: hydroplaningRisk ?? this.hydroplaningRisk,
      hasUnpavedRoads: hasUnpavedRoads ?? this.hasUnpavedRoads,
    );
  }

  /// Snap GPS position to nearest route point.
  /// 
  /// POLYLINE SNAP FIX: Prevents GPS "floating" off the road.
  LatLng snapToRoute(LatLng gpsPosition) {
    if (points.isEmpty) return gpsPosition;

    LatLng closest = points.first;
    double minDistance = _calculateDistance(gpsPosition, closest);

    for (final point in points) {
      final distance = _calculateDistance(gpsPosition, point);
      if (distance < minDistance) {
        minDistance = distance;
        closest = point;
      }
    }

    return closest;
  }

  /// Check if next segment is straight (for GPS polling optimization).
  /// 
  /// THERMAL/BATTERY GUARD: Used to adjust GPS polling rate.
  bool isNextSegmentStraight(int currentStepIndex) {
    if (currentStepIndex >= steps.length - 1) return false;
    final step = steps[currentStepIndex];
    return step.maneuverType.toLowerCase().contains('straight') ||
           step.maneuverType.toLowerCase().contains('continue');
  }

  /// Calculate distance between two points in meters.
  double _calculateDistance(LatLng p1, LatLng p2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, p1, p2);
  }
}

// ==========================================
// ROUTE STEP
// ==========================================

/// Represents a single navigation step in a route.
class RouteStep {
  /// Human-readable instruction.
  final String instruction;

  /// Distance in meters for this step.
  final double distance;

  /// Maneuver type (e.g., "turn", "straight", "arrive").
  final String maneuverType;

  /// Location [longitude, latitude] where maneuver occurs.
  final List<double> location;

  /// Creates a [RouteStep].
  RouteStep({
    required this.instruction,
    required this.distance,
    required this.maneuverType,
    required this.location,
  });

  /// Convert to JSON.
  Map<String, dynamic> toJson() => {
    'instruction': instruction,
    'distance': distance,
    'maneuverType': maneuverType,
    'location': location,
  };

  /// Create from JSON.
  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      instruction: json['instruction'],
      distance: (json['distance'] as num).toDouble(),
      maneuverType: json['maneuverType'],
      location: (json['location'] as List<dynamic>).map((e) => (e as num).toDouble()).toList(),
    );
  }

  /// Create from OSRM step JSON.
  factory RouteStep.fromOsrmJson(Map<String, dynamic> json) {
    final maneuver = json['maneuver'] as Map<String, dynamic>?;
    final location = (maneuver?['location'] as List<dynamic>?) ?? [0.0, 0.0];

    return RouteStep(
      instruction: (json['name'] as String?) ?? 'Continue',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      maneuverType: (maneuver?['type'] as String?) ?? 'continue',
      location: [
        (location[0] as num).toDouble(),
        (location[1] as num).toDouble(),
      ],
    );
  }
}

// ==========================================
// WEATHER ALERT
// ==========================================

/// Weather alert for a specific point along the route.
class WeatherAlert {
  /// Location of the alert.
  final LatLng point;

  /// Weather code from Open-Meteo.
  final int weatherCode;

  /// Human-readable description.
  final String description;

  /// Temperature in Celsius.
  final double temperature;

  /// Time when alert applies (HH:MM format).
  final String time;

  /// Rain intensity in mm/hr.
  final double? rainIntensity;

  /// Creates a [WeatherAlert].
  WeatherAlert({
    required this.point,
    required this.weatherCode,
    required this.description,
    required this.temperature,
    required this.time,
    this.rainIntensity,
  });

  Map<String, dynamic> toJson() => {
    'point': {'lat': point.latitude, 'lon': point.longitude},
    'weatherCode': weatherCode,
    'description': description,
    'temperature': temperature,
    'time': time,
    'rainIntensity': rainIntensity,
  };

  factory WeatherAlert.fromJson(Map<String, dynamic> json) {
    return WeatherAlert(
      point: LatLng(json['point']['lat'], json['point']['lon']),
      weatherCode: json['weatherCode'],
      description: json['description'],
      temperature: (json['temperature'] as num).toDouble(),
      time: json['time'],
      rainIntensity: (json['rainIntensity'] as num?)?.toDouble(),
    );
  }
}

// ==========================================
// ELEVATION DIP
// ==========================================

/// Represents an elevation dip (potential waterlogging zone).
class ElevationDip {
  /// Location of the dip.
  final LatLng point;

  /// Depth of the dip in meters.
  final double depthMeters;

  /// Whether this is a high-risk dip (>10m drop).
  final bool isHighRisk;

  /// Distance from route start in meters.
  final double distanceFromStart;

  /// Creates an [ElevationDip].
  ElevationDip({
    required this.point,
    this.depthMeters = 0.0,
    required this.isHighRisk,
    this.distanceFromStart = 0.0,
  });

  Map<String, dynamic> toJson() => {
    'point': {'lat': point.latitude, 'lon': point.longitude},
    'depthMeters': depthMeters,
    'isHighRisk': isHighRisk,
    'distanceFromStart': distanceFromStart,
  };

  factory ElevationDip.fromJson(Map<String, dynamic> json) {
    return ElevationDip(
      point: LatLng(json['point']['lat'], json['point']['lon']),
      depthMeters: (json['depthMeters'] as num).toDouble(),
      isHighRisk: json['isHighRisk'],
      distanceFromStart: (json['distanceFromStart'] as num).toDouble(),
    );
  }
}
