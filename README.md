# Rain Safe Navigator v2.0

**Professional Weather-Aware Navigation with Crowd-Sourced Safety**

## Overview

Rain Safe Navigator is a production-ready Flutter application that provides intelligent route planning based on real-time weather analysis. The v2.0 update brings professional engineering standards, strict English localization, type-safe architecture, and crowd-sourced hazard reporting.

---

## 🎯 What's New in v2.0

### 1. **Strict English Localization**
- ✅ All HTTP requests include `Accept-Language: en-US,en;q=0.9` headers
- ✅ Map tiles upgraded to CartoDB Voyager (professional, English-optimized labels)
- ✅ Voice guidance forced to English (en-IN) with Google TTS engine
- ✅ No system language override—always English regardless of device settings

### 2. **Engineering Ground Standards**
- ✅ **Type Safety**: New `RouteModel`, `NavigationStep`, `WeatherAlert`, `GeocodingResult`, `HazardReport` classes
- ✅ **Error Handling**: Professional `ErrorHandler` utility with user-friendly SnackBars and dialogs
- ✅ **Linter Compliance**: Strict analysis rules (`prefer_const_constructors`, `prefer_final_fields`, `always_declare_return_types`, etc.)
- ✅ **Logging**: Proper error logging with `ErrorHandler.logError()` instead of `debugPrint()`

### 3. **Crowd-Sourced Safety Feature**
- ✅ **Report Hazard Button**: Visible only during active navigation
- ✅ **Three Report Types**: Waterlogging, Accident, Road Block
- ✅ **Location Tracking**: Reports automatically include GPS coordinates
- ✅ **Firebase-Ready**: Mock backend structure ready for Firebase integration

### 4. **Reliability & Edge Cases**
- ✅ **Strict Input Validation**: Blocks "rain", "weather", "sunny", "null", "undefined"
- ✅ **Graceful Fallback**: Weather API failures default to "Unknown Safety" instead of crashing
- ✅ **Ocean/Unreachable Detection**: Shows friendly error dialog when route crosses water
- ✅ **Timeout Protection**: All API calls have 10-15 second timeouts

---

## 📦 Architecture

### New Type-Safe Models (`lib/models/route_model.dart`)
```dart
// Strongly typed route representation
RouteModel {
  List<LatLng> points,
  double distanceMeters,
  double durationSeconds,
  List<NavigationStep> steps,
  bool isRaining,
  String riskLevel,
  List<WeatherAlert> weatherAlerts,
}

// Navigation instructions with validation
NavigationStep {
  String instruction,
  String maneuverType,
  double distance,
  List<double> location,
}

// Weather alerts with type safety
WeatherAlert {
  LatLng point,
  int weatherCode,
  String description,
  double temperature,
  String time,
}

// Hazard reporting structure
HazardReport {
  LatLng location,
  String hazardType, // 'Waterlogging', 'Accident', 'RoadBlock'
  DateTime timestamp,
}
```

### Error Handler Utility (`lib/utils/error_handler.dart`)
```dart
// User-friendly error messages with color-coded SnackBars
ErrorHandler.showError(context, 'Network error')     // Red
ErrorHandler.showSuccess(context, 'Route found')     // Green
ErrorHandler.showWarning(context, 'Rain detected')   // Orange
ErrorHandler.showErrorDialog(context, title, msg)    // Dialog

// Professional logging
ErrorHandler.logError('Tag', 'Error message')
```

### Refactored API Service (`lib/services/api_service.dart`)
- **English Headers**: All requests include language preference
- **Typed Returns**: `getSafeRoutesOptions()` returns `List<RouteModel>` instead of `List<Map<dynamic>>`
- **Comprehensive Error Handling**: Proper exception logging and user-friendly messages
- **Validated Input**: `_isValidLocationString()` prevents bad data before API calls

---

## 🗺️ Key Features

### 1. Multi-Route Safety Analysis
- Fetches 3 alternative routes from OSRM
- Analyzes weather for each route at 8 waypoints
- Sorts by safety first, then speed

### 2. Real-Time Weather Integration
- Detects rain codes (51-67, 80-82, 95-99)
- Shows temperature markers on map
- Updates every 40-50m during navigation

### 3. Turn-by-Turn Voice Navigation
- Speaks instructions 40m before each turn
- Auto-advances to next step
- Proper instruction validation and fallback

### 4. Interactive Map
- **CartoDB Voyager tiles** (English labels, professional styling)
- Color-coded routes: Green (Safe), Orange (Medium), Red (High risk)
- Weather and location markers
- Fit-to-bounds camera control

