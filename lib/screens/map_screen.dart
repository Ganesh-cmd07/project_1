import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart' hide ErrorHandler;
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../models/route_model.dart';
import '../widgets/search_widget.dart';
import '../utils/error_handler.dart';

/// Navigation screen with interactive map, route display, and voice guidance.
/// Allows users to select safe routes and provides real-time navigation assistance.
class MapScreen extends StatefulWidget {
  /// The starting location for navigation (default: "Current Location").
  final String startPoint;

  /// The destination for navigation.
  final String endPoint;

  /// Creates a [MapScreen] for navigation.
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
      if (_startController.text.trim() == "Current Location" &&
          _liveTrackingEnabled) {
        _startLiveTracking();
      } else {
        _stopLiveTracking();
      }
    });

    // Initial check
    if (_startController.text.trim() == "Current Location" &&
        _liveTrackingEnabled) {
      _startLiveTracking();
    }
  }

  void _initVoice() async {
    try {
      await flutterTts.setLanguage('en-IN');
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setEngine('com.google.android.tts'); // Force Google TTS
    } catch (e) {
      ErrorHandler.logError('MapScreen', 'TTS initialization error: $e');
    }
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
      "rain",
      "sunny",
      "cloudy",
      "weather",
      "null",
      "undefined",
      "unknown location"
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
        if (_isNavigating &&
            _routeInstructions.isNotEmpty &&
            _currentStepIndex < _routeInstructions.length) {
          _checkNavigationStep(pos);
        }

        // Auto-recalculate if user deviates too far from the path
        if (_destinationCoord != null) {
          const Distance distanceCalc = Distance();
          if (_lastRouteCalcPosition == null ||
              distanceCalc.as(LengthUnit.Meter, _lastRouteCalcPosition!, pos) >
                  _recalcThresholdMeters) {
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

    final step = _routeInstructions[_currentStepIndex] as Map<String, dynamic>?;
    if (step == null) return;

    final maneuver = step['maneuver'] as Map<String, dynamic>?;
    final location = maneuver?['location'] as List<dynamic>?;

    // Safety check for location data
    if (location == null || location.length < 2) return;

    final LatLng stepPoint = LatLng((location[1] as num?)?.toDouble() ?? 0.0,
        (location[0] as num?)?.toDouble() ?? 0.0);

    const Distance distCalc = Distance();
    final double dist = distCalc.as(LengthUnit.Meter, currentPos, stepPoint);

    // Speak instruction if within 40m
    if (dist < 40 && !_hasSpokenCurrentStep) {
      // ✅ FIX: Use sanitized instruction or fallback to maneuver type
      final String instruction = (step['instruction'] as String?) ??
          "${maneuver?['type'] ?? 'Continue'}";

      // Remove specific "uneven" data that might have slipped through
      String speech =
          instruction.replaceAll("undefined", "").replaceAll("null", "").trim();

      // Strict check: if the speech became empty or is invalid, use default
      if (speech.isEmpty || !_isValidLocationString(speech)) {
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
          bounds: LatLngBounds.fromPoints(routePoints),
          padding: const EdgeInsets.all(50)));
    }
  }

  // ===============================================================
  // 🛣️ ROUTE CALCULATION (v2.0: Type-Safe RouteModel)
  // ===============================================================
  Future<void> _calculateSafeRoute({bool isRefetch = false}) async {
    if (!isRefetch) FocusScope.of(context).unfocus();

    final String startText = _startController.text.trim();
    final String endText = _endController.text.trim();

    // 1. Validation: Prevent invalid inputs
    if (!_isValidLocationString(endText)) {
      if (!isRefetch) {
        ErrorHandler.showError(
            context, 'Please enter a valid destination name.');
      }
      return;
    }

    if (endText.isEmpty) {
      ErrorHandler.showError(context, 'Please enter a destination');
      return;
    }

    if (!isRefetch) {
      setState(() {
        isLoading = true;
        hasError = false;
        statusMessage = 'Searching...';
        _weatherMarkers = [];
        _routeInstructions = [];
        _isNavigating = false;
      });
    }

    try {
      // 2. Geocoding
      final LatLng? sCoord =
          (startText == 'Current Location' || startText.isEmpty)
              ? (_startCoord ?? await api.getCurrentLocation())
              : await api.getCoordinates(startText);

      final LatLng? eCoord = await api.getCoordinates(endText);

      if (sCoord == null || eCoord == null) {
        if (!isRefetch && mounted) {
          ErrorHandler.showError(
              context, 'Could not find location. Please check spelling.');
          setState(() {
            statusMessage = 'Location not found';
            isLoading = false;
          });
        }
        return;
      }

      if (!isRefetch) await api.addToHistory(endText);

      // 3. Get Route Options from API (Now returns typed RouteModel)
      final List<RouteModel> allRoutes =
          await api.getSafeRoutesOptions(sCoord, eCoord);

      // --- ⚠️ OCEAN / UNREACHABLE CHECK ---
      if (allRoutes.isEmpty) {
        if (mounted) {
          setState(() {
            statusMessage = 'Route unavailable (Ocean/Flight required?)';
            isLoading = false;
            hasError = true;
            routePoints = [];
          });
          ErrorHandler.showErrorDialog(
            context,
            'No Road Route Found',
            'The destination appears to be unreachable by road.\n\n'
                'This usually happens if locations are separated by an ocean or continents.',
          );
        }
        return;
      }
      // ------------------------------------

      // 4. Parse Best Route (Now strongly typed)
      final RouteModel bestRoute = allRoutes[0];
      final double distKm = bestRoute.distanceMeters / 1000;
      final int durationMins = bestRoute.durationMinutes;

      // 5. Build instructions from route model
      final List<Map<String, dynamic>> instructions = bestRoute.steps
          .map((step) => {
                'instruction': step.instruction,
                'distance': step.distance,
                'maneuver': {
                  'type': step.maneuverType,
                  'location': step.location
                }
              })
          .toList();

      // 6. Create weather markers
      final List<Marker> newWeatherMarkers = bestRoute.weatherAlerts
          .map<Marker>((alert) => Marker(
                point: alert.point,
                width: 80,
                height: 80,
                child: Column(
                  children: [
                    const Icon(Icons.cloud, color: Colors.blue, size: 30),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${alert.temperature.toStringAsFixed(0)}°',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  ],
                ),
              ))
          .toList();

      if (mounted) {
        setState(() {
          _startCoord = sCoord;
          _destinationCoord = eCoord;
          routePoints = bestRoute.points;
          _weatherMarkers = newWeatherMarkers;
          _routeInstructions = instructions;

          _currentStepIndex = 0;
          _hasSpokenCurrentStep = false;

          routeColor = bestRoute.riskLevel == 'High'
              ? Colors.redAccent
              : (bestRoute.riskLevel == 'Medium'
                  ? Colors.orange
                  : Colors.green);
          routeStats = '${distKm.toStringAsFixed(1)} km • $durationMins min';

          if (bestRoute.isRaining) {
            statusMessage = '⚠️ Rain Detected';
            weatherForecast = 'Risk: ${bestRoute.riskLevel}';
          } else {
            statusMessage = '✅ Route Clear';
            weatherForecast = 'No rain detected';
          }
          isLoading = false;
        });

        if (!isRefetch) {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(bestRoute.points),
              padding: const EdgeInsets.all(50),
            ),
          );
          if (bestRoute.isRaining) {
            ErrorHandler.showWarning(
              context,
              'Rain at ${bestRoute.weatherAlerts.length} locations. Risk: ${bestRoute.riskLevel}',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          statusMessage = 'Error: Connection Failed';
          isLoading = false;
          hasError = true;
          routePoints = [];
        });
        ErrorHandler.showError(context, ErrorHandler.getUserFriendlyMessage(e));
        ErrorHandler.logError('MapScreen', 'Route error: $e');
      }
    }
  }

  // ===============================================================
  // ⚠️ REPORT HAZARD (Crowd-Sourced Safety Feature v2.0)
  // ===============================================================
  void _showReportHazardDialog() {
    if (_startCoord == null) {
      ErrorHandler.showError(context, 'Location not available for reporting');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Report Hazard',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'What hazard did you encounter?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => _submitHazardReport('Waterlogging', ctx),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.water_drop, color: Colors.blue),
                SizedBox(width: 8),
                Text('Waterlogging',
                    style: TextStyle(color: Colors.blueAccent)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _submitHazardReport('Accident', ctx),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.car_crash, color: Colors.red),
                SizedBox(width: 8),
                Text('Accident', style: TextStyle(color: Colors.redAccent)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _submitHazardReport('Road Block', ctx),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, color: Colors.orange),
                SizedBox(width: 8),
                Text('Road Block', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// Submit hazard report (Mock for now, ready for Firebase).
  /// Submit hazard report to Firebase Firestore.
  /// Stores the report and notifies the user of successful submission.
  void _submitHazardReport(String hazardType, BuildContext ctx) {
    Navigator.pop(ctx);

    if (_startCoord == null) {
      ErrorHandler.showError(context, 'Location not available for reporting');
      return;
    }

    final report = HazardReport(
      location: _startCoord!,
      hazardType: hazardType,
      timestamp: DateTime.now(),
    );

    // Show loading state
    ErrorHandler.logError('HazardReport', 'Submitting: $hazardType');

    // Submit to Firebase Firestore
    FirebaseService.submitHazardReport(report).then((_) {
      if (mounted) {
        ErrorHandler.showSuccess(
          context,
          '$hazardType reported successfully!\nThank you for keeping others safe.',
        );
      }
    }).catchError((error) {
      if (mounted) {
        ErrorHandler.showError(
          context,
          'Failed to submit report: ${ErrorHandler.getUserFriendlyMessage(error)}',
        );
      }
      ErrorHandler.logError('HazardReport', 'Submission failed: $error');
    });
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
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
                color: Colors.grey[900], // Dark Background
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 10)
                ]),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 15),
                const Text("Turn-by-Turn Directions",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Divider(color: Colors.grey),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _routeInstructions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[800]),
                    itemBuilder: (ctx, index) {
                      final step = _routeInstructions[index];
                      // Validated data from _calculateSafeRoute is used here
                      final String instruction = step['instruction']
                          .toString()
                          .replaceAll("turn ", "")
                          .replaceAll("new name", "")
                          .trim();
                      IconData icon = Icons.straight;
                      if (instruction.toLowerCase().contains("left")) {
                        icon = Icons.turn_left;
                      }
                      if (instruction.toLowerCase().contains("right")) {
                        icon = Icons.turn_right;
                      }
                      if (instruction.toLowerCase().contains("destination")) {
                        icon = Icons.flag;
                      }

                      // Highlight current step
                      final bool isCurrent = index == _currentStepIndex;

                      return ListTile(
                        leading: Icon(icon,
                            color: isCurrent
                                ? Colors.greenAccent
                                : Colors.cyanAccent),
                        title: Text(instruction,
                            style: TextStyle(
                                color: isCurrent
                                    ? Colors.greenAccent
                                    : Colors.white,
                                fontSize: 16,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        subtitle: Text("${step['distance']} m",
                            style: const TextStyle(color: Colors.grey)),
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
  // 📱 BUILD UI (with English Map Tiles - CartoDB Voyager)
  // ===============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
          title: const Text("RainSafe Navigation"),
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white),
      body: Stack(
        children: [
          // 1. MAP LAYER
          FlutterMap(
            mapController: mapController,
            options: const MapOptions(
                initialCenter: LatLng(17.3850, 78.4867), initialZoom: 12.0),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),
              PolylineLayer(polylines: [
                Polyline(
                    points: routePoints,
                    strokeWidth: 6.0,
                    color: routeColor.withValues(alpha: 0.6))
              ]),
              MarkerLayer(markers: [
                if (_startCoord != null)
                  Marker(
                      point: _startCoord!,
                      child: const Icon(Icons.my_location,
                          color: Colors.blueAccent, size: 30)),
                if (_destinationCoord != null)
                  Marker(
                      point: _destinationCoord!,
                      child: const Icon(Icons.location_on,
                          color: Colors.red, size: 40)),
                ..._weatherMarkers,
                ..._hazardMarkers,
              ]),
            ],
          ),

          // 2. SEARCH WIDGET (Dark Mode & Top Position)
          Positioned(
            top: 10,
            left: 15,
            right: 15,
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
                  child: const Icon(Icons.gps_fixed, color: Colors.black87))),

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
                    label: const Text("Start",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))),

          if (_isNavigating)
            Positioned(
                bottom: 140,
                right: 20,
                child: FloatingActionButton.extended(
                    heroTag: "stopNav",
                    onPressed: _stopNavigation,
                    backgroundColor: Colors.red,
                    icon: const Icon(Icons.stop, color: Colors.white),
                    label: const Text("Exit",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)))),

          // 5. STEPS BUTTON - Moved UP (bottom: 85)
          if (_routeInstructions.isNotEmpty) ...[
            Positioned(
                bottom: 85,
                right: 20,
                child: FloatingActionButton.extended(
                    heroTag: "directions",
                    backgroundColor: Colors.blueAccent,
                    icon: const Icon(Icons.format_list_bulleted,
                        color: Colors.white),
                    label: const Text("Steps",
                        style: TextStyle(color: Colors.white)),
                    onPressed: _showDirectionsSheet)),
          ],

          // 6. REPORT HAZARD BUTTON (Only visible during navigation)
          if (_isNavigating)
            Positioned(
              bottom: 85,
              left: 20,
              child: FloatingActionButton(
                heroTag: 'report',
                onPressed: _showReportHazardDialog,
                backgroundColor: Colors.redAccent,
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                ),
              ),
            ),

          // 7. COMPACT STATUS CARD (Dark, Small, Bottom Fixed)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.black87,
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                // Slim padding for compact look
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    if (isLoading)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                    else
                      Icon(
                          statusMessage.contains('Rain')
                              ? Icons.warning
                              : Icons.check_circle,
                          color: routeColor,
                          size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(statusMessage,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                          if (routeStats.isNotEmpty)
                            Text("$routeStats  |  $weatherForecast",
                                style: TextStyle(
                                    color: Colors.grey[400], fontSize: 11))
                        ])),
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
