# Rain Safe Navigator v2.0 - Technical Architecture

## System Design Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      PRESENTATION LAYER                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Screens:                                            │   │
│  │  • HomeScreen - Welcome/Landing                      │   │
│  │  • MapScreen - Navigation & Route Display            │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Widgets:                                            │   │
│  │  • RainSafeSearchWidget - Location Input & History   │   │
│  │  • Directions Sheet - Turn-by-Turn Instructions      │   │
│  │  • Hazard Report Dialog - Crowd-Sourced Safety       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      BUSINESS LOGIC LAYER                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ApiService (Singleton)                              │   │
│  │  • GPS Tracking (getPositionStream)                  │   │
│  │  • Geocoding (getCoordinates)                        │   │
│  │  • Route Calculation (getSafeRoutesOptions)          │   │
│  │  • Weather Analysis (_analyzeRouteWeather)           │   │
│  │  • Input Validation (_isValidLocationString)         │   │
│  │  • Caching (coordinate, suggestions, weather)        │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  ErrorHandler (Utility)                              │   │
│  │  • showError() - Red SnackBar                        │   │
│  │  • showSuccess() - Green SnackBar                    │   │
│  │  • showWarning() - Orange SnackBar                   │   │
│  │  • showErrorDialog() - Alert Dialog                  │   │
│  │  • logError() - Professional Logging                 │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      DATA MODELS LAYER                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  RouteModel (Strongly Typed)                         │   │
│  │  ├─ List<LatLng> points                              │   │
│  │  ├─ double distanceMeters                            │   │
│  │  ├─ double durationSeconds                           │   │
│  │  ├─ List<NavigationStep> steps                       │   │
│  │  ├─ bool isRaining                                   │   │
│  │  ├─ String riskLevel (Safe/Medium/High)              │   │
│  │  └─ List<WeatherAlert> weatherAlerts                 │   │
│  │                                                       │   │
│  │  NavigationStep                                       │   │
│  │  ├─ String instruction                               │   │
│  │  ├─ String maneuverType                              │   │
│  │  ├─ double distance                                  │   │
│  │  └─ List<double> location                            │   │
│  │                                                       │   │
│  │  WeatherAlert                                         │   │
│  │  ├─ LatLng point                                      │   │
│  │  ├─ int weatherCode (WMO)                            │   │
│  │  ├─ String description                               │   │
│  │  ├─ double temperature                               │   │
│  │  └─ String time                                      │   │
│  │                                                       │   │
│  │  HazardReport                                         │   │
│  │  ├─ LatLng location                                  │   │
│  │  ├─ String hazardType                                │   │
│  │  └─ DateTime timestamp                               │   │
│  │                                                       │   │
│  │  GeocodingResult                                      │   │
│  │  ├─ LatLng coordinates                               │   │
│  │  └─ String displayName                               │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│                      EXTERNAL SERVICES                      │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  │   Nominatim     │ │      OSRM       │ │  Open-Meteo     │
│  │  (Geocoding)    │ │   (Routing)     │ │   (Weather)     │
│  │  250ms response │ │  1-2s response  │ │  150ms response │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Local Storage (SharedPreferences)                   │   │
│  │  • Search History (last 10 queries)                  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Device Services                                     │   │
│  │  • Geolocator (GPS Tracking)                         │   │
│  │  • FlutterTts (Voice Navigation)                     │   │
│  │  • FlutterMap (Map Rendering)                        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagrams

### 1. Route Calculation Flow

```
User Input (Start/Destination)
         ↓
[Validation] - Reject if invalid terms
         ↓
[Geocoding] - Nominatim API
  Nominatim: startPoint → LatLng
  Nominatim: destination → LatLng
         ↓
[Multi-Route] - OSRM API
  Get up to 3 alternative routes with steps
         ↓
[Weather Analysis] - Open-Meteo API (8 waypoints per route)
  For each route:
    • Sample 8 waypoints
    • Calculate ETA for each
    • Fetch weather forecast
    • Detect rain (WMO codes 51-67, 80-82, 95-99)
         ↓
[Sorting] - Safety First, then Speed
  Group by riskLevel (Safe, Medium, High)
  Sort by duration within each group
         ↓
[Cache] - Store in memory
  _coordinateCache
  _suggestionsCache
  _weatherCache
         ↓
[Return] - List<RouteModel> (Type-Safe)
```

### 2. Navigation Flow

