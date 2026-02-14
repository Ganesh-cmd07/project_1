import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../models/route_model.dart';
import '../utils/error_handler.dart';

// ==========================================
// SEARCH RESULT MODEL
// ==========================================
class SearchResult {
  final String name;
  final String address; // City, State, Country
  final String fullText; // For searching/displaying
  final LatLng? location; // coordinates for distance sorting

  SearchResult({
    required this.name,
    required this.address,
    this.location,
  }) : fullText = "$name, $address";

  @override
  String toString() => fullText;
  
  // Calculate distance in meters from a reference point
  double distanceTo(LatLng point) {
    if (location == null) return double.infinity;
    const Distance distance = Distance();
    return distance.as(LengthUnit.Meter, location!, point);
  }
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          runtimeType == other.runtimeType &&
          fullText == other.fullText;

  @override
  int get hashCode => fullText.hashCode;
}

// ==========================================
// GLOBAL CACHES (Prevent API Rate Limiting)
// ==========================================
final Map<String, LatLng> _coordinateCache = {};
final Map<String, List<SearchResult>> _suggestionsCache = {}; // UPDATED CACHE TYPE
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

  /// Retrieves search history from local storage.
  Future<List<String>> getSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('search_history') ?? [];
    } catch (e) {
      ErrorHandler.logError(_tag, 'Failed to get history: $e');
      return [];
    }
  }



  Timer? _debounceTimer;

  /// Gets suggestions: First checks History, then API (Debounced).
  /// 
  /// ENGLISH FALLBACK: All API responses are in English for accessibility.
  /// Gets suggestions: First checks History, then API (Debounced).
  /// 
  /// ENGLISH FALLBACK: All API responses are in English for accessibility.
  /// PROXIMITY BIAS: Fetches current location to prioritize nearby results.
  /// Gets suggestions: First checks History, then API (Debounced).
  /// 
  /// ENGLISH FALLBACK: All API responses are in English for accessibility.
  /// PROXIMITY BIAS: Fetches current location to prioritize nearby results.
  Future<List<SearchResult>> getPlaceSuggestions(String query) async {
    final List<SearchResult> results = [];

    try {
      // 1. Get History Matches First
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('search_history') ?? [];

      print("DEBUG: Searching for '$query'"); // DEBUG LOG

      if (query.isEmpty) {
        // Convert history strings to SearchResult objects
        return history.map((h) => SearchResult(name: h, address: 'Recent Search')).toList();
      }

      // Filter history based on typing
      final historyMatches = history
          .where((h) => h.toLowerCase().contains(query.toLowerCase()))
          .map((h) => SearchResult(name: h, address: 'Recent Search'))
          .toList();
      results.addAll(historyMatches);

      // 2. API Fetch with Debounce
      if (query.length >= 3) {
        if (_suggestionsCache.containsKey(query)) {
          results.addAll(_suggestionsCache[query]!);
        } else {
             // Get user location for proximity bias (Fast check)
          LatLng? userLocation;
          try {
             final pos = await Geolocator.getLastKnownPosition();
             if (pos != null) userLocation = LatLng(pos.latitude, pos.longitude);
          } catch (_) {} // Ignore location errors for search

          // Better approach: Just call Photon. It handles high throughput better.
          List<SearchResult> apiResults = await _fetchPhotonSuggestions(query, userLocation);
          
          if (apiResults.isEmpty) {
             print("DEBUG: Photon returned empty, trying Nominatim...");
             apiResults = await _fetchNominatimSuggestions(query);
          }
          
          // SORT BY DISTANCE (Client-side refinement)
          if (userLocation != null) {
              apiResults.sort((a, b) {
                  final distA = a.distanceTo(userLocation!);
                  final distB = b.distanceTo(userLocation!);
                  return distA.compareTo(distB);
              });
          }
          
          results.addAll(apiResults);
        }
      }

      print("DEBUG: Found ${results.length} results"); // DEBUG LOG
      return results.toSet().toList();
    } catch (e) {
      print("DEBUG: Error - $e"); // DEBUG LOG
      ErrorHandler.logError(_tag, 'Failed to get suggestions: $e');
      return [];
    }
  }

  /// Fetches place suggestions from Photon API (Faster/Better for Autocomplete).
  /// Uses [location] to bias results towards the user.
  Future<List<SearchResult>> _fetchPhotonSuggestions(String query, LatLng? location) async {
     try {
       // Photon API is excellent for autocomplete 'type-ahead'
       String urlStr = 'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=5';
       
       // ADD LOCATION BIAS
       if (location != null) {
         urlStr += '&lat=${location.latitude}&lon=${location.longitude}';
       }

       final url = Uri.parse(urlStr);
       
       final response = await http.get(url).timeout(const Duration(seconds: 15));

       if (response.statusCode == 200) {
         final data = json.decode(response.body) as Map<String, dynamic>;
         final features = data['features'] as List<dynamic>;
         
         final List<SearchResult> results = features.map<SearchResult?>((f) {
            final props = f['properties'] as Map<String, dynamic>;
            final geometry = f['geometry'] as Map<String, dynamic>?;
            
            final name = props['name'] as String?;
            
            // Extract Coordinates
            LatLng? coord;
            if (geometry != null && geometry['coordinates'] != null) {
                final coords = geometry['coordinates'] as List<dynamic>;
                if (coords.length >= 2) {
                   // GeoJSON is [lon, lat]
                   coord = LatLng(coords[1].toDouble(), coords[0].toDouble());
                }
            }

            // Construct address
            final List<String> addressParts = [];
            if (props['street'] != null) addressParts.add(props['street']);
            if (props['city'] != null) addressParts.add(props['city']);
            if (props['state'] != null) addressParts.add(props['state']);
            if (props['country'] != null) addressParts.add(props['country']);
            
            final address = addressParts.join(', ');
            
            if (name == null) return null;
            return SearchResult(name: name, address: address.isEmpty ? 'Unknown Location' : address, location: coord);
         }).whereType<SearchResult>().toList();

         _suggestionsCache[query] = results;
         return results;
       }
     } catch (e) {
        ErrorHandler.logError(_tag, 'Photon API error: $e');
        // Fallback to Nominatim if Photon fails
        return await _fetchNominatimSuggestions(query);
     }
     return [];
  }

  /// Fetches place suggestions from Nominatim API.
  /// 
  /// ENGLISH FALLBACK: Uses English headers to ensure results are readable.
  Future<List<SearchResult>> _fetchNominatimSuggestions(String query) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5&countrycodes=in');
 
      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 20),
          );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        
        final List<SearchResult> results = data.map<SearchResult?>((dynamic item) {
             final map = item as Map<String, dynamic>?;
             if (map == null) return null;
             
             final displayName = map['display_name'] as String?;
             if (displayName == null) return null;
             
             // Extract Coordinates
             LatLng? coord;
             if (map['lat'] != null && map['lon'] != null) {
                 coord = LatLng(double.parse(map['lat']), double.parse(map['lon']));
             }

             // Nominatim returns a comma-separated string.
             final parts = displayName.split(',');
             final name = parts.isNotEmpty ? parts.first.trim() : displayName;
             final address = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
             
             return SearchResult(name: name, address: address, location: coord);
        }).whereType<SearchResult>().toList();

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
  
  /// Get full position stream including bearing/heading.
  Stream<Position> getFullPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
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
      if (_coordinateCache.containsKey(cityName)) {
        return _coordinateCache[cityName];
      }

      // 1. Try Photon (Faster & Fuzzier)
      try {
        final photonResults = await _fetchPhotonSuggestions(cityName, null);
        if (photonResults.isNotEmpty && photonResults.first.location != null) {
          final loc = photonResults.first.location!;
          _coordinateCache[cityName] = loc;
          return loc;
        }
      } catch (e) {
        ErrorHandler.logError(_tag, 'Photon getCoordinates error: $e');
      }

      // 2. Exact Search (Nominatim)
      LatLng? result = await _searchNominatim(cityName);
      if (result != null) return result;

      // 3. Append Country (Nominatim)
      if (!cityName.toLowerCase().contains('india')) {
        result = await _searchNominatim('$cityName, India');
        if (result != null) return result;
      }

      // 4. Recursive Split (Safety net for bad formatting)
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
            const Duration(seconds: 20),
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
      ).timeout(const Duration(seconds: 30));

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
            const Duration(seconds: 20),
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

