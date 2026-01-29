import 'package:latlong2/latlong.dart';

/// Represents a single turn-by-turn navigation instruction.
class NavigationStep {
  /// The instruction text for this navigation step (e.g., "Turn left on Main St").
  final String instruction;

  /// The type of maneuver (e.g., "turn", "straight", "merge").
  final String maneuverType;

  /// The distance for this step in meters.
  final double distance;

  /// The location of the maneuver in [longitude, latitude] format.
  final List<double> location; // [longitude, latitude]

  /// Creates a [NavigationStep].
  const NavigationStep({
    required this.instruction,
    required this.maneuverType,
    required this.distance,
    required this.location,
  });

  /// Safely parse a route step from OSRM JSON response.
  factory NavigationStep.fromJson(Map<String, dynamic> json) {
    return NavigationStep(
      instruction: (json['instruction']?.toString()) ?? 'Continue',
      maneuverType:
          (json['maneuver'] as Map<String, dynamic>?)?['type']?.toString() ??
              'straight',
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      location: _parseLocation(
          (json['maneuver'] as Map<String, dynamic>?)?['location']),
    );
  }

  /// Parse location coordinates safely from JSON.
  static List<double> _parseLocation(dynamic location) {
    if (location is List && location.length >= 2) {
      return [
        (location[0] as num?)?.toDouble() ?? 0.0,
        (location[1] as num?)?.toDouble() ?? 0.0,
      ];
    }
    return [0.0, 0.0];
  }
}

/// Represents weather information for a specific location and time.
class WeatherAlert {
  /// The geographic coordinates of this weather alert.
  final LatLng point;

  /// The WMO weather code indicating the weather condition.
  final int weatherCode;

  /// Human-readable description of the weather condition.
  final String description;

  /// Temperature in degrees Celsius.
  final double temperature;

  /// The time of this weather observation (HH:MM format).
  final String time;

  /// Creates a [WeatherAlert].
  const WeatherAlert({
    required this.point,
    required this.weatherCode,
    required this.description,
    required this.temperature,
    required this.time,
  });

  /// Parse weather alert from JSON response.
  factory WeatherAlert.fromJson(Map<String, dynamic> json) {
    return WeatherAlert(
      point: json['point'] as LatLng? ?? const LatLng(0, 0),
      weatherCode: json['code'] as int? ?? 0,
      description: json['description']?.toString() ?? 'Unknown',
      temperature: (json['temp'] as num?)?.toDouble() ?? 0.0,
      time: json['time']?.toString() ?? '00:00',
    );
  }
}

/// Represents a complete route with safety analysis and weather information.
class RouteModel {
  /// The ordered list of coordinates that form this route path.
  final List<LatLng> points;

  /// The total distance of this route in meters.
  final double distanceMeters;

  /// The estimated travel time for this route in seconds.
  final double durationSeconds;

  /// The turn-by-turn navigation steps for this route.
  final List<NavigationStep> steps;

  /// Whether rain is detected on any part of this route.
  final bool isRaining;

  /// The safety level of this route ('Safe', 'Medium', or 'High').
  final String riskLevel; // 'Safe', 'Medium', 'High'

  /// Weather alerts detected on this route.
  final List<WeatherAlert> weatherAlerts;

  /// Creates a [RouteModel].
  const RouteModel({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    required this.isRaining,
    required this.riskLevel,
    required this.weatherAlerts,
  });

  /// Safely parse a route from OSRM response.
  factory RouteModel.fromOsrmJson(Map<String, dynamic> json) {
    final geometry = ((json['geometry']
            as Map<String, dynamic>?)?['coordinates'] as List?) ??
        [];
    final List<LatLng> points = geometry
        .map((dynamic c) {
          try {
            final coord = c as List<dynamic>?;
            return LatLng((coord?[1] as num?)?.toDouble() ?? 0.0,
                (coord?[0] as num?)?.toDouble() ?? 0.0);
          } catch (_) {
            return const LatLng(0, 0);
          }
        })
        .cast<LatLng>()
        .toList();

    final distance = (json['distance'] as num?)?.toDouble() ?? 0.0;
    final duration = (json['duration'] as num?)?.toDouble() ?? 0.0;

    final stepsJson = (((json['legs'] as List<dynamic>?)?[0]
            as Map<String, dynamic>?)?['steps'] as List?) ??
        [];
    final steps = stepsJson
        .map((dynamic step) =>
            NavigationStep.fromJson(step as Map<String, dynamic>))
        .toList();

    return RouteModel(
      points: points,
      distanceMeters: distance,
      durationSeconds: duration,
      steps: steps,
      isRaining: false,
      riskLevel: 'Unknown',
      weatherAlerts: [],
    );
  }

  /// Create a copy with weather analysis results.
  RouteModel copyWithWeather({
    required bool isRaining,
    required String riskLevel,
    required List<WeatherAlert> weatherAlerts,
  }) {
    return RouteModel(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      steps: steps,
      isRaining: isRaining,
      riskLevel: riskLevel,
      weatherAlerts: weatherAlerts,
    );
  }

  /// Get distance in kilometers (formatted).
  String get distanceKm => '${(distanceMeters / 1000).toStringAsFixed(1)} km';

  /// Get duration in minutes (formatted).
  int get durationMinutes => (durationSeconds / 60).round();

  /// Get risk color based on level.
  String get riskColor {
    if (riskLevel == 'High') return 'Red';
    if (riskLevel == 'Medium') return 'Orange';
    return 'Green';
  }
}

/// Represents geocoding result for address search.
class GeocodingResult {
  /// The geographic coordinates of this location.
  final LatLng coordinates;

  /// The full display name of this location.
  final String displayName;

  /// Creates a [GeocodingResult].
  const GeocodingResult({
    required this.coordinates,
    required this.displayName,
  });

  /// Parse geocoding result from Nominatim API JSON response.
  factory GeocodingResult.fromNominatimJson(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0;
    final lon = double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0;
    final displayName = json['display_name']?.toString() ?? 'Unknown Location';

    return GeocodingResult(
      coordinates: LatLng(lat, lon),
      displayName: displayName,
    );
  }
}

/// Represents a hazard report from a user.
class HazardReport {
  /// The geographic location of this hazard.
  final LatLng location;

  /// The type of hazard ('Waterlogging', 'Accident', or 'RoadBlock').
  final String hazardType; // 'Waterlogging', 'Accident', 'RoadBlock'

  /// The time when this hazard was reported.
  final DateTime timestamp;

  /// Creates a [HazardReport].
  const HazardReport({
    required this.location,
    required this.hazardType,
    required this.timestamp,
  });

  /// Convert to JSON for API submission.
  Map<String, dynamic> toJson() {
    return {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'hazardType': hazardType,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