```
Route Selected & "Start" Pressed
         ↓
[Voice Init] - Set language to en-IN, force Google TTS
         ↓
[GPS Stream] - Continuous position updates
         ↓
[Step Tracking] - For each instruction:
    • Calculate distance to waypoint
    • At 40m: Speak instruction
    • At 15m: Mark as completed
         ↓
[Auto-Recalc] - If user deviates >50m
    Trigger _calculateSafeRoute() with isRefetch=true
         ↓
[Voice Guidance] - "In 40 meters, turn left"
         ↓
[Navigation State] - Track current step index
         ↓
[Exit] - Stop voice, zoom to full route
```

### 3. Hazard Reporting Flow

```
During Navigation
         ↓
[Report Button] - FAB (visible only when _isNavigating=true)
         ↓
[Dialog] - Three options:
  • Waterlogging
  • Accident
  • Road Block
         ↓
[Capture Data]
  • Hazard type (selected)
  • GPS location (_startCoord)
  • Timestamp (DateTime.now())
         ↓
[Mock Submission]
  • Log to console (ErrorHandler.logError)
  • Show success message (ErrorHandler.showSuccess)
         ↓
[Firebase Ready]
  // await Firebase submit on production
  // Structure: HazardReport.toJson()
```

---

## Caching Strategy

### Global Caches (In-Memory, Session-Scoped)

```dart
// 1. Coordinate Cache
_coordinateCache: Map<String, LatLng>
  Key: "City Name, Country"
  Purpose: Avoid re-geocoding same addresses
  Lifetime: Session
  
// 2. Suggestions Cache
_suggestionsCache: Map<String, List<String>>
  Key: "search query"
  Purpose: Store Nominatim API results
  Lifetime: Session
  
// 3. Weather Cache
_weatherCache: Map<String, dynamic>
  Key: "lat,lon,hour"
  Purpose: Store hourly forecasts
  Lifetime: Session
  Lookup: Smart matching by hour
```

### Local Storage (Persistent)

```dart
SharedPreferences
  Key: 'search_history'
  Value: List<String> (last 10 searches)
  Lifetime: Until cleared by user
```

---

## Type Safety Architecture

### Before (v1.0) - Dynamic Chaos
```dart
Future<List<Map<String, dynamic>>> getSafeRoutesOptions(...)

// Usage - No IDE hints, runtime errors possible
final routes = await api.getSafeRoutesOptions(start, end);
final bestRoute = routes[0];
final points = bestRoute['points'];  // Could be null!
final isRaining = bestRoute['isRaining'];  // Type unknown
```

### After (v2.0) - Strong Typing
```dart
Future<List<RouteModel>> getSafeRoutesOptions(...)

// Usage - Full IDE support, compile-time safety
final List<RouteModel> routes = await api.getSafeRoutesOptions(start, end);
final RouteModel bestRoute = routes[0];
final List<LatLng> points = bestRoute.points;  // Type guaranteed
final bool isRaining = bestRoute.isRaining;  // Boolean guaranteed
```

---

## Error Handling Architecture

### Three-Layer Error Handling

```
┌─────────────────────────────────────────┐
│  Layer 1: User Interface (Visible)     │
│                                         │
│  ErrorHandler.showError()    → Red     │
│  ErrorHandler.showSuccess()  → Green   │
│  ErrorHandler.showWarning()  → Orange  │
│  ErrorHandler.showErrorDialog() → Pop  │
└─────────────────────────────────────────┘
            ↑
            │ Maps to...
            ↓
┌─────────────────────────────────────────┐
│  Layer 2: Message Mapping               │
│                                         │
│  getUserFriendlyMessage(error)          │
│  • Timeout → "Request timed out"       │
│  • NoRoute → "Unreachable by road"     │
│  • Network → "Check internet"          │
│  • Generic → Generic fallback          │
└─────────────────────────────────────────┘
            ↑
            │ Based on...
            ↓
┌─────────────────────────────────────────┐
│  Layer 3: Exception Logging (Hidden)    │
│                                         │
│  ErrorHandler.logError(tag, error)     │
│  • Timestamp                            │
│  • Component tag                        │
│  • Full stack trace                     │
│  • Non-blocking (doesn't crash UI)      │
└─────────────────────────────────────────┘
```

---

## Localization Strategy (English Enforcement)

```
HTTP Requests
  ↓ Add Header
  Accept-Language: en-US,en;q=0.9
  ↓
API Responses
  ├─ Nominatim → English place names
  ├─ OSRM → English instructions
  └─ Open-Meteo → Standard codes
  ↓
Map Layer
  ├─ CartoDB Voyager
  ├─ English labels (professional)
  └─ Consistent styling
  ↓
Voice Output
  ├─ Language: en-IN
  ├─ Engine: com.google.android.tts
  ├─ Override: Force (no system language)
  └─ Rate: 0.5x (clear speech)
```

