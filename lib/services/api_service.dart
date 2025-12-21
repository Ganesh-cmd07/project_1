import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// ==========================================
// GLOBAL CACHES (Prevent API Rate Limiting)
// ==========================================
final Map<String, LatLng> _coordinateCache = {};
final Map<String, List<String>> _suggestionsCache = {}; 
final Map<String, dynamic> _weatherCache = {};

DateTime? _lastNominatimCall;

class ApiService {
  
  // ==========================================
  // 1. SEARCH HISTORY & SUGGESTIONS
  // ==========================================

  /// Saves a successful search query to local phone storage
  Future<void> addToHistory(String query) async {
    if (query.trim().isEmpty || query == "Current Location") return;
    
    final prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('search_history') ?? [];

    // Remove duplicates and keep only latest 10
    history.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
    history.insert(0, query);
    if (history.length > 10) history = history.sublist(0, 10);

    await prefs.setStringList('search_history', history);
  }

  /// Gets suggestions: First checks History, then API
  Future<List<String>> getPlaceSuggestions(String query) async {
    List<String> results = [];
    
    // 1. Get History Matches First
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? [];
    
    if (query.isEmpty) {
      return history; // Return full history if box is empty
    }

    // Filter history based on typing
    final historyMatches = history.where((h) => h.toLowerCase().contains(query.toLowerCase())).toList();
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

    // Remove duplicates
    return results.toSet().toList();
  }

