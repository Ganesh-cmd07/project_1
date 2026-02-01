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
final Map<String, List<double>> _elevationCache = {};

DateTime? _lastNominatimCall;

/// Service for all backend API integration and weather analysis.
/// Handles route calculation, geocoding, weather forecasting, hazard reporting,
/// elevation analysis, and vehicle-specific risk assessment.
/// 
/// Enhanced with:
/// - Weather validation for hazard reports (sensor cross-check)
/// - ENGLISH FALLBACK for location names
class ApiService {
  static const String _tag = 'ApiService';

  // ==========================================
  // HTTP Headers with Strict English Support
  // ==========================================
  /// ENGLISH FALLBACK: These headers ensure all API responses default to English,
  /// making the app usable by tourists and non-local residents.
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
  /// 
  /// ENGLISH FALLBACK: All API responses are in English for accessibility.
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

  /// Fetches place suggestions from Nominatim API.
  /// 
  /// ENGLISH FALLBACK: Uses English headers to ensure results are readable.
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
  // 2. GPS & LOCATION SERVICES (UPDATED FOR GEOLOCATOR V14)
  // ==========================================

  /// Get current GPS location with permission handling.
  /// 
  /// UPDATED: Now uses LocationSettings (Geolocator v14+ requirement)
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      ErrorHandler.logError(_tag, 'getCurrentLocation error: $e');
      return null;
    }
  }

  /// Get continuous position stream for live tracking.
  /// 
  /// THERMAL/BATTERY GUARD: Distance filter can be adjusted dynamically
  /// to reduce battery drain and heat on long straightaways.
  /// 
  /// UPDATED: Now uses LocationSettings (Geolocator v14+ requirement)
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
  /// 
  /// ENGLISH FALLBACK: Searches with English language preference.
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

  /// Searches Nominatim API for coordinates.
  /// 
  /// ENGLISH FALLBACK: Uses English headers for consistent results.
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

  /// Enforces rate limiting for Nominatim API calls.
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
  // 4. ELEVATION ANALYSIS ("Dip" Predictor)
  // ==========================================

  /// Get elevation data for a list of points using Open-Elevation API.
  Future<List<double>> getElevationData(List<LatLng> points) async {
    try {
      // Sample points to reduce API calls (max 100 points per request)
      final sampledPoints = _sampleRoutePoints(points, samples: 50);
      
      final cacheKey = sampledPoints.map((p) => '${p.latitude.toStringAsFixed(3)},${p.longitude.toStringAsFixed(3)}').join('|');
      
      if (_elevationCache.containsKey(cacheKey)) {
        return _elevationCache[cacheKey]!;
      }

      // Build request body
      final locations = sampledPoints.map((p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
      }).toList();

      final url = Uri.parse('https://api.open-elevation.com/api/v1/lookup');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'locations': locations}),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>?) ?? [];
        
        final elevations = results.map((e) => ((e as Map<String, dynamic>)['elevation'] as num).toDouble()).toList();
        
        _elevationCache[cacheKey] = elevations;
        return elevations;
      }
    } catch (e) {
      ErrorHandler.logError(_tag, 'Elevation API error: $e');
    }
    return [];
  }

  /// Detect elevation dips along the route (potential waterlogging zones).
  Future<List<ElevationDip>> detectElevationDips(List<LatLng> routePoints) async {
    try {
      final elevations = await getElevationData(routePoints);
      
      if (elevations.length < 3) return [];

      final List<ElevationDip> dips = [];
      final sampledPoints = _sampleRoutePoints(routePoints, samples: elevations.length);

      // Sliding window to detect local minima
      for (int i = 1; i < elevations.length - 1; i++) {
        final current = elevations[i];
        final prev = elevations[i - 1];
        final next = elevations[i + 1];

        // Check if current point is lower than both neighbors
        if (current < prev && current < next) {
          final drop = ((prev + next) / 2) - current;
          
          // Flag as dip if drop is > 5 meters
          if (drop >= 5.0) {
            const distanceCalc = Distance();
            final distFromStart = distanceCalc.as(
              LengthUnit.Meter,
              routePoints.first,
              sampledPoints[i],
            );

            dips.add(ElevationDip(
              point: sampledPoints[i],
              depthMeters: drop,
              isHighRisk: drop >= 10.0, // Critical dip
              distanceFromStart: distFromStart,
            ));
          }
        }
      }

      return dips;
    } catch (e) {
      ErrorHandler.logError(_tag, 'Dip detection error: $e');
      return [];
    }
  }

  // ==========================================
  // 5. WEATHER API ENDPOINTS
  // ==========================================

  /// Gets current weather at a specific location.
  /// 
  /// SENSOR CROSS-CHECK: Used to validate hazard reports against real weather data.
  /// Returns weather code, temperature, and rain intensity.
  Future<Map<String, dynamic>?> getWeatherAtLocation(LatLng location) async {
    try {
      final url = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&hourly=weathercode,temperature_2m,rain&timezone=auto');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 10),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final currentWeather = data['current_weather'] as Map<String, dynamic>?;
        final hourly = data['hourly'] as Map<String, dynamic>?;

        if (currentWeather == null || hourly == null) return null;

        // Get current hour's rain data
        final now = DateTime.now();
        final times = hourly['time'] as List<dynamic>? ?? [];
        final rains = hourly['rain'] as List<dynamic>? ?? [];
        
        double currentRain = 0.0;
        final currentHourStr = now.toIso8601String().substring(0, 13);
        
        for (int i = 0; i < times.length; i++) {
          if (times[i].toString().startsWith(currentHourStr)) {
            currentRain = (rains[i] as num?)?.toDouble() ?? 0.0;
            break;
          }
        }

        return {
          'weathercode': currentWeather['weathercode'] as int,
          'temperature_2m': currentWeather['temperature'] as double,
          'rain': currentRain,
        };
      }
    } catch (e) {
      ErrorHandler.logError(_tag, 'Weather API error: $e');
    }
    return null;
  }

  // ==========================================
  // 6. VEHICLE-SPECIFIC ROUTE LOGIC
  // ==========================================

  /// Get multiple routes with vehicle-specific analysis.
  Future<List<RouteModel>> getSafeRoutesOptions(
    LatLng start,
    LatLng end, {
    VehicleType vehicleType = VehicleType.bike,
  }) async {
    try {
      // 1. Check for ocean barriers
      const Distance distanceCalc = Distance();
      final airDistance = distanceCalc.as(LengthUnit.Kilometer, start, end);

      if (airDistance > 2000) {
        throw Exception('Ocean/Continental barrier detected. Road route unavailable.');
      }

      // 2. Get multiple geometries from OSRM
      final List<RouteModel> rawRoutes = await _getOsrmRoutesWithAlternatives(start, end);

      if (rawRoutes.isEmpty) {
        throw Exception('No routes found from OSRM');
      }

      // 3. Analyze each route
      final List<RouteModel> analyzedRoutes = [];
      
      for (final route in rawRoutes) {
        // Weather analysis
        final RouteModel withWeather = await _analyzeRouteWeather(route, vehicleType);
        
        // Elevation analysis (detect dips)
        final dips = await detectElevationDips(route.points);
        
        // Vehicle-specific checks
        bool hydroplaning = false;
        if (vehicleType == VehicleType.truck || vehicleType == VehicleType.car) {
          // Check for high-speed segments in rain
          if (withWeather.isRaining && route.distanceMeters > 5000) {
            hydroplaning = true;
          }
        }

        // Combine all analysis
        final analyzed = withWeather.copyWithWeather(
          isRaining: withWeather.isRaining,
          riskLevel: _calculateVehicleRisk(withWeather, vehicleType, dips),
          weatherAlerts: withWeather.weatherAlerts,
          elevationDips: dips,
          hydroplaningRisk: hydroplaning,
        );

        analyzedRoutes.add(analyzed);
      }

      // 4. SORT: Prioritize Safety, then Speed
      analyzedRoutes.sort((a, b) {
        final aSafe = a.riskLevel == 'Safe';
        final bSafe = b.riskLevel == 'Safe';

        if (aSafe && !bSafe) return -1;
        if (!aSafe && bSafe) return 1;
        return a.durationSeconds.compareTo(b.durationSeconds);
      });

      return analyzedRoutes;
    } catch (e) {
      ErrorHandler.logError(_tag, 'getSafeRoutesOptions error: $e');
      rethrow;
    }
  }

  /// Calculates vehicle-specific risk level based on weather, dips, and road conditions.
  String _calculateVehicleRisk(
    RouteModel route,
    VehicleType vehicleType,
    List<ElevationDip> dips,
  ) {
    // Check dips first
    final criticalDips = dips.where((d) => d.isHighRisk).toList();
    
    if (route.isRaining && criticalDips.isNotEmpty) {
      return 'High'; // Rain + Dips = Waterlogging risk
    }

    // Vehicle-specific rain thresholds
    if (route.isRaining) {
      // Check if rain exceeds vehicle threshold
      final maxRainIntensity = route.weatherAlerts
          .map((a) => a.rainIntensity ?? 0)
          .fold(0.0, (a, b) => a > b ? a : b);

      if (maxRainIntensity >= vehicleType.rainThreshold) {
        return 'High';
      } else if (maxRainIntensity > vehicleType.rainThreshold * 0.5) {
        return 'Medium';
      }
    }

    // Truck-specific checks
    if (vehicleType == VehicleType.truck) {
      if (route.hasUnpavedRoads && route.isRaining) {
        return 'High'; // Soft ground risk
      }
    }

    return 'Safe';
  }

  /// Gets multiple route alternatives from OSRM API.
  /// 
  /// POLYLINE SNAP FIX: Routes use exact OSRM geometry to prevent GPS offset.
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

  /// Analyze route for weather hazards with vehicle-specific thresholds.
  Future<RouteModel> _analyzeRouteWeather(
    RouteModel route,
    VehicleType vehicleType,
  ) async {
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
          final rainIntensity = weather['rain'] as double? ?? 0.0;

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
                rainIntensity: rainIntensity,
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
      return route.copyWithWeather(
        isRaining: false,
        riskLevel: 'Unknown',
        weatherAlerts: [],
      );
    }
  }

  /// Samples route points to reduce API calls.
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
          'https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&hourly=weathercode,temperature_2m,rain&timezone=auto');

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
          'rain': ((hourly?['rain'] as List<dynamic>?)?[targetIndex] ?? 0.0) as double,
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
  /// 
  /// ENGLISH FALLBACK: All descriptions are in English for accessibility.
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
  // 7. INPUT VALIDATION
  // ==========================================

  /// Validates if a string is a valid location input.
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

  // ==========================================
  // 8. OFFLINE ROUTE PERSISTENCE
  // ==========================================

  /// Save the active route to local storage.
  /// 
  /// OFFLINE MODE: Enables route restoration if app crashes or restarts.
  Future<void> saveActiveRoute(RouteModel route) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = json.encode(route.toJson());
      await prefs.setString('active_route_data', jsonStr);
      await prefs.setString('active_route_timestamp', DateTime.now().toIso8601String());
      ErrorHandler.logInfo(_tag, 'Route saved to local storage');
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to save route: $e');
    }
  }

  /// Retrieve the saved route from local storage.
  /// 
  /// Returns null if no route exists or it's older than 4 hours (TTL).
  Future<RouteModel?> getSavedRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('active_route_data');
      final timestampStr = prefs.getString('active_route_timestamp');

      if (jsonStr == null || timestampStr == null) return null;

      // check TTL (4 hours)
      final timestamp = DateTime.parse(timestampStr);
      if (DateTime.now().difference(timestamp).inHours > 4) {
        await clearSavedRoute();
        return null;
      }

      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return RouteModel.fromJson(data);
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to restore route: $e');
      return null;
    }
  }

  /// Clear the saved route from local storage.
  Future<void> clearSavedRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_route_data');
      await prefs.remove('active_route_timestamp');
      ErrorHandler.logError(_tag, 'Saved route cleared');
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to clear saved route: $e');
    }
  }
}