### 5. Search History & Autocomplete
- Remembers last 10 searches locally
- Nominatim API suggestions on 3+ characters
- History matches displayed first

### 6. Hazard Reporting (v2.0)
- Report Waterlogging, Accidents, Road Blocks
- Auto-includes GPS location and timestamp
- Mock backend ready for Firebase integration

---

## 🔧 Technical Stack

| Component | Library | Version |
|-----------|---------|---------|
| Maps | flutter_map | ^7.0.0 |
| Location | geolocator | ^12.0.0 |
| Voice | flutter_tts | ^4.0.2 |
| Storage | shared_preferences | ^2.2.2 |
| Networking | http | ^1.2.1 |
| Coordinates | latlong2 | ^0.9.1 |

---

## 📋 API Integrations

### Nominatim (OpenStreetMap)
- **Endpoint**: `nominatim.openstreetmap.org`
- **Purpose**: Address geocoding & suggestions
- **Rate Limit**: 1.2 seconds between requests
- **Region**: Limited to India (countrycodes=in)

### OSRM (Open Source Routing Machine)
- **Endpoint**: `router.project-osrm.org`
- **Purpose**: Multi-route calculation with alternatives & instructions
- **Features**: Steps, turn-by-turn, ETA

### Open-Meteo
- **Endpoint**: `api.open-meteo.com`
- **Purpose**: Hourly weather forecasts
- **Data**: WMO weather codes, temperature

---

## 🛡️ Professional Standards Compliance

### Linter Rules (analysis_options.yaml)
✅ `prefer_const_constructors` - Immutability
✅ `prefer_final_fields` - Const where possible
✅ `always_declare_return_types` - Type clarity
✅ `avoid_print` - Use logging utilities
✅ `avoid_dynamic_calls` - Type safety
✅ `unused_import` & `unused_element` - Clean code
✅ And 20+ additional rules for consistency

### Code Quality Metrics
- **Type Safety**: 100% typed (no `dynamic` in critical paths)
- **Error Handling**: All try-catch blocks with user-friendly messages
- **Documentation**: Public APIs documented with comments
- **Testing**: Validated against invalid inputs (rain, weather, null, undefined)

---

## 🚀 Quick Start

### Prerequisites
```bash
Flutter 3.13+
Dart 3.1+
Android SDK 21+
iOS 11.0+
```

### Installation
```bash
cd project_1
flutter pub get
flutter run
```

### First Use
1. Allow location permissions
2. Enter destination
3. Select "Find Safe Route"
4. Review weather alerts
5. Start navigation for voice guidance

---

## 📝 Environment Configuration

### English Localization Headers
All API calls include:
```
Accept-Language: en-US,en;q=0.9
User-Agent: RainSafeNavigator/2.0
```

### Voice Settings
```dart
language: 'en-IN'
speechRate: 0.5x
engine: 'com.google.android.tts'
```

### Map Tiles
```
CartoDB Voyager: https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png
```

---

## 🔄 Extensibility

### Firebase Integration (Coming Soon)
```dart
// Structure ready for:
// - Real-time hazard map
// - Community safety scores
// - Push alerts for reported hazards
// - User contributions tracking
```

### Backend API Migration
```dart
// Current: Mock hazard reports
// Future: POST to /api/hazards/{userId}
// with HazardReport.toJson()
```

---

## 📊 v2.0 Changelog

| Item | v1.0 | v2.0 | Status |
|------|------|------|--------|
| English Headers | ❌ | ✅ | Complete |
| CartoDB Map | ❌ | ✅ | Complete |
| Type Safety | ❌ | ✅ | Complete |
| Error Handler | ❌ | ✅ | Complete |
| Hazard Reporting | ❌ | ✅ | Complete |
| Linter Rules | ❌ | ✅ | Complete |
| Input Validation | ✅ | ✅ Enhanced | Complete |
| Voice Navigation | ✅ | ✅ English | Complete |
| Multi-Route Analysis | ✅ | ✅ | Complete |

---

## 🐛 Known Limitations

- Nominatim searches limited to India (`countrycodes=in`)
- Weather API free tier (no authentication)
- Map tiles require internet connectivity
- Voice navigation requires device speaker/headset

---

## 📧 Support & Feedback

For issues, feature requests, or improvements:
1. Check existing documentation
2. Review error logs with `ErrorHandler.logError()`
3. Validate input against `_isValidLocationString()`

---

## 📄 License

This project is part of the Rain Safe Navigator initiative for safer navigation.

---

**Last Updated**: January 2026 | **Version**: 2.0.0
