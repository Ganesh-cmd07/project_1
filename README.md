# RainSafe Navigator 🌧️🗺️

**RainSafe Navigator** is a weather-intelligent, cross-platform navigation application built with Flutter. Unlike traditional navigation apps, RainSafe proactively integrates real-time weather monitoring and user-reported road hazards into the routing algorithms. It is designed to ensure maximum commuter safety under adverse weather conditions, offering dynamic rerouting, real-time hazard warnings, and multilingual voice guidance.

---

## 🚀 Key Features

*   **Intelligent Routing & Mapping**: Leverages powerful open-source mapping (`flutter_map` & `latlong2`) and optimized routing capabilities to guide users safely from point A to point B.
*   **Weather overlays & Monitoring**: Features a dedicated `weather_overlay` that displays live atmospheric data directly on the navigation screen to preemptively identify heavy rainfall or poor visibility.
*   **Crowdsourced Hazard Reporting**: Integrates deeply with Firebase Authentication and Cloud Firestore to allow users to drop markers for floods, accidents, or blocked roads. The app supports anonymous login to reduce friction and encourage community reports.
*   **Turn-by-Turn Voice Guidance**: Comes equipped with text-to-speech engine integration (`flutter_tts`) for eyes-free navigation.
*   **Multilingual Support**: Supports seamless on-the-fly language translation and selection (`translation_service`), ensuring critical safety alerts are accessible to a broader user base.
*   **Vehicle & Compass Tracking**: Employs live GPS (`geolocator`), custom vehicle markers, and precise heading calculations (`flutter_compass`) for a premium navigation experience entirely in an immersive Dark Mode.

---

## 🛠️ Technology Stack

*   **Framework**: [Flutter](https://flutter.dev/) (SDK >=3.0.0)
*   **Programming Language**: Dart
*   **Backend & Cloud Database**: [Firebase Core, Auth, Firestore](https://firebase.google.com/)
*   **Maps & Geolocation**: `flutter_map`, `geolocator`, OpenStreetMap
*   **Audio / Accessibility**: `flutter_tts` 
*   **Networking & Async Tasks**: `http`, `shared_preferences`

---

## 📂 Project Architecture

The application rigorously follows a modular architecture inside the `/lib` directory to maximize scalability, testing, and debugging speed:

```text
lib/
├── models/         # Data representation objects (e.g., RouteModel)
├── screens/        # Primary UI views (HomeScreen, MapScreen)
├── services/       # App core logic (APIService, FirebaseService, TranslationService)
├── theme/          # UI Styling and centralized app themes
├── utils/          # Helper modules and error handlers (ErrorHandler)
├── widgets/        # Reusable custom UI components (PremiumBottomSheet, WeatherOverlay, etc.)
└── main.dart       # Core entry point and Firebase Initialization block
```

---

## ⚙️ Getting Started

### Prerequisites
Before running this project locally, ensure you have the following installed:
1.  **Flutter SDK** (v3.0.0 or higher) - [Installation Guide](https://docs.flutter.dev/get-started/install)
2.  **Dart SDK** (Bundled with Flutter)
3.  **Firebase CLI** (For backend syncing)
4.  **Android Studio / Xcode** (For emulator rendering and native builds)

### Installation

1.  **Clone the Repository** (If applicable):
    ```bash
    git clone https://github.com/your-username/rainsafe-navigator.git
    cd rainsafe-navigator
    ```

2.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase** (If setting up a new Firebase instance):
    ```bash
    flutterfire configure
    ```
    *(Ensure you configure Authentication (Anonymous) and Firestore inside your Firebase Console).*

4.  **Run the Application**:
    ```bash
    flutter run
    ```

---

## 🛡️ License & Contributing

This project is proprietary and currently not open for external contributions without explicit permission. All source code is built and maintained by the primary repository owner. 

---
*Developed with using Flutter.*