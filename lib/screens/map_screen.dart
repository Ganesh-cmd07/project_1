import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../services/api_service.dart';
import '../widgets/search_widget.dart'; // ✅ Integrated Custom Widget

class MapScreen extends StatefulWidget {
  final String startPoint;
  final String endPoint;

  const MapScreen({
    super.key,
    this.startPoint = "Current Location",
    this.endPoint = "",
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final ApiService api = ApiService();
  final MapController mapController = MapController();

  // ✅ Controllers for dynamic location searching
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  LatLng? _startCoord;
  LatLng? _destinationCoord;
  List<LatLng> routePoints = [];
  Color routeColor = Colors.blue;
  String statusMessage = "Enter destination and search";
  String routeStats = "";
  String weatherForecast = "";
  bool isLoading = false;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: widget.startPoint);
    _endController = TextEditingController(text: widget.endPoint);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  // Function linked to the search button in widget.dart
  Future<void> _calculateSafeRoute() async {
    String startText = _startController.text.trim();
    String endText = _endController.text.trim();

    if (endText.isEmpty) return;

    setState(() {
      isLoading = true;
      hasError = false;
      statusMessage = "Mapping road route...";
    });

    try {
      // 1. Resolve Text to Coordinates
      LatLng? sCoord = (startText == "Current Location")
          ? await api.getCurrentLocation()
          : await api.getCoordinates(startText);

      LatLng? eCoord = await api.getCoordinates(endText);

      // If location not found, show suggestions
      if (sCoord == null) {
        await _showLocationNotFoundDialog(startText, isStart: true);
        setState(() {
          isLoading = false;
          hasError = false;
        });
        return;
      }

      if (eCoord == null) {
        await _showLocationNotFoundDialog(endText, isStart: false);
        setState(() {
          isLoading = false;
          hasError = false;
        });
        return;
      }

      // 2. Fetch driving data
      final routeData = await api.getRoute(sCoord, eCoord);
      final List<LatLng> points = routeData['points'];

      // ✅ Experience Fix: Catch sea-locked locations (Andaman fix)
      if (points.isEmpty) throw "No road connectivity found.";

      // ✅ Experience Fix: Show road KM and Minutes (0km fix)
      final String distanceKm =
          (routeData['distance'] / 1000).toStringAsFixed(1);
      final int minutes = (routeData['duration'] / 60).round();
      bool raining = await api.isRaining(eCoord);

      // ✅ Fetch detailed weather forecast for destination
      final weatherData = await api.getWeatherForecast(eCoord);
      String forecastText = "";
      if (weatherData['current'] != null) {
        final temp = weatherData['current']['temperature'];
        final weatherCode = weatherData['current']['weathercode'];
        final weatherDesc = api.getWeatherDescription(weatherCode);
        forecastText = "$weatherDesc • ${temp.toStringAsFixed(1)}°C";
      }

      if (mounted) {
        setState(() {
          _startCoord = sCoord;
          _destinationCoord = eCoord;
          routePoints = points;
          routeColor = raining ? Colors.red : Colors.green;
          routeStats = " • $distanceKm km • $minutes mins";
          weatherForecast = forecastText;
          statusMessage = raining ? "⚠️ Rain Ahead!" : "✅ Route Safe";
          isLoading = false;
        });
        mapController.move(sCoord, 12.0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          statusMessage = "❌ $e";
          isLoading = false;
          hasError = true;
          routePoints = [];
        });
      }
    }
  }

  // Show location suggestions dialog when location not found
  Future<void> _showLocationNotFoundDialog(String query,
      {required bool isStart}) async {
    final suggestions = await api.getLocationSuggestions(query);

    if (!mounted) return;

    if (suggestions.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Location Not Found"),
          content: Text(
              "No results found for '$query'.\n\nPlease try:\n• Full address with state\n• Nearby city name\n• Village + District name"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Did you mean?"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: suggestions
                .map(
                  (suggestion) => ListTile(
                    title: Text(suggestion['name'] ?? "Unknown"),
                    subtitle: Text(suggestion['displayName'] ?? ""),
                    onTap: () {
                      Navigator.pop(context);
                      if (isStart) {
                        _startController.text = suggestion['name'] ?? "";
                      } else {
                        _endController.text = suggestion['name'] ?? "";
                      }
                      _calculateSafeRoute();
                    },
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("RainSafe Navigation"),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: const MapOptions(
                initialCenter: LatLng(17.3850, 78.4867), initialZoom: 12.0),
            children: [
              TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              PolylineLayer(
                polylines: [
                  Polyline(
                      points: routePoints, strokeWidth: 6.0, color: routeColor),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_startCoord != null)
                    Marker(
                        point: _startCoord!,
                        child: const Icon(Icons.location_on,
                            color: Colors.green, size: 40)),
                  if (_destinationCoord != null)
                    Marker(
                        point: _destinationCoord!,
                        child: const Icon(Icons.location_on,
                            color: Colors.red, size: 40)),
                ],
              ),
            ],
          ),

          // ✅ UI Widget: The dynamic search interface
          Positioned(
            top: 10,
            left: 15,
            right: 15,
            child: RainSafeSearchWidget(
              startController: _startController,
              endController: _endController,
              onSearchPressed: _calculateSafeRoute,
            ),
          ),

          // Bottom Status Card with Weather Forecast
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isLoading)
                          const CircularProgressIndicator(color: Colors.white)
                        else
                          Icon(hasError ? Icons.error_outline : Icons.info,
                              color: routeColor, size: 30),
                        const SizedBox(width: 15),
                        Expanded(
                            child: Text("$statusMessage$routeStats",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 16))),
                        if (hasError)
                          IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.blueAccent),
                              onPressed: _calculateSafeRoute),
                      ],
                    ),
                    if (weatherForecast.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud,
                                color: Colors.cyan, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Forecast: $weatherForecast",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