---

## Professional Standards Implementation

### Code Quality Checklist

| Standard | Implementation | Check |
|----------|----------------|-------|
| Type Safety | RouteModel, NavigationStep, etc. | ✅ |
| Error Handling | ErrorHandler utility | ✅ |
| Input Validation | _isValidLocationString() | ✅ |
| Documentation | Public API comments | ✅ |
| Const Constructors | prefer_const_constructors | ✅ |
| Final Fields | prefer_final_fields | ✅ |
| Return Types | always_declare_return_types | ✅ |
| Logging | ErrorHandler.logError() | ✅ |
| Testing | Validated against edge cases | ✅ |
| Linting | 25+ rules enforced | ✅ |

### Analysis Options (analysis_options.yaml)

```yaml
✅ prefer_const_constructors
✅ prefer_const_constructors_in_immutables
✅ prefer_const_declarations
✅ prefer_final_fields
✅ prefer_final_locals
✅ avoid_empty_else
✅ avoid_print (use ErrorHandler)
✅ always_declare_return_types
✅ avoid_dynamic_calls
✅ unused_element
✅ unused_import
✅ public_member_api_docs
```

---

## Performance Considerations

### API Call Optimization

```
Nominatim (Geocoding)
├─ Rate limit: 1.2 seconds between calls
├─ Cache: Prevent repeat queries
├─ Timeout: 10 seconds
└─ Limit: 5 results max

OSRM (Routing)
├─ Multiple routes: 3 alternatives
├─ With steps: Turn-by-turn included
├─ Timeout: 15 seconds
└─ Caching: None (dynamic routing)

Open-Meteo (Weather)
├─ Concurrent: 8 waypoint checks
├─ Timeout: 10 seconds each
├─ Cache: By lat,lon,hour
└─ Delay: 150ms between requests
```

### Memory Management

```
Const Constructors
  → Singleton instances (Route, WeatherAlert)
  → Reduced heap allocation
  → Faster equality checks

Final Fields
  → Immutable objects
  → Compiler optimizations
  → Safer concurrency

Smart Caching
  → Session-scoped (cleared on navigation)
  → Bounded size (10 searches max)
  → Lazy loading (on-demand)
```

---

## Security Considerations

### Input Validation

```dart
_isValidLocationString() checks:
  ✓ Not null or empty
  ✓ Not contains "rain" (weather word)
  ✓ Not contains "sunny" (weather word)
  ✓ Not contains "cloudy" (weather word)
  ✓ Not contains "weather" (weather word)
  ✓ Not contains "null" (invalid)
  ✓ Not contains "undefined" (invalid)
  ✓ Not contains "unknown location" (invalid)
```

### API Security

```
All requests include:
  • User-Agent: RainSafeNavigator/2.0
  • Accept-Language: en-US,en;q=0.9
  • Accept: application/json

No sensitive data:
  • Location history not stored (except 10 searches)
  • No user authentication
  • All APIs are public (no secrets)
```

---

## Future Extensibility

### Firebase Integration Points

```dart
// 1. Hazard Report Submission
HazardReport.toJson()
  ↓ Firebase Realtime Database
    /hazards/{timestamp}/{userId}

// 2. Real-Time Hazard Map
FirebaseDatabase.ref('hazards')
  .onValue
  .listen((event) {
    // Update map markers
  })

// 3. User Contribution Tracking
await FirebaseFirestore.collection('users')
  .doc(userId)
  .update({'hazardsReported': increment(1)})
```

### Custom Event Tracking

```dart
// Analytics ready
// await Analytics.logEvent(
//   name: 'route_calculated',
//   parameters: {
//     'distance_km': route.distanceMeters / 1000,
//     'risk_level': route.riskLevel,
//     'has_weather': route.isRaining,
//   },
// );
```

---

## Deployment Architecture

### Build Variants

```
Debug
├─ Full logging (ErrorHandler.logError)
├─ All analytics enabled
└─ Slower performance (expected)

Release
├─ Optimized build (tree-shaking)
├─ Const constructors (minified)
├─ Removed debug symbols
└─ Full performance
```

### Version Management

```
v2.0.0
├─ Major: Type-safe redesign
├─ Minor: New hazard feature
└─ Patch: Bug fixes & optimizations
```

---

**Architecture Last Updated**: January 2026 | **Version**: 2.0.0