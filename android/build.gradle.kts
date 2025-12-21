import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';

// ==========================================
// GLOBAL CACHES (Prevent API Rate Limiting)
// ==========================================
final Map<String, LatLng> _coordinateCache = {};
final Map<String, List<Map<String, dynamic>>> _suggestionsCache = {};
// 🛑 WEATHER CACHE: Key = "lat,lng,hour", Value = Weather Data
final Map<String, dynamic> _weatherCache = {};

DateTime? _lastNominatimCall;

class ApiService {
  // ==========================================
  // 1. GPS & LOCATION SERVICES
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
  // 2. GEOCODING (Nominatim)
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

    // 3. Recursive Split
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

  Future<List<Map<String, dynamic>>> getLocationSuggestions(String query) async {
    if (query.isEmpty) return [];
    if (_suggestionsCache.containsKey(query)) return _suggestionsCache[query]!;

    await _rateLimitNominatim();

    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=10&accept-language=en&addressdetails=1&countrycodes=in');

    try {
      final response = await http.get(url, headers: {
        'User-Agent': 'com.rainsafe.app',
        'Accept-Language': 'en'
      });
      _lastNominatimCall = DateTime.now();

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = (data as List).map((item) {
          final addr = item['address'] ?? {};
          final name = addr['village'] ??
              addr['town'] ??
              addr['city'] ??
              addr['suburb'] ??
              addr['hamlet'] ??
              item['display_name'].split(',')[0];

          return {
            'name': name,
            'displayName': item['display_name'],
            'lat': double.parse(item['lat']),
            'lon': double.parse(item['lon']),
          };
        }).toList();
        _suggestionsCache[query] = list;
        return list;
      }
    } catch (e) {
      debugPrint("Error getting suggestions: $e");
    }
    return [];
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
  // 3. ROUTING & SAFE ROUTE LOGIC (COMPLETE & FIXED)
  // ==========================================

  Future<Map<String, dynamic>> getRouteWithRainCheck(
      LatLng start, LatLng end) async {
    
    // 1. Get Geometry from OSRM
    final routeData = await _getOsrmRoute(start, end);
    final List<LatLng> points = routeData['points'];
    final double totalDurationSeconds = routeData['duration'].toDouble();

    // 2. Sample points (Start, 25%, 50%, 75%, End)
    List<LatLng> checkPoints = _sampleRoutePoints(points, samples: 8);

    bool rainDetected = false;
    List<Map<String, dynamic>> weatherAlerts = [];
    DateTime now = DateTime.now();

    // 3. Loop through points and calculate ARRIVAL TIME for each
    for (int i = 0; i < checkPoints.length; i++) {
      LatLng point = checkPoints[i];

      // ⏱️ TEMPORAL FIX: Calculate estimated time to reach this specific point
      double progressPercent = (i / (checkPoints.length - 1));
      int secondsToPoint = (totalDurationSeconds * progressPercent).round();
      DateTime arrivalTime = now.add(Duration(seconds: secondsToPoint));

      // 4. Get Forecast for that specific hour
      final weather = await _getCachedWeatherForecast(point, arrivalTime);

      if (weather != null) {
        int code = weather['weathercode'] ?? 0;
        
        // Check if it will be raining *when the user arrives*
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
      'points': points,
      'distance': routeData['distance'],
      'duration': routeData['duration'],
      'isRaining': rainDetected,
      'riskLevel': rainDetected ? 'High' : 'Safe',
      'weatherAlerts': weatherAlerts,
    };
  }

  // 🛠️ HELPER: Smart Weather Fetcher with Caching
  Future<Map<String, dynamic>?> _getCachedWeatherForecast(
      LatLng point, DateTime time) async {
    
    String key = "${point.latitude.toStringAsFixed(2)},${point.longitude.toStringAsFixed(2)},${time.hour}";
    
    if (_weatherCache.containsKey(key)) {
      debugPrint("✅ Using Cached Weather for $key");
      return _weatherCache[key];
    }

    await Future.delayed(const Duration(milliseconds: 200));

    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${point.latitude}&longitude=${point.longitude}&hourly=weathercode,temperature_2m&timezone=auto');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        List<dynamic> times = data['hourly']['time'];
        int targetIndex = 0;
        
        String targetIso = time.toIso8601String().substring(0, 13); // "2023-10-27T14"
        
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

  // 🛠️ HELPER: Fetch Route from OSRM
  Future<Map<String, dynamic>> _getOsrmRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson');

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] == null || data['routes'].isEmpty) {
        throw Exception("No route found");
      }

      final route = data['routes'][0];
      final geometry = route['geometry']['coordinates'] as List;

      List<LatLng> points = geometry.map((coord) {
        return LatLng(coord[1].toDouble(), coord[0].toDouble());
      }).toList();

      return {
        'points': points,
        'distance': route['distance'],
        'duration': route['duration'],
      };
    } else {
      throw Exception('Failed to load route');
    }
  }

  // 🛠️ HELPER: Sample equidistant points
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

  // ==========================================
  // 4. WEATHER UTILS
  // ==========================================

  Future<Map<String, dynamic>> getWeatherForecast(LatLng location) async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&hourly=precipitation_probability,weathercode,temperature_2m&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      debugPrint("Error getting weather: $e");
    }
    return {'current': null};
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