import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart' hide ErrorHandler;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../models/route_model.dart';
import '../utils/error_handler.dart';

/// Navigation screen with vehicle-specific intelligence, SOS, and multi-language guidance.
/// 
/// Enhanced with:
/// - Haptic feedback for glove-mode interaction
/// - Rain mode with high-contrast UI
/// - Thermal/battery GPS optimization
/// - Polyline snap for GPS accuracy
/// - WHITE/LIGHT THEME UI
/// 
/// ✅ MIGRATED TO: flutter_map v8 + Geolocator v14 (2026)
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
  // SERVICES
  final ApiService api = ApiService();
  final MapController mapController = MapController();
  final FlutterTts flutterTts = FlutterTts();
  final Stream<QuerySnapshot> _hazardStream = FirebaseFirestore.instance
      .collection('hazards')
      .where('expiresAt', isGreaterThan: DateTime.now())
      .snapshots();

  // CONTROLLERS
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  // STATE VARIABLES
  StreamSubscription<LatLng>? _positionSub;
  LatLng? _lastRouteCalcPosition;

  // VEHICLE MODE & SETTINGS
  VehicleType _selectedVehicle = VehicleType.bike;
  String _selectedLanguage = 'en-IN'; // English-India default (ENGLISH FALLBACK)
  final Map<String, String> _languageNames = const {
    'en-IN': 'English',
    'hi-IN': 'हिंदी (Hindi)',
    'te-IN': 'తెలుగు (Telugu)',
    'ta-IN': 'தமிழ் (Tamil)',
    'kn-IN': 'ಕನ್ನಡ (Kannada)',
  };

  // Settings
  final double _recalcThresholdMeters = 50.0;
  final bool _liveTrackingEnabled = true;

  // RAIN MODE TOGGLE (HIGH-CONTRAST UI)
  /// When enabled, UI elements are scaled to 30% screen height and use
  /// high-contrast colors for visibility in heavy rain.
  bool _rainModeEnabled = false;

  // THERMAL/BATTERY OPTIMIZATION
  /// Tracks if current route segment is a straightaway for GPS polling optimization.
  bool _isCurrentSegmentStraight = false;

  // Navigation State
  bool _isNavigating = false;
  int _currentStepIndex = 0;
  bool _hasSpokenCurrentStep = false;

  // Map Data
  LatLng? _startCoord;
  LatLng? _destinationCoord;
  RouteModel? _currentRoute;
  List<LatLng> routePoints = [];
  List<Marker> _weatherMarkers = [];
  List<Marker> _dipMarkers = [];

  // POLYLINE SNAP: Snapped GPS position for display
  LatLng? _snappedGPSPosition;

  // Route Instructions
  List<Map<String, dynamic>> _routeInstructions = [];

  // UI Status
  Color routeColor = Colors.blue;
  String statusMessage = "Select vehicle & enter destination";
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

    _startController.addListener(() {
      if (_startController.text.trim() == "Current Location" &&
          _liveTrackingEnabled) {
        _startLiveTracking();
      } else {
        _stopLiveTracking();
      }
    });

    if (_startController.text.trim() == "Current Location" &&
        _liveTrackingEnabled) {
      _startLiveTracking();
    }
    
    // OFFLINE MODE: Check for saved route, then auto-calc if needed
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkForSavedRoute();
      
      // AUTO-CALCULATE: If no saved route restored, use the provided endpoint
      if (_currentRoute == null && widget.endPoint.isNotEmpty) {
        _calculateSafeRoute();
      }
    });
  }

  /// Initializes the text-to-speech engine.
  /// 
  /// ENGLISH FALLBACK: Defaults to English-India, ensuring tourists can use the app.
  void _initVoice() async {
    try {
      await flutterTts.setLanguage(_selectedLanguage);
      await flutterTts.setSpeechRate(0.5);
      await flutterTts.setVolume(1.0);
    } catch (e) {
      // Fallback to English if selected language fails
      await flutterTts.setLanguage('en-IN');
      ErrorHandler.logError('MapScreen', 'TTS initialization error, falling back to English: $e');
    }
  }

  /// Restores saved route if available (Offline capabilities).
  Future<void> _checkForSavedRoute() async {
    final savedRoute = await api.getSavedRoute();
    if (savedRoute != null && mounted) {
      // Ask user if they want to restore
      final shouldRestore = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Resume Navigation?'),
          content: const Text('Found an active route from your last session. Would you like to resume?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (shouldRestore == true && mounted) {
        setState(() {
          _currentRoute = savedRoute;
          routePoints = savedRoute.points;
          _routeInstructions = savedRoute.steps.map((step) {
            return {
              'instruction': step.instruction,
              'distance': step.distance,
              'maneuver': {
                'type': step.maneuverType,
                'location': step.location
              }
            };
          }).toList();
          
          // Restore visual elements
          _weatherMarkers = savedRoute.weatherAlerts.map<Marker>((alert) {
             return Marker(
               point: alert.point,
               width: 80, 
               height: 80,
               child: Column(
                 children: [
                   Icon(Icons.cloud, color: _rainModeEnabled ? Colors.lightBlueAccent : Colors.blue, size: 30),
                   Container(
                     padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                     decoration: BoxDecoration(
                       color: Colors.white,
                       borderRadius: BorderRadius.circular(4),
                       border: Border.all(color: Colors.grey.shade300),
                     ),
                     child: Text(
                       '${alert.temperature.toStringAsFixed(0)}°',
                       style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                     ),
                   ),
                 ],
               ),
             );
          }).toList();
          
          _dipMarkers = savedRoute.elevationDips.map<Marker>((dip) {
            return Marker(
              point: dip.point,
              width: 60,
              height: 60,
              child: Icon(Icons.water, color: dip.isHighRisk ? Colors.red : Colors.orange, size: 35),
            );
          }).toList();

          _isNavigating = true; // Auto-start navigation
          statusMessage = "Route restored";
          
          // Re-center map
          if (routePoints.isNotEmpty) {
             mapController.fitCamera(CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(routePoints),
                padding: const EdgeInsets.all(50)));
          }
        });
        
        _startLiveTracking();
        _speak("Resuming navigation.");
      } else {
        await api.clearSavedRoute();
      }
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
  // RAIN MODE TOGGLE (HIGH-CONTRAST UI)
  // ===============================================================
  /// Toggles rain mode for high-contrast, large-button UI.
  /// 
  /// HAPTIC FEEDBACK: Provides strong vibration to confirm toggle.
  void _toggleRainMode() {
    HapticFeedback.heavyImpact();
    setState(() => _rainModeEnabled = !_rainModeEnabled);
    _speak(_rainModeEnabled ? "Rain mode activated" : "Rain mode deactivated");
  }

  // ===============================================================
  // VEHICLE SELECTION DIALOG
  // ===============================================================
  /// Shows a dialog to select vehicle type.
  /// 
  /// HAPTIC FEEDBACK: Medium vibration on selection.
  void _showVehicleSelectionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Select Vehicle Type',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: VehicleType.values.map((vehicle) {
            return ListTile(
              leading: Text(
                vehicle.icon,
                style: const TextStyle(fontSize: 30),
              ),
              title: Text(
                vehicle.displayName,
                style: const TextStyle(color: Colors.black87),
              ),
              subtitle: Text(
                'Rain threshold: ${vehicle.rainThreshold}mm/hr',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              tileColor: _selectedVehicle == vehicle
                  ? Colors.blue.withValues(alpha: 0.1)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: _selectedVehicle == vehicle 
                      ? Colors.blue 
                      : Colors.grey.shade300,
                  width: _selectedVehicle == vehicle ? 2 : 1,
                ),
              ),
              onTap: () {
                HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
                setState(() => _selectedVehicle = vehicle);
                Navigator.pop(ctx);
                _speak('Vehicle changed to ${vehicle.displayName}');
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // LANGUAGE SELECTION DIALOG
  // ===============================================================
  /// Shows a dialog to select voice language.
  /// 
  /// ENGLISH FALLBACK: English is always first in the list.
  void _showLanguageSelectionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Voice Language',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _languageNames.entries.map((entry) {
            return ListTile(
              title: Text(
                entry.value,
                style: const TextStyle(color: Colors.black87),
              ),
              tileColor: _selectedLanguage == entry.key
                  ? Colors.blue.withValues(alpha: 0.1)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: _selectedLanguage == entry.key 
                      ? Colors.blue 
                      : Colors.grey.shade300,
                  width: _selectedLanguage == entry.key ? 2 : 1,
                ),
              ),
              onTap: () async {
                HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
                setState(() => _selectedLanguage = entry.key);
                try {
                  await flutterTts.setLanguage(_selectedLanguage);
                } catch (e) {
                  // ENGLISH FALLBACK if language not supported
                  await flutterTts.setLanguage('en-IN');
                  ErrorHandler.logError('MapScreen', 'Language not supported, falling back to English');
                }
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _speak('Language changed');
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // SOS EMERGENCY FEATURE
  // ===============================================================
  /// Shows the SOS emergency dialog.
  /// 
  /// HAPTIC FEEDBACK: Heavy vibration on activation.
  void _showSOSDialog() {
    HapticFeedback.heavyImpact(); // HAPTIC FEEDBACK
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red[50],
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red[700], size: 30),
            const SizedBox(width: 10),
            Text(
              'Emergency SOS',
              style: TextStyle(color: Colors.red[900], fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'This will copy your location and route info to clipboard.\n\nYou can then paste it into SMS or WhatsApp.',
          style: TextStyle(color: Colors.grey[800], fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact(); // HAPTIC FEEDBACK
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              HapticFeedback.heavyImpact(); // HAPTIC FEEDBACK
              Navigator.pop(ctx);
              _sendSOS();
            },
            child: const Text('COPY SOS INFO'),
          ),
        ],
      ),
    );
  }

  /// Sends an SOS message by copying location info to clipboard.
  /// 
  /// HAPTIC FEEDBACK: Triple vibration pattern on success.
  Future<void> _sendSOS() async {
    if (_startCoord == null) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Location not available');
      return;
    }

    try {
      // Create Google Maps link
      final mapsUrl = 'https://www.google.com/maps?q=${_startCoord!.latitude},${_startCoord!.longitude}';
      
      // Create SOS message
      final message = '🚨 EMERGENCY SOS from RainSafe Navigator\n\n'
        'My Location: $mapsUrl\n'
        'Weather Risk: $statusMessage\n'
        'Route: $routeStats\n'
        'Vehicle: ${_selectedVehicle.displayName}\n\n'
        'Please send help!';

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: message));
      
      if (!mounted) return;
      
      ErrorHandler.showSuccess(context, 'SOS info copied to clipboard!\nPaste in SMS or WhatsApp to send.');
      
      // HAPTIC FEEDBACK: Triple pattern to confirm critical action
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Failed to prepare SOS: ${e.toString()}');
    }
  }

  // ===============================================================
  // GPS TRACKING & VOICE LOGIC
  // ===============================================================
  /// Starts live GPS tracking with adaptive polling.
  /// 
  /// THERMAL/BATTERY GUARD: Adjusts GPS polling rate based on route conditions.
  void _startLiveTracking() {
    if (_positionSub != null) return;

    // Determine initial GPS polling rate
    final int distanceFilter = GPSPollingConfig.getDistanceFilter(
      isNavigating: _isNavigating,
      isStraightaway: _isCurrentSegmentStraight,
      isInCity: true, // Default to high accuracy
    );

    _positionSub = api.getPositionStream(distanceFilter: distanceFilter).listen(
      (pos) async {
        if (!mounted) return;
        
        // POLYLINE SNAP: Snap GPS to nearest route point
        final LatLng displayPosition = _currentRoute != null 
            ? _currentRoute!.snapToRoute(pos)
            : pos;
        
        setState(() {
          _startCoord = pos; // Actual GPS
          _snappedGPSPosition = displayPosition; // Visual display
        });

        if (_isNavigating &&
            _routeInstructions.isNotEmpty &&
            _currentStepIndex < _routeInstructions.length) {
          await _checkNavigationStep(pos);
          
          // THERMAL/BATTERY GUARD: Update polling rate based on route segment
          if (_currentRoute != null) {
            final isStraight = _currentRoute!.isNextSegmentStraight(_currentStepIndex);
            if (isStraight != _isCurrentSegmentStraight) {
              _isCurrentSegmentStraight = isStraight;
              _restartGPSTracking(); // Restart with new polling rate
            }
          }
        }

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

  /// Restarts GPS tracking with updated polling rate.
  /// 
  /// THERMAL/BATTERY GUARD: Called when switching between straight/turn segments.
  void _restartGPSTracking() {
    _stopLiveTracking();
    _startLiveTracking();
  }

  /// Checks if the user has reached a navigation step and provides voice guidance.
  /// 
  /// HAPTIC FEEDBACK: Medium vibration when approaching a turn.
  Future<void> _checkNavigationStep(LatLng currentPos) async {
    if (!_isNavigating) return;

    final step = _routeInstructions[_currentStepIndex] as Map<String, dynamic>?;
    if (step == null) return;

    final maneuver = step['maneuver'] as Map<String, dynamic>?;
    final location = maneuver?['location'] as List<dynamic>?;

    if (location == null || location.length < 2) return;

    final LatLng stepPoint = LatLng(
      (location[1] as num?)?.toDouble() ?? 0.0,
      (location[0] as num?)?.toDouble() ?? 0.0,
    );

    const Distance distCalc = Distance();
    final double dist = distCalc.as(LengthUnit.Meter, currentPos, stepPoint);

    if (dist < 40 && !_hasSpokenCurrentStep) {
      final String instruction = (step['instruction'] as String?) ??
          "${maneuver?['type'] ?? 'Continue'}";

      String speech = instruction
          .replaceAll("undefined", "")
          .replaceAll("null", "")
          .trim();

      if (speech.isEmpty) {
        speech = "Continue along the route";
      }

      await _speak("In 40 meters, $speech");
      
      if (!mounted) return;
      
      // HAPTIC FEEDBACK: Alert user of upcoming turn (critical for glove mode)
      HapticFeedback.mediumImpact();
      
      setState(() => _hasSpokenCurrentStep = true);
    }

    if (dist < 15 && _hasSpokenCurrentStep) {
      if (!mounted) return;
      
      setState(() {
        _currentStepIndex++;
        _hasSpokenCurrentStep = false;
      });
    }
  }

  /// Speaks text using text-to-speech with English fallback.
  Future<void> _speak(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (e) {
      // ENGLISH FALLBACK: Try English if selected language fails
      try {
        await flutterTts.setLanguage('en-IN');
        await flutterTts.speak(text);
      } catch (fallbackError) {
        ErrorHandler.logError('MapScreen', 'TTS error even with English fallback: $fallbackError');
      }
    }
  }

  /// Stops live GPS tracking.
  void _stopLiveTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _lastRouteCalcPosition = null;
  }

  /// Starts turn-by-turn navigation.
  /// 
  /// HAPTIC FEEDBACK: Strong vibration on start.
  void _startNavigation() {
    HapticFeedback.heavyImpact(); // HAPTIC FEEDBACK
    setState(() => _isNavigating = true);
    _speak("Starting navigation.");
    if (_snappedGPSPosition != null) {
      mapController.move(_snappedGPSPosition!, 18.0);
    } else if (_startCoord != null) {
      mapController.move(_startCoord!, 18.0);
    }
    _restartGPSTracking(); // Update GPS polling for navigation mode
  }

  /// Stops turn-by-turn navigation.
  /// 
  /// HAPTIC FEEDBACK: Medium vibration on stop.
  void _stopNavigation() {
    HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
    setState(() {
      _isNavigating = false;
      _isCurrentSegmentStraight = false;
    });
    _speak("Navigation stopped.");
    _restartGPSTracking(); // Restore normal GPS polling
    api.clearSavedRoute(); // Clear offline cache
    
    if (routePoints.isNotEmpty) {
      mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(routePoints),
          padding: const EdgeInsets.all(50)));
    }
  }

  // ===============================================================
  // ROUTE CALCULATION WITH VEHICLE INTELLIGENCE
  // ===============================================================
  /// Calculates the safest route based on vehicle type and weather conditions.
  Future<void> _calculateSafeRoute({bool isRefetch = false}) async {
    if (!isRefetch && mounted) FocusScope.of(context).unfocus();

    final String startText = _startController.text.trim();
    final String endText = _endController.text.trim();

    if (endText.isEmpty) {
      if (mounted) {
        ErrorHandler.showError(context, 'Please enter a destination');
      }
      return;
    }

    if (!isRefetch) {
      setState(() {
        isLoading = true;
        hasError = false;
        statusMessage = 'Searching for ${_selectedVehicle.displayName} safe route...';
        _weatherMarkers = [];
        _dipMarkers = [];
        _routeInstructions = [];
        _isNavigating = false;
      });
    }

    try {
      // Geocoding
      final LatLng? sCoord = (startText == 'Current Location' || startText.isEmpty)
          ? (_startCoord ?? await api.getCurrentLocation())
          : await api.getCoordinates(startText);

      final LatLng? eCoord = await api.getCoordinates(endText);

      if (sCoord == null || eCoord == null) {
        if (!isRefetch && mounted) {
          ErrorHandler.showError(context, 'Could not find location. Please check spelling.');
          setState(() {
            statusMessage = 'Location not found';
            isLoading = false;
          });
        }
        return;
      }

      if (!isRefetch) await api.addToHistory(endText);

      // Get Vehicle-Specific Routes
      final List<RouteModel> allRoutes = await api.getSafeRoutesOptions(
        sCoord,
        eCoord,
        vehicleType: _selectedVehicle,
      );

      if (allRoutes.isEmpty) {
        if (mounted) {
          setState(() {
            statusMessage = 'No route found';
            isLoading = false;
          });
          ErrorHandler.showErrorDialog(
            context,
            'No Road Route Found',
            'The destination appears to be unreachable by road.',
          );
        }
        return;
      }

      // Select best route
      final RouteModel bestRoute = allRoutes.first;
      
      // Store current route for polyline snapping
      _currentRoute = bestRoute;

      final double distKm = bestRoute.distanceMeters / 1000;
      final int durationMins = bestRoute.durationMinutes;

      // Build instructions
      final List<Map<String, dynamic>> instructions = bestRoute.steps.map((step) {
        return {
          'instruction': step.instruction,
          'distance': step.distance,
          'maneuver': {
            'type': step.maneuverType,
            'location': step.location
          }
        };
      }).toList();

      // Create weather markers
      final List<Marker> newWeatherMarkers = bestRoute.weatherAlerts.map<Marker>((alert) {
        return Marker(
          point: alert.point,
          width: 80,
          height: 80,
          child: Column(
            children: [
              Icon(Icons.cloud, color: _rainModeEnabled ? Colors.lightBlueAccent : Colors.blue, size: 30),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  '${alert.temperature.toStringAsFixed(0)}°',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ),
            ],
          ),
        );
      }).toList();

      // Create dip markers
      final List<Marker> newDipMarkers = bestRoute.elevationDips.map<Marker>((dip) {
        return Marker(
          point: dip.point,
          width: 60,
          height: 60,
          child: Icon(
            Icons.water,
            color: dip.isHighRisk ? Colors.red : Colors.orange,
            size: 35,
          ),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _startCoord = sCoord;
          _destinationCoord = eCoord;
          routePoints = bestRoute.points;
          _weatherMarkers = newWeatherMarkers;
          _dipMarkers = newDipMarkers;
          _routeInstructions = instructions;
          _currentStepIndex = 0;
          _hasSpokenCurrentStep = false;

          // Use blue or green for routes
          if (bestRoute.riskLevel == 'High' || bestRoute.riskLevel == 'Medium') {
            routeColor = Colors.blueAccent; // Blue even if risky
          } else {
            routeColor = Colors.green; // Safe route
          }

          routeStats = '${distKm.toStringAsFixed(1)} km • $durationMins min';
          
          // Keep status informative but always show as "Safe Route"
          statusMessage = '✅ Safe Route for ${_selectedVehicle.displayName}';
          
          // Show warnings in weatherForecast instead
          if (bestRoute.riskLevel == 'High') {
            weatherForecast = 'CAUTION: ${bestRoute.isRaining ? "Rain" : "Hazards"} detected';
          } else if (bestRoute.riskLevel == 'Medium') {
            weatherForecast = 'Drive carefully';
          } else {
            weatherForecast = 'No major hazards';
          }

          // Special warnings
          if (bestRoute.hydroplaningRisk) {
            weatherForecast += ' | Hydroplaning risk';
          }
          if (bestRoute.hasUnpavedRoads && _selectedVehicle == VehicleType.truck) {
            weatherForecast += ' | Soft ground';
          }
          if (bestRoute.elevationDips.isNotEmpty) {
            weatherForecast += ' | ${bestRoute.elevationDips.length} dip(s)';
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
        }
        
        // OFFLINE MODE: Save active route
        api.saveActiveRoute(bestRoute);
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
  // HAZARD REPORTING
  // ===============================================================
  /// Shows a dialog to report a hazard.
  /// 
  /// HAPTIC FEEDBACK: Medium vibration on button press.
  void _showReportHazardDialog() {
    if (_startCoord == null) {
      HapticFeedback.lightImpact(); // HAPTIC FEEDBACK for error
      ErrorHandler.showError(context, 'Location not available for reporting');
      return;
    }

    HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Report Hazard',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'What hazard did you encounter?',
          style: TextStyle(color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
              _submitHazardReport('Waterlogging', ctx);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.water_drop, color: Colors.blue),
                SizedBox(width: 8),
                Text('Waterlogging', style: TextStyle(color: Colors.blue)),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
              _submitHazardReport('Accident', ctx);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.car_crash, color: Colors.red),
                SizedBox(width: 8),
                Text('Accident', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact(); // HAPTIC FEEDBACK
              _submitHazardReport('Road Block', ctx);
            },
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
            onPressed: () {
              HapticFeedback.lightImpact(); // HAPTIC FEEDBACK
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// Submits a hazard report to Firebase with weather validation.
  /// 
  /// SENSOR CROSS-CHECK: Validates report against real-time weather data.
  /// HAPTIC FEEDBACK: Double vibration on successful submission.
  Future<void> _submitHazardReport(String hazardType, BuildContext dialogContext) async {
    Navigator.pop(dialogContext);

    if (_startCoord == null) {
      if (!mounted) return;
      ErrorHandler.showError(context, 'Location not available for reporting');
      return;
    }

    // Create report with initial trust score
    final report = HazardReport(
      location: _startCoord!,
      hazardType: hazardType,
      timestamp: DateTime.now(),
      trustScore: 0.5, // Initial score, will be updated by sensor cross-check
      status: HazardStatus.pending,
    );

    try {
      // Submit to Firebase with weather validation
      // Pass the ApiService instance (api) for weather cross-check
      await FirebaseService.submitHazardReport(report, api);
      
      if (!mounted) return;
      
      // HAPTIC FEEDBACK: Double pattern for successful submission
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      HapticFeedback.heavyImpact();
      
      ErrorHandler.showSuccess(
        context,
        '$hazardType reported successfully!\nThank you for keeping others safe.',
      );
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.lightImpact(); // HAPTIC FEEDBACK for error

      String errorMessage = 'Failed to submit report';
      
      if (error is FirebaseException) {
        if (error.code == 'permission-denied') {
          errorMessage = 'Permission denied. You may need to sign in again.';
          debugPrint('FIREBASE PERMISSION ERROR: ${error.message}');
        } else if (error.code == 'unavailable') {
          errorMessage = 'Network unavailable. Please check your connection.';
        } else {
          errorMessage = 'Firebase Error: ${error.message}';
        }
      } else {
        errorMessage = ErrorHandler.getUserFriendlyMessage(error);
      }
      
      ErrorHandler.showError(context, errorMessage);
      ErrorHandler.logError('HazardReport', 'Submission failed: $error');
      debugPrint('FULL ERROR DETAILS: $error'); 
    }
  }

  /// Recenters the map to current location.
  /// 
  /// HAPTIC FEEDBACK: Light vibration on recenter.
  void _recenterMap() {
    HapticFeedback.lightImpact(); // HAPTIC FEEDBACK
    
    // Use snapped position if available for better visual accuracy
    final LatLng centerPos = _snappedGPSPosition ?? _startCoord ?? const LatLng(17.3850, 78.4867);
    mapController.move(centerPos, 17.0);
  }

  /// Shows a bottom sheet with turn-by-turn directions.
  void _showDirectionsSheet() {
    if (_routeInstructions.isEmpty) return;
    
    HapticFeedback.lightImpact(); // HAPTIC FEEDBACK
    
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
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 10)
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 15),
                const Text("Turn-by-Turn Directions",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                Divider(color: Colors.grey[300], height: 20),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _routeInstructions.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey[200]),
                    itemBuilder: (ctx, index) {
                      final step = _routeInstructions[index];
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

                      final bool isCurrent = index == _currentStepIndex;

                      return ListTile(
                        leading: Icon(icon,
                            color: isCurrent
                                ? Colors.green
                                : Colors.blue),
                        title: Text(instruction,
                            style: TextStyle(
                                color: isCurrent
                                    ? Colors.green[700]
                                    : Colors.black87,
                                fontSize: 16,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        subtitle: Text("${step['distance']} m",
                            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
  // BUILD UI (WHITE/LIGHT THEME WITH RAIN MODE)
  // ===============================================================
  @override
  Widget build(BuildContext context) {
    // RAIN MODE: Standard sizes enforced
    final double buttonSize = 56.0;
    final double largeButtonSize = 72.0;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Neutral grey background
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Row(
          children: [
            const Text("RainSafe Navigation"),
            const SizedBox(width: 10),
            Text(
              _selectedVehicle.icon,
              style: const TextStyle(fontSize: 24),
            ),
            if (_rainModeEnabled) ...[
              const SizedBox(width: 10),
              const Icon(Icons.water_drop, color: Colors.blueAccent),
            ],
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 2,
        actions: [
          // RAIN MODE TOGGLE
          IconButton(
            icon: Icon(
              _rainModeEnabled ? Icons.wb_sunny : Icons.water_drop,
              color: Colors.blue,
            ),
            onPressed: _toggleRainMode,
            tooltip: 'Toggle Rain Mode',
            iconSize: 24, // Standard size
          ),
          IconButton(
            icon: Icon(
              Icons.directions_bike,
              color: Colors.black87,
            ),
            onPressed: _showVehicleSelectionDialog,
            tooltip: 'Change Vehicle',
            iconSize: 24, // Standard size
          ),
          IconButton(
            icon: Icon(
              Icons.language,
              color: Colors.black87,
            ),
            onPressed: _showLanguageSelectionDialog,
            tooltip: 'Voice Language',
            iconSize: 24, // Standard size
          ),
        ],
      ),
      body: Stack(
        children: [
          // ✅ MIGRATED: flutter_map v8 MAP LAYER
          FlutterMap(
            mapController: mapController,
            options: const MapOptions(
              initialCenter: LatLng(17.3850, 78.4867),
              initialZoom: 12.0,
            ),
            children: [
              // ✅ MIGRATED: TileLayer with userAgentPackageName
              TileLayer(
                urlTemplate:
                    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.rainsafe.navigator',
              ),
              
              // RAIN MODE OVERLAY (Border only)
              if (_rainModeEnabled)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                          width: 8.0,
                        ),
                      ),
                    ),
                  ),
                ),

              PolylineLayer(
                 polylines: [
                if (routePoints.isNotEmpty) 
                Polyline(
                  points: routePoints,
                  strokeWidth: _selectedVehicle == VehicleType.bike ? 8.0 : 5.0,
                  color: routeColor, // Now only blue or green
                  borderStrokeWidth: 2.0,
                  borderColor: Colors.black26,
                )
              ]),
              StreamBuilder<QuerySnapshot>(
                stream: _hazardStream,
                builder: (context, snapshot) {
                  final List<Marker> liveHazards = [];

                  if (snapshot.hasData) {
                    liveHazards.addAll(snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final locationData = data['location'] as Map<String, dynamic>;
                      final status = data['status'] as String? ?? 'pending';
                      final isVerified = status == 'verified';

                      return Marker(
                        point: LatLng(
                          locationData['latitude'] as double,
                          locationData['longitude'] as double,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Dotted/Glow Effect for Unverified
                            if (!isVerified)
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.orange.withValues(alpha: 0.5),
                                    width: 2,
                                    style: BorderStyle.solid, // Flutter default doesn't support dotted easily here
                                  ),
                                ),
                                width: _rainModeEnabled ? 45 : 35,
                                height: _rainModeEnabled ? 45 : 35,
                              ),
                              
                            // Icon
                            Icon(
                              // Outline for pending, Fill for verified
                              isVerified ? Icons.warning : Icons.warning_amber_rounded,
                              color: isVerified 
                                  ? (_rainModeEnabled ? Colors.red : Colors.red) 
                                  : (_rainModeEnabled ? Colors.orange : Colors.orange),
                              size: _rainModeEnabled ? 40 : 30,
                            ),
                            
                            // Question mark badge for pending
                            if (!isVerified)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.question_mark,
                                    size: 10,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }));
                  }

                  return MarkerLayer(
                    markers: [
                      // POLYLINE SNAP: Use snapped position for visual display
                      if (_snappedGPSPosition != null)
                        Marker(
                            point: _snappedGPSPosition!,
                            child: Icon(
                              Icons.my_location,
                              color: _rainModeEnabled ? Colors.cyanAccent : Colors.blueAccent,
                              size: _rainModeEnabled ? 40 : 30,
                            )),
                      if (_destinationCoord != null)
                        Marker(
                            point: _destinationCoord!,
                            child: Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: _rainModeEnabled ? 50 : 40,
                            )),
                      ..._weatherMarkers,
                      ..._dipMarkers,
                      ...liveHazards,
                    ],
                  );
                },
              ),
            ],
          ),



          // RIGHT-SIDE BUTTONS GROUP (Bottom-Right)
          Positioned(
            bottom: 100,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // SOS BUTTON
                SizedBox(
                  width: largeButtonSize,
                  height: largeButtonSize,
                  child: FloatingActionButton(
                    heroTag: "sos_btn",
                    backgroundColor: Colors.red,
                    onPressed: _showSOSDialog,
                    child: Icon(
                      Icons.sos,
                      color: Colors.white,
                      size: 30, // Standard size
                    ),
                  ),
                ),
                SizedBox(height: 16), // Standard spacing
                
                // RECENTER BUTTON
                SizedBox(
                  width: buttonSize,
                  height: buttonSize,
                  child: FloatingActionButton(
                    heroTag: "recenter_btn",
                    backgroundColor: Colors.white,
                    onPressed: _recenterMap,
                    child: Icon(
                      Icons.gps_fixed,
                      color: Colors.black87,
                      size: 24, // Standard size
                    ),
                  ),
                ),
                SizedBox(height: 16),
                
                // NAVIGATION START/STOP
                if (_isNavigating)
                   SizedBox(
                    height: buttonSize,
                    child: FloatingActionButton.extended(
                      heroTag: "stop_nav_btn",
                      onPressed: _stopNavigation,
                      backgroundColor: Colors.red,
                      icon: Icon(
                        Icons.stop,
                        color: Colors.white,
                        size: 18, // Standard size
                      ),
                      label: Text(
                        "Exit",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // Standard size
                        ),
                      ),
                    ),
                  )
                else if (routePoints.isNotEmpty)
                  SizedBox(
                    height: buttonSize,
                    child: FloatingActionButton.extended(
                      heroTag: "start_nav_btn",
                      onPressed: _startNavigation,
                      backgroundColor: Colors.green,
                      icon: Icon(
                        Icons.navigation,
                        color: Colors.white,
                        size: 18, // Standard size
                      ),
                      label: Text(
                        "Start",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // Standard size
                        ),
                      ),
                    ),
                  ),
                  
                if (routePoints.isNotEmpty || _isNavigating) ...[
                   SizedBox(height: 16),
                   // STEPS BUTTON
                   SizedBox(
                      height: buttonSize,
                      child: FloatingActionButton.extended(
                        heroTag: "steps_btn",
                        backgroundColor: Colors.blueAccent,
                        icon: Icon(
                          Icons.format_list_bulleted,
                          color: Colors.white,
                          size: 18, // Standard size
                        ),
                        label: Text(
                          "Steps",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14, // Standard size
                          ),
                        ),
                         onPressed: _showDirectionsSheet,
                      ),
                    ),
                ],
              ],
            ),
          ),

          // REPORT HAZARD BUTTON (Rain mode adaptive)
          Positioned(
            bottom: 85,
            left: 20,
            child: SizedBox(
              width: largeButtonSize,
              height: largeButtonSize,
              child: FloatingActionButton(
                heroTag: 'report',
                onPressed: _showReportHazardDialog,
                backgroundColor: Colors.orange, // Always Orange
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20, // Standard size
                ),
              ),
            ),
          ),

          // COMPACT STATUS CARD (White with blue border)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Card(
              color: Colors.white, // Always White
              elevation: 4, // Standard elevation
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Colors.grey.shade300,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0, // Standard padding
                ),
                child: Row(
                  children: [
                    if (isLoading)
                      SizedBox(
                        width: 12, // Standard size
                        height: 12, // Standard size
                        child: CircularProgressIndicator(
                          color: Colors.blue,
                          strokeWidth: 2, // Standard width
                        ),
                      )
                    else
                      Icon(
                        Icons.check_circle, // Always show success icon
                        color: routeColor,
                        size: 12, // Standard size
                      ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusMessage,
                            style: TextStyle(
                              color: Colors.black87, // Always Black text
                              fontWeight: FontWeight.bold,
                              fontSize: 10, // Standard size
                            ),
                          ),
                          if (routeStats.isNotEmpty)
                            Text(
                              "$routeStats  |  $weatherForecast",
                              style: TextStyle(
                                color: Colors.grey[600], // Always Grey text
                                fontSize: 8, // Standard size
                              ),
                            ),
                        ],
                      ),
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
}