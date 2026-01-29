# Rain Safe Navigator v2.0 - Migration Guide

## For Developers: Key Changes from v1.0 to v2.0

### 1. API Service Return Types

**Before (v1.0)**:
```dart
Future<List<Map<String, dynamic>>> getSafeRoutesOptions(LatLng start, LatLng end)
```

**After (v2.0)**:
```dart
Future<List<RouteModel>> getSafeRoutesOptions(LatLng start, LatLng end)
```

**Migration**:
```dart
// Old code
final List<Map<String, dynamic>> routes = await api.getSafeRoutesOptions(start, end);
final bestRoute = routes[0];
final points = bestRoute['points'];
final isRaining = bestRoute['isRaining'];

// New code (Type-Safe)
final List<RouteModel> routes = await api.getSafeRoutesOptions(start, end);
final RouteModel bestRoute = routes[0];
final List<LatLng> points = bestRoute.points;
final bool isRaining = bestRoute.isRaining;
```

---

### 2. Error Handling

**Before (v1.0)**:
```dart
void _showErrorSnackBar(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
  );
}

// Usage
_showErrorSnackBar("An error occurred");
debugPrint("Route Error: $e");
```

**After (v2.0)**:
```dart
// Use professional error handler
ErrorHandler.showError(context, 'An error occurred');
ErrorHandler.logError('MapScreen', 'Route error: $e');
ErrorHandler.showErrorDialog(context, 'Title', 'Message');
```

---

### 3. Map Tile Layer

**Before (v1.0)**:
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
)
```

**After (v2.0)**:
```dart
TileLayer(
  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
  subdomains: const ['a', 'b', 'c'],
)
```

---

### 4. HTTP Headers

**Before (v1.0)**:
```dart
final response = await http.get(url, headers: {
  'User-Agent': 'RainSafeApp/1.0',
  'Accept-Language': 'en'
});
```

**After (v2.0)**:
```dart
static const Map<String, String> _englishHeaders = {
  'User-Agent': 'RainSafeNavigator/2.0',
  'Accept-Language': 'en-US,en;q=0.9',
  'Accept': 'application/json',
};

final response = await http.get(url, headers: _englishHeaders);
```

---

### 5. Voice Initialization

**Before (v1.0)**:
```dart
void _initVoice() async {
  await flutterTts.setLanguage("en-US");
  await flutterTts.setSpeechRate(0.5);
}
```

**After (v2.0)**:
```dart
void _initVoice() async {
  try {
    await flutterTts.setLanguage('en-IN');
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setEngine('com.google.android.tts'); // Force Google TTS
  } catch (e) {
    ErrorHandler.logError('MapScreen', 'TTS initialization error: $e');
  }
}
```

---

### 6. Model Classes (New in v2.0)

You must import and use these new type-safe models:

```dart
import '../models/route_model.dart';

// RouteModel - Complete route with weather analysis
final route = RouteModel(
  points: [...],
  distanceMeters: 15000,
  durationSeconds: 900,
  steps: [...],
  isRaining: false,
  riskLevel: 'Safe',
  weatherAlerts: [],
);

// NavigationStep - Single turn instruction
final step = NavigationStep(
  instruction: 'Turn left onto Main Street',
  maneuverType: 'left',
  distance: 50,
  location: [78.5, 17.4],
);

// WeatherAlert - Rain detection at location
final alert = WeatherAlert(
  point: LatLng(17.4, 78.5),
  weatherCode: 61,
  description: '🌧️ Rain',
  temperature: 28.5,
  time: '14:30',
);

// HazardReport - User-submitted safety concern
final report = HazardReport(
  location: LatLng(17.4, 78.5),
  hazardType: 'Waterlogging',
  timestamp: DateTime.now(),
);
```

---

### 7. Input Validation

**Before (v1.0)**:
```dart
bool _isValidLocationString(String? input) {
  if (input == null || input.trim().isEmpty) return false;
  
  final lowerInput = input.trim().toLowerCase();
  const invalidTerms = [
    "rain", "sunny", "cloudy", "weather", 
    "null", "undefined", "unknown location"
  ];
  
  if (invalidTerms.contains(lowerInput)) return false;
  return true;
}
```

**After (v2.0)**:
```dart
// Same method, now also in ApiService class
// Moved from MapScreen to ApiService for reuse
bool _isValidLocationString(String? input) {
  // Same validation logic, enforced at API layer
}
```

---

### 8. Hazard Reporting (New in v2.0)

**New Feature - Report Hazard Dialog**:
```dart
void _showReportHazardDialog() {
  // Shows dialog with three options:
  // - Waterlogging (💧)
  // - Accident (🚗)
  // - Road Block (🚧)
}

void _submitHazardReport(String hazardType, BuildContext ctx) {
  final report = HazardReport(
    location: _startCoord!,
    hazardType: hazardType,
    timestamp: DateTime.now(),
  );
  
  // TODO: Firebase integration
  // await FirebaseService.submitHazardReport(report);
  
  ErrorHandler.showSuccess(context, 'Hazard reported!');
}
```

---

### 9. Linter Configuration

**Before (v1.0)**:
```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    # Minimal rules
```

**After (v2.0)**:
```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml
linter:
  rules:
    - prefer_const_constructors      # New
    - prefer_final_fields            # New
    - always_declare_return_types    # New
    - avoid_print                     # New
    - avoid_dynamic_calls            # New
    # ... 20+ additional professional rules
```

---

### 10. Import Updates Required

Add these imports to any file using new features:

```dart
// For type-safe routes
import '../models/route_model.dart';

// For professional error handling
import '../utils/error_handler.dart';

// In map_screen.dart (already done)
import '../models/route_model.dart';
import '../utils/error_handler.dart';
```

---

## Backward Compatibility

⚠️ **Breaking Changes**:
- `getSafeRoutesOptions()` now returns `List<RouteModel>` instead of `List<Map<String, dynamic>>`
- Old code accessing map keys like `route['points']` will fail
- Must migrate to `route.points` property access

✅ **Preserved**:
- All public API endpoints remain the same
- Location permission flows unchanged
- Voice navigation still works (now English-forced)
- Search history still stored locally

---

## Testing Checklist

After upgrade, verify:

- [ ] App compiles without errors
- [ ] Flutter analyze shows no issues (new linter rules)
- [ ] Route calculation returns typed RouteModel
- [ ] Weather alerts display correctly
- [ ] Voice navigation speaks in English
- [ ] Error messages show user-friendly text
- [ ] Hazard report button only shows during navigation
- [ ] Map displays CartoDB Voyager tiles
- [ ] Search history works with new API service

---

## Performance Notes

v2.0 improvements:
- **Type Safety**: Eliminates runtime casting errors
- **Error Handling**: Faster error recovery with proper logging
- **Caching**: Same smart caching strategy (coordinates, suggestions, weather)
- **Memory**: Const constructors reduce heap allocation
- **Network**: English headers standardized for all APIs

---

## Firebase Integration (Future)

Current structure supports Firebase:

```dart
// In _submitHazardReport()
// Uncomment when Firebase is ready:
// await Firebase.initializeApp();
// await FirebaseDatabase.instance
//   .ref('hazards')
//   .push()
//   .set(report.toJson());
```

---

## Questions?

If upgrading existing code:
1. Check type signatures in `lib/services/api_service.dart`
2. Review error handling patterns in `lib/utils/error_handler.dart`
3. Import models from `lib/models/route_model.dart`
4. Run `flutter analyze` to catch linter issues
5. Test on both Android and iOS

---

**Migration Complete** ✅