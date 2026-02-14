import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui'; // For ImageFilter

import 'package:geolocator/geolocator.dart'; 
import 'package:flutter_compass/flutter_compass.dart'; // Added Compass
import 'package:flutter_tts/flutter_tts.dart' hide ErrorHandler;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../models/route_model.dart';
import '../utils/error_handler.dart';
import 'package:url_launcher/url_launcher.dart'; // Added for calling functionality
import '../widgets/vehicle_marker.dart'; // Added Vehicle Marker
import '../widgets/language_selector.dart'; // Language Selector
import '../widgets/premium_bottom_sheet.dart'; // Premium Bottom Sheet
import '../widgets/weather_overlay.dart'; // Immersive Weather Animations

import '../theme/app_theme.dart';

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
  final String? simulateWeather; // 'rain', 'storm', 'clear'
  final LatLng? startCoords;
  final LatLng? endCoords;

  /// Creates a [MapScreen] for navigation.
  const MapScreen({
    super.key, 
    required this.startPoint, 
    required this.endPoint,
    this.startCoords,
    this.endCoords,
    this.simulateWeather,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
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
  final TextEditingController _mapSearchController = TextEditingController();

  // MAP SEARCH STATE
  List<SearchResult> _mapSearchResults = [];
  bool _isMapSearching = false;
  Timer? _mapSearchDebounce;

  // STATE VARIABLES
  // STATE VARIABLES
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<CompassEvent>? _compassSub; // Compass subscription
  LatLng? _lastRouteCalcPosition;
  double _currentHeading = 0.0; // Combined Heading (GPS or Compass)
  double _deviceHeading = 0.0; // Magnetic Heading

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
  bool _voiceAssistantEnabled = false; // Voice Assistant Toggle (Default OFF)

  // Map Data
  LatLng? _startCoord;
  LatLng? _destinationCoord;
  RouteModel? _currentRoute;
  List<RouteModel> _alternativeRoutes = []; // Store alternatives
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
      // await _checkForSavedRoute(); // Disabled per user request
      
      // AUTO-CALCULATE: If no saved route restored, use the provided endpoint
      if (_currentRoute == null && widget.endPoint.isNotEmpty) {
        _calculateSafeRoute();
      }
    });

    // Initialize Weather Animation
    _weatherController = AnimationController(
       vsync: this, 
       duration: const Duration(milliseconds: 1000) // Loop every 1s
    )..repeat();

    _activeWeatherMode = widget.simulateWeather ?? 'clear';
  }

  late AnimationController _weatherController;
  String _activeWeatherMode = 'clear';

  /// Initializes the text-to-speech engine.
  /// 
  /// ENGLISH FALLBACK: Defaults to English-India, ensuring tourists can use the app.
  void _initVoice() async {
    try {
      await flutterTts.setLanguage(_selectedLanguage);
      await flutterTts.setSpeechRate(1.1); // Fast, clear speech
      await flutterTts.setVolume(1.0);
      await flutterTts.setPitch(1.0);
    } catch (e) {
      // Fallback to English if selected language fails
      await flutterTts.setLanguage('en-IN');
      await flutterTts.setSpeechRate(1.1);
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
    _mapSearchController.dispose();
    _mapSearchDebounce?.cancel();
    flutterTts.stop();
    _weatherController.dispose();
    super.dispose();
  }

  void _onMapSearchChanged(String query) {
    _mapSearchDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _mapSearchResults = [];
        _isMapSearching = false;
      });
      return;
    }
    _mapSearchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await api.getPlaceSuggestions(query);
      if (mounted) {
        setState(() {
          _mapSearchResults = results;
          _isMapSearching = _mapSearchResults.isNotEmpty;
        });
      }
    });
  }

  Future<void> _searchAndNavigate(String destination) async {
    setState(() {
      _mapSearchResults = [];
      _isMapSearching = false;
    });
    _mapSearchController.clear();
    FocusScope.of(context).unfocus();

    // Update the end controller and recalculate
    _endController.text = destination;
    final coords = await api.getCoordinates(destination);
    if (coords != null && mounted) {
      setState(() {
        _destinationCoord = coords;
      });
      _calculateSafeRoute();
    }
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

  // VOICE ASSISTANT TOGGLE
  void _toggleVoice() {
    HapticFeedback.mediumImpact();
    setState(() => _voiceAssistantEnabled = !_voiceAssistantEnabled);
    if (_voiceAssistantEnabled) {
      _speak("Voice assistant enabled");
    } else {
      flutterTts.stop(); // Stop immediately
    }
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
        backgroundColor: AppColors.surface,
        title: const Text(
          'Select Vehicle Type',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                style: const TextStyle(color: Colors.white),
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
        backgroundColor: AppColors.surface,
        title: const Text(
          'Voice Language',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _languageNames.entries.map((entry) {
            return ListTile(
              title: Text(
                entry.value,
                style: const TextStyle(color: Colors.white),
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
        backgroundColor: const Color(0xFF7F1D1D), // Dark Red
        title: Row(
          children: [
            Icon(Icons.emergency, color: Colors.red[100], size: 30),
            const SizedBox(width: 10),
            const Text(
              'Emergency SOS',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose an emergency service to call immediately or copy your location info.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSOSButton(
                  label: "Ambulance",
                  icon: Icons.medical_services,
                  color: Colors.red[900]!,
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchDialer("108");
                  },
                ),
                _buildSOSButton(
                  label: "Police",
                  icon: Icons.local_police,
                  color: Colors.blue[900]!,
                  onTap: () {
                    Navigator.pop(ctx);
                    _launchDialer("100");
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
             Text(
              'Or copy location info to clipboard:',
              style: TextStyle(color: Colors.red[50], fontSize: 14),
            ),
          ],
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

  Widget _buildSOSButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(20),
            side: const BorderSide(color: Colors.white54, width: 2),
            elevation: 5,
          ),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _launchDialer(String number) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: number,
    );
    try {
      await launchUrl(launchUri);
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, 'Could not launch dialer: $e');
      }
    }
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
  /// Starts live GPS tracking with adaptive polling and COMPASS.
  /// 
  /// THERMAL/BATTERY GUARD: Adjusts GPS polling rate based on route conditions.
  /// Starts live GPS tracking with adaptive polling.
  /// 
  /// THERMAL/BATTERY GUARD: Adjusts GPS polling rate based on route conditions.
  void _startLiveTracking() async {
    if (_positionSub != null) return;

    // 0. CHECK PERMISSIONS FIRST
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) ErrorHandler.showError(context, 'Location permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) ErrorHandler.showError(context, 'Location permission permanently denied. Enable in settings.');
        return;
      }
    } catch (e) {
      debugPrint("Permission check error: $e");
    }

    // 1. Start Compass for stationary rotation
    _compassSub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        _deviceHeading = event.heading ?? 0.0;
        // Use compass if not navigating or speed is low (handled in GPS listener)
        if (!_isNavigating) {
             _currentHeading = _deviceHeading;
        }
      });
    });

    // 2. Determine initial GPS polling rate
    final int distanceFilter = GPSPollingConfig.getDistanceFilter(
      isNavigating: _isNavigating,
      isStraightaway: _isCurrentSegmentStraight,
      isInCity: true, // Default to high accuracy
    );

    _positionSub = api.getFullPositionStream(distanceFilter: distanceFilter).listen(
      (pos) async {
        if (!mounted) return;
        
        final LatLng latLongPos = LatLng(pos.latitude, pos.longitude);
        
        // POLYLINE SNAP: Snap GPS to nearest route point
        final LatLng displayPosition = _currentRoute != null 
            ? _currentRoute!.snapToRoute(latLongPos)
            : latLongPos;
        
        setState(() {
          _startCoord = latLongPos; // Actual GPS
          _snappedGPSPosition = displayPosition; // Visual display
          
          // SMART HEADING: Use GPS bearing if moving > 3km/h, else Compass
          if (pos.speed > 0.8) { // ~3 km/h
             _currentHeading = pos.heading;
          } else {
             _currentHeading = _deviceHeading;
          }
        });
        
        // HEADING UP MODE: Rotate map during navigation
        if (_isNavigating) {
          mapController.rotate(-_currentHeading); // Counter-rotate map to keep Heading Up
          mapController.move(displayPosition, 18.0); // Follow user
        }

        if (_isNavigating &&
            _routeInstructions.isNotEmpty &&
            _currentStepIndex < _routeInstructions.length) {
          await _checkNavigationStep(latLongPos);
          
          // THERMAL/BATTERY GUARD: Update polling rate based on route segment
          if (_currentRoute != null) {
            final isStraight = _currentRoute!.isNextSegmentStraight(_currentStepIndex);
            if (isStraight != _isCurrentSegmentStraight) {
              _isCurrentSegmentStraight = isStraight;
              _restartGPSTracking(); // Restart with new polling rate
            }
          }
        }

        if (_destinationCoord != null && !_isNavigating) {
          const Distance distanceCalc = Distance();
          if (_lastRouteCalcPosition == null ||
              distanceCalc.as(LengthUnit.Meter, _lastRouteCalcPosition!, latLongPos) >
                  _recalcThresholdMeters) {
            _lastRouteCalcPosition = latLongPos;
            _calculateSafeRoute(isRefetch: true);
          }
        }
      },
      onError: (e) {
        debugPrint('Position stream error: $e');
        if (mounted) ErrorHandler.showError(context, "GPS Error: $e");
      }, 
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
  /// Speaks text using text-to-speech with English fallback.
  Future<void> _speak(String text) async {
    if (!_voiceAssistantEnabled) return; // Respect toggle

    try {
      // Always sync language before speaking
      await flutterTts.setLanguage(_selectedLanguage);
      await flutterTts.setSpeechRate(1.1);
      await flutterTts.speak(text);
    } catch (e) {
      // ENGLISH FALLBACK: Try English if selected language fails
      try {
        await flutterTts.setLanguage('en-IN');
        await flutterTts.setSpeechRate(1.1);
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
    _compassSub?.cancel();
    _compassSub = null;
    _lastRouteCalcPosition = null;
  }

  /// Starts turn-by-turn navigation.
  /// 
  /// HAPTIC FEEDBACK: Strong vibration on start.
  void _startNavigation() {
    print("🔘 DEBUG: _startNavigation called"); // FORCE LOG
    
    // FAILSAFE: Ensure we have a start position
    // If GPS hasn't locked yet, use the route's starting point
    LatLng? startPos = _snappedGPSPosition ?? _startCoord;
    
    if (startPos == null && routePoints.isNotEmpty) {
       print("🔘 DEBUG: Start coords missing, using route start point as fallback");
       startPos = routePoints.first;
       
       // Update _startCoord so SOS and other features work if needed
       if (mounted) {
         setState(() {
           _startCoord = startPos;
         });
       }
    }

    if (startPos == null) {
         print("🔘 DEBUG: No start position available!");
         ErrorHandler.showError(context, "Waiting for GPS signal...");
         return; 
    }

    try {
      print("🔘 DEBUG: Attempting to start navigation...");
      
      // 1. Update State FIRST to ensure UI responsiveness
      setState(() => _isNavigating = true);
      
      // 2. Haptic Feedback (Non-blocking)
      HapticFeedback.heavyImpact().catchError((e) => debugPrint("Haptic error: $e")); 
      
      // 3. Voice Announcement
      _speak("Starting navigation.");

      // 4. Move Map
      debugPrint("DEBUG: Moving to start pos: $startPos");
      mapController.move(startPos, 18.0);
      mapController.rotate(-_currentHeading); 
      
      // 5. Restart Tracking
      debugPrint("DEBUG: Navigation state set to true. Restarting GPS tracking...");
      _restartGPSTracking(); 
      
      // SUCCESS FEEDBACK
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(
             content: Text("Navigation Started"), 
             backgroundColor: Colors.green,
             duration: Duration(seconds: 1),
           )
        );
      }
      
    } catch (e) {
      debugPrint("DEBUG: Error in _startNavigation: $e");
      ErrorHandler.logError('MapScreen', 'Start Nav Error: $e');
      // Revert state if critical error
      if (mounted) setState(() => _isNavigating = false);
      
      if (mounted) ErrorHandler.showError(context, "Failed to start: $e");
    }
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
    mapController.rotate(0); // Reset rotation to North Up
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
      // Geocoding: PREFER PASSED COORDINATES if available
      LatLng? sCoord = widget.startCoords;
      if (sCoord == null) {
          sCoord = (startText == 'Current Location' || startText.isEmpty)
              ? (_startCoord ?? await api.getCurrentLocation())
              : await api.getCoordinates(startText);
      }

      LatLng? eCoord = widget.endCoords;
      if (eCoord == null) {
          eCoord = await api.getCoordinates(endText);
      }

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

      // Get Vehicle-Specific Routes (Alternatives)
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

      if (mounted) {
        setState(() {
           _startCoord = sCoord;
           _destinationCoord = eCoord;
           _alternativeRoutes = allRoutes;
        });
      }

      // Select best route (first one by default)
      _selectRoute(allRoutes.first);
      
    } catch (e) {
      if (mounted) {
        ErrorHandler.logError('MapScreen', 'Route calc error: $e');
        setState(() {
          isLoading = false;
          hasError = true;
          statusMessage = 'Error: ${e.toString()}';
        });
        ErrorHandler.showError(context, 'Failed to calculate route: $e');
      }
    }
  }

  /// Selects a specific route from available options
  void _selectRoute(RouteModel route) {
      final RouteModel bestRoute = route;
      
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

      // Create dip markers (LEVEL 2 ACCURACY)
      final List<Marker> newDipMarkers = bestRoute.elevationDips.map<Marker>((dip) {
        // Color logic: Blue = Active Water, Red = High Risk Dry, Orange = Med Risk Dry
        final Color color;
        final IconData icon;
        
        if (dip.isActiveWaterlogging) {
          color = const Color(0xFF2962FF); // Deep Blue
          icon = Icons.flood; // Active flooding
        } else if (dip.isHighRisk) {
          color = Colors.red;
          icon = Icons.arrow_downward; // Changed to clear "Elevation Drop" arrow
        } else {
          color = Colors.orange;
          icon = Icons.priority_high; 
        }

        return Marker(
          point: dip.point,
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: color,
            size: dip.isActiveWaterlogging ? 32 : 24, // Larger if active
          ),
        );
      }).toList();

      if (mounted) {
        setState(() {
          _currentRoute = bestRoute;
          routePoints = bestRoute.points;
          _weatherMarkers = newWeatherMarkers;
          _dipMarkers = newDipMarkers;
          _routeInstructions = instructions;
          _currentStepIndex = 0;
          _hasSpokenCurrentStep = false;
          isLoading = false;

          // Risk-based Coloring (Semi-transparent to show Traffic Layer underneath)
          if (bestRoute.riskLevel == 'High') {
            routeColor = Colors.red.withValues(alpha: 0.6);
          } else if (bestRoute.riskLevel == 'Medium') {
            routeColor = Colors.orange.withValues(alpha: 0.6);
          } else {
            routeColor = Colors.blue.withValues(alpha: 0.6); // Safe route (Blue)
          }

          // AUTOMATIC WEATHER ANIMATION TRIGGER
          // User Request: "if it is raining it should automatically show its animation"
          if (bestRoute.isRaining) {
             // Check for severe weather keywords in alerts
             final isStorm = bestRoute.weatherAlerts.any((alert) => 
               alert.description.toLowerCase().contains('storm') || 
               alert.description.toLowerCase().contains('thunder'));
             
             _activeWeatherMode = isStorm ? 'storm' : 'rain';
          } else {
             // If manual simulation implies 'clear' or user just reset, we sync to reality?
             // Or should we only set to 'clear' if it was previously auto-set?
             // Safest is to sync to reality:
             _activeWeatherMode = 'clear';
          }

          routeStats = '${distKm.toStringAsFixed(1)} km • $durationMins min';
          
          // Keep status informative but always show as "Safe Route"
          statusMessage = '✅ Safe Route for ${_selectedVehicle.displayName}';
          
          // Show warnings in weatherForecast instead
          if (bestRoute.riskLevel == 'High') {
            weatherForecast = 'CAUTION: ${bestRoute.isRaining ? "Rain" : "Hazards"} detected';
            if (bestRoute.hydroplaningRisk) weatherForecast += ' | Hydroplaning risk';
            if (bestRoute.hasUnpavedRoads && _selectedVehicle == VehicleType.truck) weatherForecast += ' | Soft ground';
            if (bestRoute.elevationDips.isNotEmpty) weatherForecast += ' | ${bestRoute.elevationDips.length} dip(s)';
          } else if (bestRoute.riskLevel == 'Medium') {
            weatherForecast = 'Drive carefully';
          } else {
            weatherForecast = 'No major hazards';
          }
        });

        // Only zoom to fit route if NOT actively navigating
        if (!_isNavigating && bestRoute.points.isNotEmpty) {
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
        backgroundColor: AppColors.surface,
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
    const double buttonSize = 56.0;
    const double largeButtonSize = 72.0;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark Background
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true, 
      // AppBar removed for Custom Floating Header
      body: Stack(
        children: [
          // DEBUG STATE
          Builder(builder: (context) {
             print("🔘 DEBUG: BUILD STATE -> Nav: $_isNavigating, RoutePoints: ${routePoints.length}");
             return const SizedBox.shrink();
          }),

          // ✅ MIGRATED: flutter_map v8 MAP LAYER
          FlutterMap(
            mapController: mapController,
            options: const MapOptions(
              initialCenter: LatLng(17.3850, 78.4867),
              initialZoom: 12.0,
            ),
            children: [
              // ✅ MIGRATED: TileLayer with userAgentPackageName
              // MAP TILE LAYER
              // - Normal Mode: Clean OpenStreetMap
              // - Navigation Mode OR Manual Traffic: Google Maps Traffic Layer
              // - Normal Mode: Google Maps Standard (Matches Traffic Layer style)
              // - Navigation Mode: Google Maps Traffic Layer
              TileLayer(
                urlTemplate:
                    _rainModeEnabled
                      ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                      : 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.rainsafe.navigator',
              ),

              // RAIN RADAR OVERLAY
              if (_rainModeEnabled || (_currentRoute?.isRaining ?? false))
                TileLayer(
                  urlTemplate:
                      'https://tile.openweathermap.org/map/precipitation_new/{z}/{x}/{y}.png?appid=9de243494c0b295cca9337e1e96b00e2',
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
                  // 1. ALTERNATIVE ROUTES (Grey/Ghost)
                  ..._alternativeRoutes
                      .where((r) => r != _currentRoute && r.points.isNotEmpty)
                      .map((route) {
                    
                    Color riskColor;
                    if (route.riskLevel == 'High') {
                      riskColor = Colors.red.withValues(alpha: 0.7);
                    } else if (route.riskLevel == 'Medium') {
                      riskColor = Colors.orange.withValues(alpha: 0.7); // Yellow is hard to see, Orange is better
                    } else {
                      riskColor = Colors.green.withValues(alpha: 0.6);
                    }

                     return Polyline(
                      points: route.points,
                      color: riskColor,
                      strokeWidth: 5.0, // Slightly thicker to be visible
                      borderColor: Colors.white.withValues(alpha: 0.8), // Add border for contrast
                      borderStrokeWidth: 1.0, 
                     );
                   }),
                   
                   // 2. SELECTED ROUTE (Blue/Primary)
                   if (routePoints.isNotEmpty)
                     Polyline(
                       points: routePoints,
                       strokeWidth: 6.0,
                       color: routeColor,
                     ),
                 ],
               ),
               StreamBuilder<QuerySnapshot>(
                 stream: _hazardStream,
                 builder: (context, snapshot) {
                   final List<Marker> liveHazards = [];

                   if (snapshot.hasError) {
                     debugPrint("❌ FIRESTORE ERROR: ${snapshot.error}");
                   }

                   if (snapshot.connectionState == ConnectionState.active) {
                      debugPrint("🔥 FIRESTORE: Stream active. Docs: ${snapshot.data?.docs.length ?? 0}");
                   }

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
                               const Positioned(
                                 right: 0,
                                 bottom: 0,
                                 child: Icon(
                                   Icons.question_mark,
                                   size: 10,
                                   color: Colors.black,
                                 ),
                               ),
                           ],
                         ),
                       );
                     }));
                   }

                   return MarkerLayer(
                     markers: [
                       // VISUAL: Live Location Puck/Arrow
                       if (_snappedGPSPosition != null)
                         Marker(
                             point: _snappedGPSPosition!,
                             width: 60, // Larger for visibility
                             height: 60,
                             child: Transform.rotate(
                               angle: _isNavigating 
                                   ? 0 
                                   : (_currentHeading * (3.14159 / 180)), 
                               child: VehicleMarker(
                                 vehicleType: _selectedVehicle,
                                 isNavigating: _isNavigating,
                               ),
                             ),),
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
               // WATERLOGGING HEATMAP ZONES
               if (_currentRoute != null && _currentRoute!.elevationDips.isNotEmpty)
                 CircleLayer(
                   circles: _currentRoute!.elevationDips.map((dip) {
                     // Dynamic Color for Heatmap
                     final Color fillColor = dip.isActiveWaterlogging 
                         ? Colors.blue.withValues(alpha: 0.4) 
                         : Colors.orange.withValues(alpha: 0.15);
                     
                     final Color borderColor = dip.isActiveWaterlogging
                         ? Colors.blueAccent
                         : (dip.isHighRisk ? Colors.red : Colors.orange);

                     return CircleMarker(
                       point: dip.point,
                       radius: dip.isActiveWaterlogging ? 50 : 40, // Larger if active
                       color: fillColor,
                       borderColor: borderColor.withValues(alpha: 0.8),
                       borderStrokeWidth: dip.isActiveWaterlogging ? 3 : 2,
                       useRadiusInMeter: true,
                     );
                   }).toList(),
                 ),
             ],
           ),

           // Weather Overlay (Full Screen)
           _buildWeatherEffect(),
           
           // CUSTOM FLOATING HEADER (Replaces AppBar)
           Positioned(
             top: 0, 
             left: 0, 
             right: 0,
             child: SafeArea(
               child: Container(
                 margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                 decoration: BoxDecoration(
                   color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                   borderRadius: BorderRadius.circular(24),
                   border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                   boxShadow: [
                     BoxShadow(
                       color: Colors.black.withValues(alpha: 0.3),
                       blurRadius: 20,
                       offset: const Offset(0, 10),
                     )
                   ],
                 ),
                 child: Row(
                   children: [
                     // Back Button
                     InkWell(
                       onTap: () => Navigator.pop(context),
                       child: const Icon(Icons.arrow_back_ios_new, color: Colors.white70, size: 20),
                     ),
                     const SizedBox(width: 16),
                     
                     // Title & Vehicle
                     Expanded(
                        child: GestureDetector(
                          onTap: () {
                             HapticFeedback.selectionClick();
                             _showVehicleSelectionDialog();
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Navigation",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    _selectedVehicle.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_selectedVehicle.icon, style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.keyboard_arrow_down,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    size: 16,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                     ),

                     // Actions
                     Row(
                       children: [
                         // Voice Mic Button (Glowing when active)  
                         GestureDetector(
                           onTap: () {
                             HapticFeedback.selectionClick();
                             _toggleVoice();
                           },
                           child: AnimatedBuilder(
                             animation: _weatherController,
                             builder: (context, child) {
                               final glow = _voiceAssistantEnabled
                                   ? (sin(_weatherController.value * 2 * pi) + 1) / 2
                                   : 0.0;
                               return Container(
                                 padding: const EdgeInsets.all(8),
                                 decoration: BoxDecoration(
                                   color: _voiceAssistantEnabled
                                       ? const Color(0xFF00F0FF).withValues(alpha: 0.2 + glow * 0.1)
                                       : Colors.white.withValues(alpha: 0.1),
                                   shape: BoxShape.circle,
                                   boxShadow: _voiceAssistantEnabled
                                       ? [
                                           BoxShadow(
                                             color: const Color(0xFF00F0FF).withValues(alpha: 0.3 + glow * 0.3),
                                             blurRadius: 8 + glow * 8,
                                             spreadRadius: glow * 2,
                                           ),
                                         ]
                                       : [],
                                 ),
                                 child: Icon(
                                   _voiceAssistantEnabled ? Icons.mic : Icons.mic_off,
                                   size: 18,
                                   color: _voiceAssistantEnabled ? const Color(0xFF00F0FF) : Colors.white70,
                                 ),
                               );
                             },
                           ),
                         ),
                         const SizedBox(width: 8),
                          _buildHeaderAction(
                            icon: _rainModeEnabled ? Icons.water_drop : Icons.wb_sunny,
                            isActive: _rainModeEnabled,
                            onTap: _toggleRainMode,
                          ),
                          const SizedBox(width: 8),
                          _buildHeaderAction(
                            icon: Icons.translate,
                            isActive: false,
                            onTap: _showLanguageSelector,
                          ),
                        ],
                     ),
                   ],
                 ),
               ),
             ),
           ),
           // FLOATING SEARCH BAR (below header)
           Positioned(
             top: MediaQuery.of(context).padding.top + 72,
             left: 16,
             right: 16,
             child: Column(
               children: [
                 Container(
                   height: 48,
                   decoration: BoxDecoration(
                     color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                     boxShadow: [
                       BoxShadow(
                         color: Colors.black.withValues(alpha: 0.2),
                         blurRadius: 12,
                         offset: const Offset(0, 4),
                       ),
                     ],
                   ),
                   child: Row(
                     children: [
                       const SizedBox(width: 14),
                       const Icon(Icons.search, color: Colors.white38, size: 20),
                       const SizedBox(width: 10),
                       Expanded(
                         child: TextField(
                           controller: _mapSearchController,
                           style: const TextStyle(color: Colors.white, fontSize: 14),
                           decoration: InputDecoration(
                             hintText: _endController.text.isNotEmpty
                                 ? _endController.text
                                 : "Search destination...",
                             hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                             border: InputBorder.none,
                           ),
                           onChanged: _onMapSearchChanged,
                           onSubmitted: (val) {
                             if (val.trim().isNotEmpty) {
                               _searchAndNavigate(val.trim());
                             }
                           },
                         ),
                       ),
                       if (_mapSearchController.text.isNotEmpty)
                         GestureDetector(
                           onTap: () {
                             _mapSearchController.clear();
                             setState(() {
                               _mapSearchResults = [];
                               _isMapSearching = false;
                             });
                           },
                           child: const Padding(
                             padding: EdgeInsets.all(8),
                             child: Icon(Icons.close, color: Colors.white38, size: 18),
                           ),
                         ),
                       const SizedBox(width: 8),
                     ],
                   ),
                 ),
                 // Search Results Dropdown
                 if (_isMapSearching && _mapSearchResults.isNotEmpty)
                   Container(
                     margin: const EdgeInsets.only(top: 4),
                     constraints: const BoxConstraints(maxHeight: 200),
                     decoration: BoxDecoration(
                       color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                       borderRadius: BorderRadius.circular(12),
                       border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                       boxShadow: [
                         BoxShadow(
                           color: Colors.black.withValues(alpha: 0.3),
                           blurRadius: 15,
                         ),
                       ],
                     ),
                     child: ListView.separated(
                       shrinkWrap: true,
                       padding: EdgeInsets.zero,
                       itemCount: _mapSearchResults.length,
                       separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
                       itemBuilder: (ctx, i) {
                         return ListTile(
                           dense: true,
                           leading: const Icon(Icons.location_on, color: Color(0xFF00F0FF), size: 18),
                           title: Text(
                             _mapSearchResults[i].name,
                             style: const TextStyle(color: Colors.white, fontSize: 13),
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                           ),
                           subtitle: Text(
                             _mapSearchResults[i].address,
                             style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                           ),
                           onTap: () => _searchAndNavigate(_mapSearchResults[i].fullText),
                         );
                       },
                     ),
                   ),
               ],
             ),
           ),
           Positioned(
             bottom: (_alternativeRoutes.length > 1 && !_isNavigating) ? 330 : 250,
             right: 16,
             child: Column(
               mainAxisSize: MainAxisSize.min,
               crossAxisAlignment: CrossAxisAlignment.end,
               children: [


                 // SOS BUTTON (Pulsing Glow)
                 SizedBox(
                   width: largeButtonSize,
                   height: largeButtonSize,
                   child: Stack(
                     alignment: Alignment.center,
                     children: [
                       // Outer pulse glow
                       AnimatedBuilder(
                         animation: _weatherController,
                         builder: (context, child) {
                           final pulse = (sin(_weatherController.value * 2 * pi) + 1) / 2;
                           return Container(
                             width: largeButtonSize + 8 + (pulse * 6),
                             height: largeButtonSize + 8 + (pulse * 6),
                             decoration: BoxDecoration(
                               shape: BoxShape.circle,
                               boxShadow: [
                                 BoxShadow(
                                   color: Colors.red.withValues(alpha: 0.3 + pulse * 0.2),
                                   blurRadius: 15 + pulse * 10,
                                   spreadRadius: pulse * 4,
                                 ),
                               ],
                             ),
                           );
                         },
                       ),
                       // Actual button
                       SizedBox(
                         width: largeButtonSize,
                         height: largeButtonSize,
                         child: FloatingActionButton(
                           heroTag: "sos_btn",
                           backgroundColor: const Color(0xFFEF4444),
                           elevation: 12,
                           onPressed: _showSOSDialog,
                           child: const Icon(
                             Icons.sos,
                             color: Colors.white,
                             size: 28,
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),
                 const SizedBox(height: 16), // Standard spacing
                 
                 // RECENTER BUTTON
                 SizedBox(
                   width: buttonSize,
                   height: buttonSize,
                   child: FloatingActionButton(
                     heroTag: "recenter_btn",
                     backgroundColor: Colors.white,
                     onPressed: _recenterMap,
                     child: const Icon(
                       Icons.gps_fixed,
                       color: Colors.black87,
                       size: 24, // Standard size
                     ),
                   ),
                 ),
                 const SizedBox(height: 16),
                 
                 // NAVIGATION START/STOP
                if (_isNavigating)
                   SizedBox(
                    height: buttonSize,
                    child: FloatingActionButton.extended(
                      heroTag: "stop_nav_btn",
                      onPressed: _stopNavigation,
                      backgroundColor: Colors.red,
                      icon: const Icon(
                        Icons.stop,
                        color: Colors.white,
                        size: 18, // Standard size
                      ),
                      label: const Text(
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
                    child: Listener(
                      onPointerDown: (_) => print("🔘 POINTER DOWN on Start Button"),
                      child: FloatingActionButton.extended(
                        heroTag: "start_nav_btn",
                        onPressed: () {
                          print("🔘 BUTTON: Start Clicked via onPressed");
                          _startNavigation();
                        },
                        backgroundColor: Colors.green,
                        icon: const Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 18, // Standard size
                        ),
                        label: const Text(
                          "Start",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14, // Standard size
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                if (routePoints.isNotEmpty || _isNavigating) ...[
                   const SizedBox(height: 16),
                   // STEPS BUTTON
                   SizedBox(
                      height: buttonSize,
                      child: FloatingActionButton.extended(
                        heroTag: "steps_btn",
                        backgroundColor: Colors.blueAccent,
                        icon: const Icon(
                          Icons.format_list_bulleted,
                          color: Colors.white,
                          size: 18, // Standard size
                        ),
                        label: const Text(
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
            bottom: (_alternativeRoutes.length > 1 && !_isNavigating) ? 330 : 250,
            left: 20,
            child: SizedBox(
              width: largeButtonSize,
              height: largeButtonSize,
              child: FloatingActionButton(
                heroTag: 'report',
                onPressed: _showReportHazardDialog,
                backgroundColor: Colors.orange, // Always Orange
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 20, // Standard size
                ),
              ),
            ),
          ),

          // ROUTE SELECTION (Premium Cards)
          if (_alternativeRoutes.length > 1 && !_isNavigating)
            Positioned(
              bottom: 240, // ABOVE Bottom Sheet
              left: 0,
              right: 0,
              child: SizedBox(
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _alternativeRoutes.length,
                  itemBuilder: (context, index) {
                     final route = _alternativeRoutes[index];
                     final isSelected = route == _currentRoute;
                     final Color chipColor;
                     if (route.riskLevel == 'High') {
                       chipColor = const Color(0xFFEF4444);
                     } else if (route.riskLevel == 'Medium') {
                       chipColor = const Color(0xFFF59E0B);
                     } else {
                       chipColor = const Color(0xFF10B981);
                     }
                     
                     return Padding(
                       padding: const EdgeInsets.only(right: 10),
                       child: GestureDetector(
                         onTap: () {
                           HapticFeedback.selectionClick();
                           setState(() => _selectRoute(route));
                         },
                         child: ClipRRect(
                           borderRadius: BorderRadius.circular(16),
                           child: BackdropFilter(
                             filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                             child: Container(
                               width: 140,
                               padding: const EdgeInsets.all(12),
                               decoration: BoxDecoration(
                                 color: isSelected
                                     ? chipColor.withValues(alpha: 0.2)
                                     : const Color(0xFF1E293B).withValues(alpha: 0.8),
                                 borderRadius: BorderRadius.circular(16),
                                 border: Border.all(
                                   color: isSelected ? chipColor : Colors.white.withValues(alpha: 0.1),
                                   width: isSelected ? 1.5 : 1,
                                 ),
                                 boxShadow: [
                                   if (isSelected)
                                     BoxShadow(color: chipColor.withValues(alpha: 0.3), blurRadius: 12),
                                 ],
                               ),
                               child: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                 children: [
                                   Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       Text(
                                         "Route ${index + 1}",
                                         style: TextStyle(
                                           color: Colors.white.withValues(alpha: 0.5),
                                           fontSize: 10,
                                           fontWeight: FontWeight.bold,
                                           letterSpacing: 0.5,
                                         ),
                                       ),
                                       Container(
                                         padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                         decoration: BoxDecoration(
                                           color: chipColor.withValues(alpha: 0.2),
                                           borderRadius: BorderRadius.circular(6),
                                         ),
                                         child: Text(
                                           route.riskLevel.toUpperCase(),
                                           style: TextStyle(color: chipColor, fontSize: 8, fontWeight: FontWeight.bold),
                                         ),
                                       ),
                                     ],
                                   ),
                                   Row(
                                     children: [
                                       Icon(Icons.schedule, size: 12, color: Colors.white.withValues(alpha: 0.6)),
                                       const SizedBox(width: 4),
                                       Flexible(
                                         child: Text(
                                           "${route.durationMinutes} min",
                                           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                           overflow: TextOverflow.ellipsis,
                                         ),
                                       ),
                                       const SizedBox(width: 6),
                                       Flexible(
                                         child: Text(
                                           "${(route.distanceMeters / 1000).toStringAsFixed(1)} km",
                                           style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                                           overflow: TextOverflow.ellipsis,
                                         ),
                                       ),
                                     ],
                                   ),
                                 ],
                               ),
                             ),
                           ),
                         ),
                       ),
                     );
                  },
                ),
              ),
            ),

          // PREMIUM BOTTOM SHEET
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: PremiumBottomSheet(
              route: _currentRoute,
              statusMessage: statusMessage,
              weatherForecast: weatherForecast,
              routeColor: routeColor,
              isNavigating: _isNavigating,
              isRaining: _currentRoute?.isRaining ?? false,
            ),
          ),


          // Full Screen Loading Overlay
          if (isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      "Calculating Safe Route...",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildWeatherEffect() {
    // Determine mode: Explicit simulation OR Rain Mode
    String mode = _activeWeatherMode;
    bool showEffect = mode == 'rain' || mode == 'storm' || mode == 'cloudy' || (_rainModeEnabled && mode != 'clear');
    
    // If rain mode is enabled via toggle, treat as rain unless storm selected
    if (_rainModeEnabled && mode == 'clear') mode = 'rain';

    if (!showEffect && mode == 'clear') return const SizedBox.shrink();

    // Use the new immersive overlay
    return WeatherOverlay(
      weatherMode: mode,
      isNight: DateTime.now().hour > 18 || DateTime.now().hour < 6,
    );
  }

  void _showLanguageSelector() async {
    final selected = await LanguageSelector.show(
      context,
      currentLanguage: _selectedLanguage,
      languageNames: _languageNames,
    );
    if (selected != null && selected != _selectedLanguage) {
      setState(() => _selectedLanguage = selected);
      // Update TTS language and re-apply speed
      await flutterTts.setLanguage(selected);
      await flutterTts.setSpeechRate(1.1);
      // Confirm with a voice sample
      final langName = _languageNames[selected] ?? selected;
      _speak('Language changed to $langName');
    }
  }

  Widget _buildHeaderAction({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF00F0FF).withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.1),
          shape: BoxShape.circle,
          border: isActive
              ? Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.4))
              : null,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: const Color(0xFF00F0FF).withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? const Color(0xFF00F0FF) : Colors.white70,
        ),
      ),
    );
  }
}