Future<List<RouteModel>> getSafeRoutesOptions(
  LatLng start,
  LatLng end, {
  VehicleType vehicleType = VehicleType.bike,
}) async {
  try {
    // 1. Ocean barrier check
    const Distance distanceCalc = Distance();
    final airDistance = distanceCalc.as(LengthUnit.Kilometer, start, end);

    if (airDistance > 2000) {
      throw Exception('Ocean/Continental barrier detected. Road route unavailable.');
    }

    // 2. MULTI-PROFILE STRATEGY: Fetch from different networks
    List<String> profilesToFetch = ['driving'];
    
    if (vehicleType == VehicleType.bike) {
      // Bikes can use all networks
      profilesToFetch = ['cycling', 'driving', 'walking'];
    } else if (vehicleType == VehicleType.car || vehicleType == VehicleType.truck) {
      // Cars limited to driving
      profilesToFetch = ['driving'];
    }

    print("🚗 Fetching routes for ${vehicleType.displayName}");
    print("   Profiles: $profilesToFetch");

    // 3. Fetch ALL profiles in PARALLEL (faster)
    final futures = profilesToFetch.map((profile) async {
      try {
        return await _getOsrmRoutesWithAlternatives(
          start,
          end,
          profile: profile,
        );
      } catch (e) {
        ErrorHandler.logError(_tag, 'Failed to fetch $profile routes: $e');
        return <RouteModel>[];
      }
    });

    final results = await Future.wait(futures);
    
    // 4. Combine all routes
    List<RouteModel> allRawRoutes = [];
    for (final routes in results) {
      allRawRoutes.addAll(routes);
    }

    if (allRawRoutes.isEmpty) {
      throw Exception('No routes found from OSRM');
    }

    print("📊 Found ${allRawRoutes.length} raw routes");

    // 5. GEOMETRIC DEDUPLICATION
    final List<RouteModel> uniqueRoutes = _deduplicateRoutes(allRawRoutes);
    
    print("✅ After deduplication: ${uniqueRoutes.length} unique routes");

    // 6. FORCE ALTERNATIVE if only 1 route
    if (uniqueRoutes.length == 1) {
      print("⚠️ Only 1 route found, forcing alternative...");
      
      final alternative = await _forceAlternativeRoute(
        uniqueRoutes.first,
        start,
        end,
        vehicleType,
      );
      
      if (alternative != null) {
        uniqueRoutes.add(alternative);
        print("✅ Forced alternative generated");
      } else {
        print("⚠️ Could not generate forced alternative");
      }
    }

    // 7. Analyze all routes IN PARALLEL for speed
    final analyzedFutures = uniqueRoutes.map((route) async {
      // Weather & Elevation in parallel
      final weatherFuture = _analyzeRouteWeather(route, vehicleType);
      final elevationFuture = detectElevationDips(route.points);
      
      final results = await Future.wait([weatherFuture, elevationFuture]);
      final withWeather = results[0] as RouteModel;
      var dips = results[1] as List<ElevationDip>;
      
      // LEVEL 2 ACCURACY: Inject real-time rain data into dips
      if (withWeather.isRaining) {
        // Find max rain intensity along the route
        final double maxRain = withWeather.weatherAlerts
            .map((a) => a.rainIntensity ?? 0.0)
            .fold(0.0, (prev, curr) => prev > curr ? prev : curr);
            
        // Update all dips with this intensity
        if (maxRain > 0) {
          dips = dips.map((d) => d.copyWith(rainIntensity: maxRain)).toList();
        }
      }
      
      // Vehicle-specific checks
      bool hydroplaning = false;
      if (vehicleType == VehicleType.truck || vehicleType == VehicleType.car) {
        if (withWeather.isRaining && route.distanceMeters > 5000) {
          hydroplaning = true;
        }
      }

      return withWeather.copyWithWeather(
        isRaining: withWeather.isRaining,
        riskLevel: _calculateVehicleRisk(withWeather, vehicleType, dips),
        weatherAlerts: withWeather.weatherAlerts,
        elevationDips: dips,
        hydroplaningRisk: hydroplaning,
      );
    });

    final analyzedRoutes = await Future.wait(analyzedFutures);

    // 8. SORT: Safety first, then speed
    analyzedRoutes.sort((a, b) {
      final aSafe = a.riskLevel == 'Safe';
      final bSafe = b.riskLevel == 'Safe';

      if (aSafe && !bSafe) return -1;
      if (!aSafe && bSafe) return 1;
      return a.durationSeconds.compareTo(b.durationSeconds);
    });

    // 9. Return top 3 routes
    final finalRoutes = analyzedRoutes.take(3).toList();
    
    print("🎯 Returning ${finalRoutes.length} routes:");
    for (int i = 0; i < finalRoutes.length; i++) {
      final r = finalRoutes[i];
      print("   Route ${i + 1}: ${r.durationMinutes}min, ${(r.distanceMeters / 1000).toStringAsFixed(1)}km, ${r.riskLevel}");
    }

    return finalRoutes;
    
  } catch (e) {
    ErrorHandler.logError(_tag, 'getSafeRoutesOptions error: $e');
    rethrow;
  }
}

