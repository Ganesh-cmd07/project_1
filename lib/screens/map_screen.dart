import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart'; 
import '../services/api_service.dart';
import '../widgets/search_widget.dart';

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
  // ---------------------------------------------
  // SERVICES
  // ---------------------------------------------
  final ApiService api = ApiService();
  final MapController mapController = MapController();
  final FlutterTts flutterTts = FlutterTts(); 

  // ---------------------------------------------
  // CONTROLLERS
  // ---------------------------------------------
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  // ---------------------------------------------
  // STATE VARIABLES
  // ---------------------------------------------
  StreamSubscription<LatLng>? _positionSub;
  LatLng? _lastRouteCalcPosition;
  
  // Settings
  final double _recalcThresholdMeters = 50.0;
  final bool _liveTrackingEnabled = true; 
  
  // Navigation State
  bool _isNavigating = false; 
  int _currentStepIndex = 0;
  bool _hasSpokenCurrentStep = false;

  // Map Data (Coordinates & Markers)
  LatLng? _startCoord;
  LatLng? _destinationCoord;
  List<LatLng> routePoints = [];
  List<Marker> _weatherMarkers = [];
  final List<Marker> _hazardMarkers = [];

  // Route Instructions 
  List<Map<String, dynamic>> _routeInstructions = [];

  // UI Status
  Color routeColor = Colors.blue;
  String statusMessage = "Enter destination";
  String routeStats = "";
  String weatherForecast = "";
  bool isLoading = false;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: widget.startPoint);
    _endController = TextEditingController(text: widget.endPoint);
    
    _initVoice(); 

    // Listen for changes to "Current Location" text to toggle GPS
    _startController.addListener(() {
      if (_startController.text.trim() == "Current Location" && _liveTrackingEnabled) {
        _startLiveTracking();
      } else {
        _stopLiveTracking();
      }
    });

    // Initial check
    if (_startController.text.trim() == "Current Location" && _liveTrackingEnabled) {
      _startLiveTracking();
    }
  }

  void _initVoice() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
  }

  @override
  void dispose() {
    _stopLiveTracking();
    _startController.dispose();
    _endController.dispose();
    flutterTts.stop();
    super.dispose();
  }

  // ===============================================================
  // 🛡️ VALIDATION HELPER (✅ ADDED: Prevents "rain" inputs)
  // ===============================================================
  bool _isValidLocationString(String? input) {
    if (input == null || input.trim().isEmpty) return false;
    
    final lowerInput = input.trim().toLowerCase();
    
    // The specific "uneven words" to block
    const invalidTerms = [
      "rain", "sunny", "cloudy", "weather", 
      "null", "undefined", "unknown location"
    ];
    
    // Return false if the input matches any invalid term exactly
    if (invalidTerms.contains(lowerInput)) return false;
    
    return true;
  }

  // ===============================================================
  // 📍 GPS TRACKING & VOICE LOGIC
  // ===============================================================
  void _startLiveTracking() {
    if (_positionSub != null) return;

    _positionSub = api.getPositionStream(distanceFilter: 5).listen( 
      (pos) async {
        if (!mounted) return;
        setState(() => _startCoord = pos);

        // Only process navigation logic if "Start" was pressed
        if (_isNavigating && _routeInstructions.isNotEmpty && _currentStepIndex < _routeInstructions.length) {
           _checkNavigationStep(pos);
        }

        // Auto-recalculate if user deviates too far from the path
        if (_destinationCoord != null) {
          const Distance distanceCalc = Distance();
          if (_lastRouteCalcPosition == null ||
              distanceCalc.as(LengthUnit.Meter, _lastRouteCalcPosition!, pos) > _recalcThresholdMeters) {
            _lastRouteCalcPosition = pos;
            _calculateSafeRoute(isRefetch: true);
          }
        }
      },
      onError: (e) => debugPrint('Position stream error: $e'),
    );
  }

  void _checkNavigationStep(LatLng currentPos) async {
    if (!_isNavigating) return;

    final step = _routeInstructions[_currentStepIndex];
    final maneuver = step['maneuver'];
    final location = maneuver['location']; 
    
    // Safety check for location data
    if (location == null || location is! List || location.length < 2) return;

    final LatLng stepPoint = LatLng(location[1], location[0]);

    const Distance distCalc = Distance();
    final double dist = distCalc.as(LengthUnit.Meter, currentPos, stepPoint);

    // Speak instruction if within 40m
    if (dist < 40 && !_hasSpokenCurrentStep) {
      
      // ✅ FIX: Use sanitized instruction or fallback to maneuver type
      String instruction = step['instruction'] ?? "${step['maneuver']['type']}";
      
      // Remove specific "uneven" data that might have slipped through
      String speech = instruction
          .replaceAll("undefined", "")
          .replaceAll("null", "")
          .trim();
      
      // Strict check: if the speech became empty or is invalid, use default
      if(speech.isEmpty || !_isValidLocationString(speech)) {
        speech = "Continue along the route";
      }
      
      await flutterTts.speak("In 40 meters, $speech");
      setState(() => _hasSpokenCurrentStep = true);
    }

    // Advance to next step if we passed the point (within 15m)
    if (dist < 15 && _hasSpokenCurrentStep) {
        setState(() {
          _currentStepIndex++;
          _hasSpokenCurrentStep = false;
        });
    }
  }

  void _stopLiveTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _lastRouteCalcPosition = null;
  }
  
  void _startNavigation() {
    setState(() => _isNavigating = true);
    flutterTts.speak("Starting navigation.");
    if (_startCoord != null) mapController.move(_startCoord!, 18.0); 
  }

  void _stopNavigation() {
    setState(() => _isNavigating = false);
    flutterTts.speak("Navigation stopped.");
    // Zoom out to show full route
    if (routePoints.isNotEmpty) {
       mapController.fitCamera(CameraFit.bounds(
           bounds: LatLngBounds.fromPoints(routePoints), padding: const EdgeInsets.all(50)));
    }
  }

  // ===============================================================
  // 🛣️ ROUTE CALCULATION (Updated for Ocean/Unreachable Checks)
  // ===============================================================
  Future<void> _calculateSafeRoute({bool isRefetch = false}) async {
    if (!isRefetch) FocusScope.of(context).unfocus();

    String startText = _startController.text.trim();
    String endText = _endController.text.trim();

    // 1. Validation: Prevent invalid inputs
    if (!_isValidLocationString(endText)) {
       if (!isRefetch) _showErrorSnackBar("Please enter a valid destination name.");
       return;
    }

    if (endText.isEmpty) {
       _showErrorSnackBar("Please enter a destination");
       return;
    }

    if (!isRefetch) {
      setState(() {
        isLoading = true;
        hasError = false;
        statusMessage = "Searching...";
        _weatherMarkers = [];
        _routeInstructions = [];
        _isNavigating = false; 
      });
    }

    try {
      // 2. Geocoding
      LatLng? sCoord = (startText == "Current Location" || startText.isEmpty)
          ? (_startCoord ?? await api.getCurrentLocation())
          : await api.getCoordinates(startText);

      LatLng? eCoord = await api.getCoordinates(endText);

      if (sCoord == null || eCoord == null) {
        if (!isRefetch) {
          _showErrorSnackBar("Could not find location. Please check spelling.");
          setState(() {
            statusMessage = "Location not found";
            isLoading = false;
          });
        }
        return;
      }
      
      if (!isRefetch) await api.addToHistory(endText);

      // 3. Get Route Options from API
      final List<Map<String, dynamic>> allRoutes = await api.getSafeRoutesOptions(sCoord, eCoord);
      
      // --- ⚠️ OCEAN / UNREACHABLE CHECK ---
      if (allRoutes.isEmpty) {
          // If coordinates are valid but no route exists, it's likely across an ocean or unconnected.
          if (mounted) {
            setState(() {
              statusMessage = "Route unavailable (Ocean/Flight required?)";
              isLoading = false;
              hasError = true;
              routePoints = [];
            });
            _showErrorDialog("No Road Route Found", 
              "The destination appears to be unreachable by road. \n\n"
              "This usually happens if the locations are separated by an ocean or are on different continents.");
          }
          return;
      }
      // -------------------------------------

      // 4. Parse Best Route
      final bestRoute = allRoutes[0];
      final List<LatLng> points = bestRoute['points'];
      final double distKm = bestRoute['distance'] / 1000;
      final int durationMins = (bestRoute['duration'] / 60).round();

      // Sanitize Instructions
      List<Map<String, dynamic>> instructions = [];
      if (bestRoute['instructions'] != null) {
        var rawInstructions = List<Map<String, dynamic>>.from(bestRoute['instructions']);
        instructions = rawInstructions.map((step) {
          String instrText = step['instruction']?.toString() ?? "";
          String maneuverType = step['maneuver']?['type']?.toString() ?? "";

          if (!_isValidLocationString(instrText) || instrText.toLowerCase().contains("rain")) {
             if (maneuverType.contains("left")) {
              instrText = "Turn left";
             } else if (maneuverType.contains("right")) {
              instrText = "Turn right";
             } else {
              instrText = "Continue straight";
             }
             step['instruction'] = instrText; 
          }
          return step;
        }).toList();
      }

      final bool isRaining = bestRoute['isRaining'] ?? false;
      final String riskLevel = bestRoute['riskLevel'] ?? 'Safe';
      final List<dynamic> alerts = bestRoute['weatherAlerts'] ?? [];

      // Create Markers...
      List<Marker> newWeatherMarkers = alerts.map<Marker>((alert) {
        return Marker(
          point: alert['point'] as LatLng,
          width: 80, height: 80,
          child: Column(
            children: [
              const Icon(Icons.cloud, color: Colors.blue, size: 30),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                child: Text("${alert['temp']}°", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _startCoord = sCoord;
          _destinationCoord = eCoord;
          routePoints = points;
          _weatherMarkers = newWeatherMarkers;
          _routeInstructions = instructions; 
          
          _currentStepIndex = 0;
          _hasSpokenCurrentStep = false;

          routeColor = (riskLevel == 'High') ? Colors.redAccent : (riskLevel == 'Medium' ? Colors.orange : Colors.green);
          routeStats = "${distKm.toStringAsFixed(1)} km • $durationMins min";

          if (isRaining) {
            statusMessage = "⚠️ Rain Detected";
            weatherForecast = "Risk: $riskLevel";
          } else {
            statusMessage = "✅ Route Clear";
            weatherForecast = "No rain detected";
          }
          isLoading = false;
        });

        if (!isRefetch) {
          mapController.fitCamera(CameraFit.bounds(
               bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(50)));
          if (isRaining) _showHazardDialog(alerts.length, riskLevel);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          statusMessage = "Error: Connection Failed";
          isLoading = false;
          hasError = true;
          routePoints = [];
        });
        _showErrorSnackBar("An error occurred while calculating the route.");
        debugPrint("Route Error: $e");
      }
    }
  }

  // ✅ NEW HELPER DIALOG FOR "NO ROUTE"
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.redAccent)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _recenterMap() {
    if (_startCoord != null) {
      mapController.move(_startCoord!, 17.0); 
    }
  }

  // ===============================================================
  // 📄 DIRECTIONS SHEET (Dark Theme)
  // ===============================================================
  void _showDirectionsSheet() {
    if (_routeInstructions.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey[900], // Dark Background
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10)]
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 15),
                const Text("Turn-by-Turn Directions", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                const Divider(color: Colors.grey),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _routeInstructions.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[800]),
                    itemBuilder: (ctx, index) {
                      final step = _routeInstructions[index];
                      // Validated data from _calculateSafeRoute is used here
                      String instruction = step['instruction'].toString().replaceAll("turn ", "").replaceAll("new name", "").trim();
                      IconData icon = Icons.straight;
                      if (instruction.toLowerCase().contains("left")) icon = Icons.turn_left;
                      if (instruction.toLowerCase().contains("right")) icon = Icons.turn_right;
                      if (instruction.toLowerCase().contains("destination")) icon = Icons.flag;
                      
                      // Highlight current step
                      bool isCurrent = index == _currentStepIndex;
                      
                      return ListTile(
                        leading: Icon(icon, color: isCurrent ? Colors.greenAccent : Colors.cyanAccent),
                        title: Text(instruction, style: TextStyle(color: isCurrent ? Colors.greenAccent : Colors.white, fontSize: 16, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                        subtitle: Text("${step['distance']} m", style: const TextStyle(color: Colors.grey)),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===============================================================
  // ⚠️ DIALOGS
  // ===============================================================
  void _showReportDialog() {
     showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("Report Hazard", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             ListTile(leading: const Icon(Icons.water_drop, color: Colors.blue), title: const Text("Water Logging", style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context)),
             ListTile(leading: const Icon(Icons.car_crash, color: Colors.red), title: const Text("Accident", style: TextStyle(color: Colors.white)), onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
  
  void _showHazardDialog(int spots, String risk) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Weather Alert"), 
        content: Text("Rain at $spots locations. Risk: $risk."), 
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))]
      ),
    );
  }

  // ===============================================================
  // 📱 BUILD UI
  // ===============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text("RainSafe Navigation"), 
        backgroundColor: Colors.black87, 
        foregroundColor: Colors.white
      ),
      body: Stack(
        children: [
          // 1. MAP LAYER
          FlutterMap(
            mapController: mapController,
            options: const MapOptions(initialCenter: LatLng(17.3850, 78.4867), initialZoom: 12.0),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
              PolylineLayer(polylines: [Polyline(points: routePoints, strokeWidth: 6.0, color: routeColor.withValues(alpha: 0.6))]),
              MarkerLayer(markers: [
                  if (_startCoord != null) Marker(point: _startCoord!, child: const Icon(Icons.my_location, color: Colors.blueAccent, size: 30)),
                  if (_destinationCoord != null) Marker(point: _destinationCoord!, child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
                  ..._weatherMarkers, ..._hazardMarkers,
              ]),
            ],
          ),

          // 2. SEARCH WIDGET (Dark Mode & Top Position)
          Positioned(
            top: 10, left: 15, right: 15,
            child: RainSafeSearchWidget(
              startController: _startController, 
              endController: _endController, 
              onSearchPressed: () => _calculateSafeRoute(isRefetch: false),
            ),
          ),
          
          // 3. RECENTER BUTTON
          Positioned(
            bottom: 240, 
            right: 20, 
            child: FloatingActionButton(
              heroTag: "recenter", 
              backgroundColor: Colors.white, 
              onPressed: _recenterMap, 
              child: const Icon(Icons.gps_fixed, color: Colors.black87)
            )
          ),

          // 4. NAVIGATION BUTTONS (Start / Exit) - Moved UP (bottom: 140)
          if (_routePoints.isNotEmpty && !_isNavigating) 
            Positioned(
              bottom: 140, 
              right: 20, 
              child: FloatingActionButton.extended(
                heroTag: "startNav", 
                onPressed: _startNavigation, 
                backgroundColor: Colors.green, 
                icon: const Icon(Icons.navigation, color: Colors.white), 
                label: const Text("Start", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              )
            ),

          if (_isNavigating)
             Positioned(
               bottom: 140, 
               right: 20, 
               child: FloatingActionButton.extended(
                 heroTag: "stopNav", 
                 onPressed: _stopNavigation, 
                 backgroundColor: Colors.red, 
                 icon: const Icon(Icons.stop, color: Colors.white), 
                 label: const Text("Exit", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
               )
             ),

          // 5. STEPS BUTTON - Moved UP (bottom: 85)
          if (_routeInstructions.isNotEmpty) ...[
            Positioned(
              bottom: 85, 
              right: 20, 
              child: FloatingActionButton.extended(
                heroTag: "directions", 
                backgroundColor: Colors.blueAccent, 
                icon: const Icon(Icons.format_list_bulleted, color: Colors.white), 
                label: const Text("Steps", style: TextStyle(color: Colors.white)), 
                onPressed: _showDirectionsSheet
              )
            ),
          ],
          
          // 6. REPORT BUTTON (Left Side)
          Positioned(
            bottom: 85, 
            left: 20, 
            child: FloatingActionButton(
              heroTag: "report", 
              onPressed: _showReportDialog, 
              backgroundColor: Colors.redAccent, 
              child: const Icon(Icons.warning_amber_rounded, color: Colors.white)
            )
          ),

          // 7. COMPACT STATUS CARD (Dark, Small, Bottom Fixed)
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: Card(
              color: Colors.black87,
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                // Slim padding for compact look
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    if (isLoading)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    else
                      Icon(statusMessage.contains('Rain') ? Icons.warning : Icons.check_circle, color: routeColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children: [
                          Text(statusMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          if (routeStats.isNotEmpty) 
                            Text("$routeStats  |  $weatherForecast", style: TextStyle(color: Colors.grey[400], fontSize: 11))
                        ]
                      )
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  List<LatLng> get _routePoints => routePoints;
}