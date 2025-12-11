import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class ApiService {
  // 1. GET GPS LOCATION
  Future<LatLng?> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }

    Position position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  }

  // 2. CONVERT CITY/VILLAGE NAME TO COORDINATES (Using Nominatim - Free, No API Key)
  // Enhanced to find villages, small addresses, and provide suggestions
  // Handles compound addresses like "Village, District, State"
  Future<LatLng?> getCoordinates(String cityName) async {
    if (cityName.isEmpty) return null;

    // Try exact search first
    LatLng? result = await _searchNominatim(cityName);
    if (result != null) return result;

    // If no result, try variations:
    // 1. Try with country added (India is common)
    if (!cityName.toLowerCase().contains('india')) {
      result = await _searchNominatim('$cityName, India');
      if (result != null) return result;
    }

    // 2. Try splitting by comma and searching just the first parts
    if (cityName.contains(',')) {
      final parts = cityName.split(',').map((p) => p.trim()).toList();
      // Try progressively: "Village District", "District State", etc.
      for (int i = 0; i < parts.length - 1; i++) {
        final query = parts.sublist(i).join(', ');
        result = await _searchNominatim(query);
        if (result != null) return result;
      }
    }

    return null;
  }

  // Helper method to search Nominatim
  Future<LatLng?> _searchNominatim(String query) async {
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=1&accept-language=en&addressdetails=1');
    try {
      final response = await http.get(url,
          headers: {'User-Agent': 'com.rainsafe.app', 'Accept-Language': 'en'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if ((data as List).isNotEmpty) {
          debugPrint("Found: ${data[0]['display_name']}");
          return LatLng(
            double.parse(data[0]['lat']),
            double.parse(data[0]['lon']),
          );
        }
      }
    } catch (e) {
      debugPrint("Error searching nominatim: $e");
    }
    return null;
  }

  // Get location suggestions/alternatives when exact match not found
  Future<List<Map<String, dynamic>>> getLocationSuggestions(
      String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=15&accept-language=en&addressdetails=1&countrycodes=in');
    try {
      final response = await http.get(url,
          headers: {'User-Agent': 'com.rainsafe.app', 'Accept-Language': 'en'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data as List)
            .map((item) => {
                  'name': item['address']?['name'] ??
                      item['address']?['village'] ??
                      item['address']?['town'] ??
                      item['address']?['city'] ??
                      item['display_name'],
                  'lat': double.parse(item['lat']),
                  'lon': double.parse(item['lon']),
                  'displayName': item['display_name'],
                })
            .toList();
      }
    } catch (e) {
      debugPrint("Error getting suggestions: $e");
    }
    return [];
  }

  // 3. GET ROUTE & TIME (Using OSRM - Free, No API Key)
  Future<Map<String, dynamic>> getRoute(LatLng start, LatLng end) async {
    final url = Uri.parse(
        'http://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final route = data['routes'][0];

        // Get Geometry (The route points)
        final coordinates = route['geometry']['coordinates'] as List;
        final points = coordinates
            .map((point) => LatLng(point[1].toDouble(), point[0].toDouble()))
            .toList();

        // Get Distance (meters) and Duration (seconds)
        final distance = route['distance']; // in meters
        final duration = route['duration']; // in seconds

        return {
          "points": points,
          "distance": distance,
          "duration": duration,
        };
      }
    } catch (e) {
      debugPrint("Error getting route: $e");
    }
    return {"points": <LatLng>[], "distance": 0.0, "duration": 0.0};
  }

  // 4. CHECK WEATHER (Rain Logic - Current + Forecast)
  Future<bool> isRaining(LatLng location) async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&hourly=precipitation,weathercode');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final weatherCode = data['current_weather']['weathercode'];
        // Codes 51-99 mean Rain
        return (weatherCode >= 51 && weatherCode <= 99);
      }
    } catch (e) {
      debugPrint("Error getting weather: $e");
    }
    return false;
  }

  // 5. GET DETAILED WEATHER FORECAST (7 days with hourly data)
  Future<Map<String, dynamic>> getWeatherForecast(LatLng location) async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current_weather=true&hourly=precipitation,weathercode,temperature_2m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=auto');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'current': data['current_weather'],
          'hourly': data['hourly'],
          'daily': data['daily'],
          'timezone': data['timezone'],
        };
      }
    } catch (e) {
      debugPrint("Error getting weather forecast: $e");
    }
    return {'current': null, 'hourly': null, 'daily': null};
  }

  // 6. INTERPRET WEATHER CODE
  String getWeatherDescription(int weatherCode) {
    if (weatherCode == 0) return "Clear sky";
    if (weatherCode == 1 || weatherCode == 2) return "Mostly clear";
    if (weatherCode == 3) return "Overcast";
    if (weatherCode >= 45 && weatherCode <= 48) return "Foggy";
    if (weatherCode >= 51 && weatherCode <= 67) return "🌧️ Drizzle/Rain";
    if (weatherCode >= 71 && weatherCode <= 77) return "❄️ Snow";
    if (weatherCode >= 80 && weatherCode <= 82) return "🌧️ Heavy Rain";
    if (weatherCode >= 85 && weatherCode <= 86) return "❄️ Heavy Snow";
    if (weatherCode >= 80 && weatherCode <= 99) return "⛈️ Thunderstorm";
    return "Unknown";
  }
}