/// Deduplicates routes based on geometric similarity.
/// 
/// Removes routes that are effectively identical even if from different profiles.
List<RouteModel> _deduplicateRoutes(List<RouteModel> routes) {
  if (routes.length <= 1) return routes;
  
  final List<RouteModel> unique = [];
  
  for (final route in routes) {
    bool isDuplicate = false;
    
    for (final existing in unique) {
      // Check distance and time similarity
      final distDiff = (route.distanceMeters - existing.distanceMeters).abs();
      final timeDiff = (route.durationSeconds - existing.durationSeconds).abs();
      
      if (distDiff < 50 && timeDiff < 10) {
        isDuplicate = true;
        break;
      }

      // Check geometric similarity (path matching)
      if (route.points.length == existing.points.length) {
        const double threshold = 0.0001; // ~11 meters
        bool isSamePath = true;
        
        // Check start, middle, and end points
        final int mid = route.points.length ~/ 2;
        final indices = [0, mid, route.points.length - 1];
        
        for (final i in indices) {
          if (i < route.points.length) {
            final p1 = route.points[i];
            final p2 = existing.points[i];
            
            if ((p1.latitude - p2.latitude).abs() > threshold ||
                (p1.longitude - p2.longitude).abs() > threshold) {
              isSamePath = false;
              break;
            }
          }
        }
        
        if (isSamePath) {
          isDuplicate = true;
          break;
        }
      }
    }
    
    if (!isDuplicate) {
      unique.add(route);
    }
  }
  
  return unique;
}

  /// Forces an alternative route by adding a waypoint offset from the midpoint.
  ///
  /// When OSRM only returns a single route, this creates a detour through a
  /// perpendicular offset point to guarantee a visually distinct alternative.
  Future<RouteModel?> _forceAlternativeRoute(
    RouteModel originalRoute,
    LatLng start,
    LatLng end,
    VehicleType vehicleType,
  ) async {
    try {
      // Calculate midpoint of the route
      final midIndex = originalRoute.points.length ~/ 2;
      final midPoint = originalRoute.points[midIndex];

      // Create an offset point perpendicular to the route direction
      // Offset by ~500m to get a meaningfully different path
      const double offsetDegrees = 0.005; // ~500m at equator

      // Calculate bearing from start to end
      final dLat = end.latitude - start.latitude;
      final dLon = end.longitude - start.longitude;

      // Perpendicular offset (rotate 90 degrees)
      final perpLat = midPoint.latitude + (-dLon / (dLat.abs() + dLon.abs()) * offsetDegrees);
      final perpLon = midPoint.longitude + (dLat / (dLat.abs() + dLon.abs()) * offsetDegrees);

      final viaPoint = LatLng(perpLat, perpLon);

      // Fetch route with via point to force a detour
      final profile = vehicleType == VehicleType.bike ? 'cycling' : 'driving';
      final routes = await _getOsrmRoutesWithAlternatives(
        start,
        end,
        profile: profile,
        viaPoint: viaPoint,
      );

      if (routes.isNotEmpty) {
        // Return the first route that is meaningfully different
        for (final route in routes) {
          final distDiff = (route.distanceMeters - originalRoute.distanceMeters).abs();
          if (distDiff > 100) {
            return route;
          }
        }
        // If no meaningfully different route, return the first one anyway
        return routes.first;
      }
    } catch (e) {
      ErrorHandler.logError(_tag, 'Force alternative route error: $e');
    }
    return null;
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
    LatLng end, {
    String profile = 'driving', // Default
    LatLng? viaPoint, // For forced deviation
  }) async {
    try {
      // Use efficient OSRM profiles
      String coordinates = '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      
      if (viaPoint != null) {
        coordinates = '${start.longitude},${start.latitude};${viaPoint.longitude},${viaPoint.latitude};${end.longitude},${end.latitude}';
      }

      final url = Uri.parse('https://router.project-osrm.org/route/v1/$profile/'
          '$coordinates'
          '?overview=full&geometries=geojson&alternatives=true&steps=true');

      final response = await http.get(url, headers: _englishHeaders).timeout(
            const Duration(seconds: 30),
          );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List<dynamic>? ?? [];

        if (routes.isEmpty) {
          throw Exception('No routes found');
        }

        final List<RouteModel> parsedRoutes = routes
            .map((route) =>
                RouteModel.fromOsrmJson(route as Map<String, dynamic>))
            .toList();

        return parsedRoutes;
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
      final checkPoints = _sampleRoutePoints(route.points, samples: 4); // Fast sample
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