  Future<List<String>> _fetchNominatimSuggestions(String query) async {
    final url = Uri.parse(
        "https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5&countrycodes=in");
    
    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'RainSafeApp/1.0'
      });

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final List<String> results = data
            .map<String>((item) => item['display_name'] as String)
            .toList();
        
        _suggestionsCache[query] = results;
        return results;
      }
    } catch (e) {
      debugPrint("Error fetching suggestions: $e");
    }
    return [];
  }

  // ==========================================
  // 2. GPS & LOCATION SERVICES
  // ==========================================

  Future<LatLng?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    return LatLng(position.latitude, position.longitude);
  }

  Stream<LatLng> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 10,
  }) {
    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(locationSettings: settings)
        .map((pos) => LatLng(pos.latitude, pos.longitude));
  }

  // ==========================================
  // 3. GEOCODING
  // ==========================================

  Future<LatLng?> getCoordinates(String cityName) async {
    if (cityName.isEmpty) return null;

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
  }

  Future<LatLng?> _searchNominatim(String query) async {
    if (_coordinateCache.containsKey(query)) return _coordinateCache[query];

    await _rateLimitNominatim();

    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&accept-language=en&addressdetails=1');

    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'com.rainsafe.app',
        'Accept-Language': 'en'
      });
      _lastNominatimCall = DateTime.now();

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if ((data as List).isNotEmpty) {
          final lat = double.parse(data[0]['lat']);
          final lon = double.parse(data[0]['lon']);
          final result = LatLng(lat, lon);
          _coordinateCache[query] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint("Error searching nominatim: $e");
    }
    return null;
  }

  Future<void> _rateLimitNominatim() async {
    if (_lastNominatimCall != null) {
      final diff = DateTime.now().difference(_lastNominatimCall!).inMilliseconds;
      if (diff < 1200) {
        await Future.delayed(Duration(milliseconds: 1200 - diff));
      }
    }
  }

  // ==========================================
  // 4. MULTI-ROUTE & SAFE ROUTE LOGIC
  // ==========================================

  Future<List<Map<String, dynamic>>> getSafeRoutesOptions(LatLng start, LatLng end) async {
    
    // 1. Get multiple geometries from OSRM
    final List<Map<String, dynamic>> rawRoutes = await _getOsrmRoutesWithAlternatives(start, end);
    
    List<Map<String, dynamic>> analyzedRoutes = [];

    // 2. Analyze weather for EACH route
    for (var route in rawRoutes) {
      final analyzed = await _analyzeRouteWeather(route);
      analyzedRoutes.add(analyzed);
    }

    // 3. SORT: Prioritize Safety, then Speed
    analyzedRoutes.sort((a, b) {
      bool aSafe = a['riskLevel'] == 'Safe';
      bool bSafe = b['riskLevel'] == 'Safe';

      if (aSafe && !bSafe) return -1; // A comes first
      if (!aSafe && bSafe) return 1;  // B comes first
      return (a['duration'] as num).compareTo(b['duration'] as num);
    });

    return analyzedRoutes;
  }

  Future<List<Map<String, dynamic>>> _getOsrmRoutesWithAlternatives(LatLng start, LatLng end) async {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&alternatives=true&steps=true');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] == null || (data['routes'] as List).isEmpty) {
        throw Exception("No routes found");
      }

      List<dynamic> routes = data['routes'];

      return routes.map((route) {
        final geometry = route['geometry']['coordinates'] as List;
        List<LatLng> points = geometry.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
        
        return {
          'points': points,
          'distance': route['distance'],
          'duration': route['duration'],
          'instructions': route['legs'][0]['steps'], // For Voice Nav
        };
      }).toList().cast<Map<String, dynamic>>();
    }
    throw Exception('Failed to fetch routes');
  }

  Future<Map<String, dynamic>> _analyzeRouteWeather(Map<String, dynamic> routeData) async {
    List<LatLng> points = routeData['points'];
    double duration = (routeData['duration'] as num).toDouble();
    
    List<LatLng> checkPoints = _sampleRoutePoints(points, samples: 8);

    bool rainDetected = false;
    List<Map<String, dynamic>> weatherAlerts = [];
    DateTime now = DateTime.now();

    for (int i = 0; i < checkPoints.length; i++) {
      LatLng point = checkPoints[i];

      double progressPercent = (i / (checkPoints.length - 1));
      int secondsToPoint = (duration * progressPercent).round();
      DateTime arrivalTime = now.add(Duration(seconds: secondsToPoint));

      final weather = await _getCachedWeatherForecast(point, arrivalTime);
      
      if (weather != null) {
        int code = weather['weathercode'] ?? 0;
        
        if (_isRainyCode(code)) {
          rainDetected = true;
          weatherAlerts.add({
            'point': point,
            'code': code,
            'description': getWeatherDescription(code),
            'temp': weather['temperature_2m'],
            'time': "${arrivalTime.hour}:${arrivalTime.minute.toString().padLeft(2, '0')}", 
          });
        }
      }
    }

    return {
      ...routeData, 
      'isRaining': rainDetected,
      'riskLevel': rainDetected ? 'High' : 'Safe',
      'weatherAlerts': weatherAlerts,
    };
  }

  List<LatLng> _sampleRoutePoints(List<LatLng> path, {int samples = 5}) {
    if (path.isEmpty) return [];
    if (path.length <= samples) return path;

    List<LatLng> result = [];
    int step = (path.length / samples).floor();
    
    for (int i = 0; i < path.length; i += step) {
      result.add(path[i]);
    }
    
    if (result.last != path.last) {
      result.add(path.last);
    }
    return result;
  }

  Future<Map<String, dynamic>?> _getCachedWeatherForecast(
      LatLng point, DateTime time) async {
    
    String key = "${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)},${time.hour}";
    
    if (_weatherCache.containsKey(key)) {
      return _weatherCache[key];
    }

    await Future.delayed(const Duration(milliseconds: 150));

    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&hourly=weathercode,temperature_2m&timezone=auto');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        List<dynamic> times = data['hourly']['time'];
        int targetIndex = 0;
        
        String targetIso = time.toIso8601String().substring(0, 13);
        
        for(int i=0; i<times.length; i++) {
          if(times[i].toString().startsWith(targetIso)) {
            targetIndex = i;
            break;
          }
        }

        Map<String, dynamic> result = {
          'weathercode': data['hourly']['weathercode'][targetIndex],
          'temperature_2m': data['hourly']['temperature_2m'][targetIndex]
        };

        _weatherCache[key] = result;
        return result;
      }
    } catch (e) {
      debugPrint("Error fetching weather: $e");
    }
    return null;
  }

  bool _isRainyCode(int code) {
    return (code >= 51 && code <= 67) || 
           (code >= 80 && code <= 82) || 
           (code >= 95 && code <= 99);   
  }

  String getWeatherDescription(int weatherCode) {
    if (weatherCode == 0) return "Clear sky";
    if (weatherCode >= 1 && weatherCode <= 3) return "Cloudy";
    if (weatherCode >= 45 && weatherCode <= 48) return "Fog";
    if (weatherCode >= 51 && weatherCode <= 55) return "🌧️ Drizzle";
    if (weatherCode >= 56 && weatherCode <= 57) return "❄️ Freezing Drizzle";
    if (weatherCode >= 61 && weatherCode <= 65) return "🌧️ Rain";
    if (weatherCode >= 66 && weatherCode <= 67) return "❄️ Freezing Rain";
    if (weatherCode >= 71 && weatherCode <= 77) return "❄️ Snow";
    if (weatherCode >= 80 && weatherCode <= 82) return "🌧️ Heavy Showers";
    if (weatherCode >= 85 && weatherCode <= 86) return "❄️ Snow Showers";
    if (weatherCode >= 95 && weatherCode <= 99) return "⛈️ Thunderstorm";
    return "Unknown";
  }
}