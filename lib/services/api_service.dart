import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/route_model.dart';
import '../utils/error_handler.dart';

// ==========================================
// GLOBAL CACHES (Prevent API Rate Limiting)
// ==========================================
final Map<String, LatLng> _coordinateCache = {};
final Map<String, List<String>> _suggestionsCache = {};
final Map<String, dynamic> _weatherCache = {};

DateTime? _lastNominatimCall;

/// Service for all backend API integration and weather analysis.
/// Handles route calculation, geocoding, weather forecasting, and hazard reporting.
/// Uses caching to optimize API calls and reduce rate limiting.
class ApiService {
  static const String _tag = 'ApiService';

  // ==========================================
  // HTTP Headers with Strict English Support
  // ==========================================
  static const Map<String, String> _englishHeaders = {
    'User-Agent': 'RainSafeNavigator/2.0',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept': 'application/json',
  };

  // ==========================================
  // 1. SEARCH HISTORY & SUGGESTIONS
  // ==========================================

  /// Saves a successful search query to local phone storage.
  Future<void> addToHistory(String query) async {
    if (query.trim().isEmpty || query == 'Current Location') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> history = prefs.getStringList('search_history') ?? [];

      // Remove duplicates and keep only latest 10
      history.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
      history.insert(0, query);
      if (history.length > 10) {
        history.removeRange(10, history.length);
      }

      await prefs.setStringList('search_history', history);
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to save to history: $e');
    }
  }

  /// Gets suggestions: First checks History, then API.
  Future<List<String>> getPlaceSuggestions(String query) async {
    final List<String> results = [];

    try {
      // 1. Get History Matches First
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('search_history') ?? [];

      if (query.isEmpty) {
        return history; // Return full history if box is empty
      }

      // Filter history based on typing
      final historyMatches = history
          .where((h) => h.toLowerCase().contains(query.toLowerCase()))
          .toList();
      results.addAll(historyMatches);

      // 2. If query is long enough, fetch from API
      if (query.length >= 3) {
        if (_suggestionsCache.containsKey(query)) {
          results.addAll(_suggestionsCache[query]!);
        } else {
          final apiResults = await _fetchNominatimSuggestions(query);
          results.addAll(apiResults);
        }
      }

      // Remove duplicates and return
      return results.toSet().toList();
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to get suggestions: $e');
      return [];
    }
  }

  Future<List<String>> _fetchNominatimSuggestions(String query) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5&countrycodes=in');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        final List<String> results = data
            .map<String>((dynamic item) =>
                ((item as Map<String, dynamic>?)?['display_name'] as String?) ??
                'Unknown')
            .toList();

        _suggestionsCache[query] = results;
        return results;
      }
    } catch (e) {
      ErrorHandler.logError(_tag, 'Nominatim suggestion error: $e');
    }
    return [];
  }

  // ==========================================
  // 2. GPS & LOCATION SERVICES
  // ==========================================

  /// Get current GPS location with permission handling.
  Future<LatLng?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ErrorHandler.logError(_tag, 'Location service is disabled');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ErrorHandler.logError(_tag, 'Location permission denied');
          return null;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      ErrorHandler.logError(_tag, 'getCurrentLocation error: $e');
      return null;
    }
  }

  /// Get continuous position stream for live tracking.
  Stream<LatLng> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
        .map((pos) => LatLng(pos.latitude, pos.longitude))
        .handleError((e) {
      ErrorHandler.logError(_tag, 'Position stream error: $e');
    });
  }

  // ==========================================
  // 3. GEOCODING (with Type Safety)
  // ==========================================

  /// Convert address string to coordinates.
  Future<LatLng?> getCoordinates(String cityName) async {
    if (!_isValidLocationString(cityName)) return null;

    try {
      // 1. Exact Search
      LatLng? result = await _searchNominatim(cityName);
      if (result != null) return result;

      // 2. Append Country
      if (!cityName.toLowerCase().contains('india')) {
        result = await _searchNominatim('$cityName, India');
        if (result != null) return result;
      }

      // 3. Recursive Split (Safety net for bad formatting)
      if (cityName.contains(',')) {
        final parts = cityName.split(',').map((p) => p.trim()).toList();
        for (int i = 0; i < parts.length - 1; i++) {
          final query = parts.sublist(i).join(', ');
          result = await _searchNominatim(query);
          if (result != null) return result;
        }
      }

      return null;
    } catch (e) {
      ErrorHandler.logError(_tag, 'getCoordinates error: $e');
      return null;
    }
  }

  Future<LatLng?> _searchNominatim(String query) async {
    try {
      if (_coordinateCache.containsKey(query)) {
        return _coordinateCache[query];
      }

      await _rateLimitNominatim();

      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&accept-language=en&addressdetails=1');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 10),
          );

      _lastNominatimCall = DateTime.now();

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List<dynamic>?;
        if (data != null && data.isNotEmpty) {
          try {
            final firstItem = data[0] as Map<String, dynamic>?;
            final lat = double.parse((firstItem?['lat'] ?? '0').toString());
            final lon = double.parse((firstItem?['lon'] ?? '0').toString());
            final result = LatLng(lat, lon);
            _coordinateCache[query] = result;
            return result;
          } catch (e) {
            ErrorHandler.logError(_tag, 'Failed to parse coordinates: $e');
          }
        }
      }
    } catch (e) {
      ErrorHandler.logError(_tag, '_searchNominatim error: $e');
    }
    return null;
  }

  Future<void> _rateLimitNominatim() async {
    if (_lastNominatimCall != null) {
      final diff =
          DateTime.now().difference(_lastNominatimCall!).inMilliseconds;
      if (diff < 1200) {
        await Future.delayed(Duration(milliseconds: 1200 - diff));
      }
    }
  }

  // ==========================================
  // 4. MULTI-ROUTE & SAFE ROUTE LOGIC
  // ==========================================

  /// Get multiple routes with weather analysis and safety scoring.
  Future<List<RouteModel>> getSafeRoutesOptions(
      LatLng start, LatLng end) async {
    try {
      // 1. Get multiple geometries from OSRM
      final List<RouteModel> rawRoutes =
          await _getOsrmRoutesWithAlternatives(start, end);

      if (rawRoutes.isEmpty) {
        throw Exception('No routes found from OSRM');
      }

      // 2. Analyze weather for EACH route
      final List<RouteModel> analyzedRoutes = [];
      for (final route in rawRoutes) {
        final analyzed = await _analyzeRouteWeather(route);
        analyzedRoutes.add(analyzed);
      }

      // 3. SORT: Prioritize Safety, then Speed
      analyzedRoutes.sort((a, b) {
        final aSafe = a.riskLevel == 'Safe';
        final bSafe = b.riskLevel == 'Safe';

        if (aSafe && !bSafe) return -1; // A comes first
        if (!aSafe && bSafe) return 1; // B comes first
        return a.durationSeconds.compareTo(b.durationSeconds);
      });

      return analyzedRoutes;
    } catch (e) {
      ErrorHandler.logError(_tag, 'getSafeRoutesOptions error: $e');
      rethrow;
    }
  }

  Future<List<RouteModel>> _getOsrmRoutesWithAlternatives(
    LatLng start,
    LatLng end,
  ) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson&alternatives=true&steps=true');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? [];

        if (routes.isEmpty) {
          throw Exception('No routes found');
        }

        return routes
            .map((route) =>
                RouteModel.fromOsrmJson(route as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('OSRM returned status ${response.statusCode}');
      }
    } catch (e) {
      ErrorHandler.logError(_tag, '_getOsrmRoutesWithAlternatives error: $e');
      rethrow;
    }
  }

  /// Analyze route for weather hazards.
  Future<RouteModel> _analyzeRouteWeather(RouteModel route) async {
    try {
      final checkPoints = _sampleRoutePoints(route.points, samples: 8);
      var rainDetected = false;
      final List<WeatherAlert> weatherAlerts = [];
      final now = DateTime.now();

      for (int i = 0; i < checkPoints.length; i++) {
        final point = checkPoints[i];
        final progressPercent = i / (checkPoints.length - 1);
        final secondsToPoint =
            (route.durationSeconds * progressPercent).round();
        final arrivalTime = now.add(Duration(seconds: secondsToPoint));

        final weather = await _getCachedWeatherForecast(point, arrivalTime);

        if (weather != null) {
          final code = weather['weathercode'] as int? ?? 0;

          if (_isRainyCode(code)) {
            rainDetected = true;
            weatherAlerts.add(
              WeatherAlert(
                point: point,
                weatherCode: code,
                description: getWeatherDescription(code),
                temperature:
                    (weather['temperature_2m'] as num?)?.toDouble() ?? 0.0,
                time:
                    '${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}',
              ),
            );
          }
        }
      }

      final riskLevel = rainDetected ? 'High' : 'Safe';
      return route.copyWithWeather(
        isRaining: rainDetected,
        riskLevel: riskLevel,
        weatherAlerts: weatherAlerts,
      );
    } catch (e) {
      ErrorHandler.logError(_tag, '_analyzeRouteWeather error: $e');
      // Return with Unknown risk on error
      return route.copyWithWeather(
        isRaining: false,
        riskLevel: 'Unknown',
        weatherAlerts: [],
      );
    }
  }

  List<LatLng> _sampleRoutePoints(List<LatLng> path, {int samples = 5}) {
    if (path.isEmpty) return [];
    if (path.length <= samples) return path;

    final List<LatLng> result = [];
    final int step = (path.length / samples).floor();

    for (int i = 0; i < path.length; i += step) {
      result.add(path[i]);
    }

    if (result.isEmpty || result.last != path.last) {
      result.add(path.last);
    }
    return result;
  }

  /// Get cached weather forecast with API fallback.
  Future<Map<String, dynamic>?> _getCachedWeatherForecast(
    LatLng point,
    DateTime time,
  ) async {
    try {
      final key =
          '${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)},${time.hour}';

      if (_weatherCache.containsKey(key)) {
        return _weatherCache[key];
      }

      await Future.delayed(const Duration(milliseconds: 150));

      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&hourly=weathercode,temperature_2m&timezone=auto');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final times = (data['hourly'] as Map<String, dynamic>?)?['time']
                as List<dynamic>? ??
            [];
        var targetIndex = 0;

        final targetIso = time.toIso8601String().substring(0, 13);

        for (int i = 0; i < times.length; i++) {
          if (times[i].toString().startsWith(targetIso)) {
            targetIndex = i;
            break;
          }
        }

        final hourly = data['hourly'] as Map<String, dynamic>?;
        final result = <String, dynamic>{
          'weathercode':
              ((hourly?['weathercode'] as List<dynamic>?)?[targetIndex] ?? 0)
                  as int,
          'temperature_2m':
              ((hourly?['temperature_2m'] as List<dynamic>?)?[targetIndex] ??
                  0.0) as double,
        };

        _weatherCache[key] = result;
        return result;
      }
    } catch (e) {
      ErrorHandler.logError(_tag, 'Weather forecast error: $e');
    }
    return null;
  }

  /// Check if weather code indicates rain.
  bool _isRainyCode(int code) {
    return (code >= 51 && code <= 67) ||
        (code >= 80 && code <= 82) ||
        (code >= 95 && code <= 99);
  }

  /// Get human-readable weather description from WMO code.
  String getWeatherDescription(int weatherCode) {
    if (weatherCode == 0) return 'Clear sky';
    if (weatherCode >= 1 && weatherCode <= 3) return 'Cloudy';
    if (weatherCode >= 45 && weatherCode <= 48) return 'Fog';
    if (weatherCode >= 51 && weatherCode <= 55) return '🌧️ Drizzle';
    if (weatherCode >= 56 && weatherCode <= 57) return '❄️ Freezing Drizzle';
    if (weatherCode >= 61 && weatherCode <= 65) return '🌧️ Rain';
    if (weatherCode >= 66 && weatherCode <= 67) return '❄️ Freezing Rain';
    if (weatherCode >= 71 && weatherCode <= 77) return '❄️ Snow';
    if (weatherCode >= 80 && weatherCode <= 82) return '🌧️ Heavy Showers';
    if (weatherCode >= 85 && weatherCode <= 86) return '❄️ Snow Showers';
    if (weatherCode >= 95 && weatherCode <= 99) return '⛈️ Thunderstorm';
    return 'Unknown';
  }

  // ==========================================
  // 5. INPUT VALIDATION (GROUND STANDARDS)
  // ==========================================

  /// Validate location input against problematic terms.
  bool _isValidLocationString(String? input) {
    if (input == null || input.trim().isEmpty) return false;

    final lowerInput = input.trim().toLowerCase();

    const invalidTerms = [
      'rain',
      'sunny',
      'cloudy',
      'weather',
      'null',
      'undefined',
      'unknown location',
    ];

    return !invalidTerms.contains(lowerInput);
  }
}
