import 'package:flutter/material.dart';

/// Multi-language translation service supporting 8+ languages.
/// 
/// Supported languages:
/// - English (en)
/// - Hindi (hi)
/// - Telugu (te)
/// - Tamil (ta)
/// - Kannada (kn)
/// - Spanish (es)
/// - French (fr)
/// - Arabic (ar)
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  /// Translation database
  static final Map<String, Map<String, String>> _translations = {
    // ENGLISH
    'en': {
      'search_placeholder': 'Where to?',
      'search_current_location': 'Current Location',
      'route_found': 'Route found: {duration} min, {distance} km',
      'navigation_started': 'Navigation started',
      'navigation_stopped': 'Navigation stopped',
      'turn_instruction': 'In 40 meters, {instruction}',
      'arrive_destination': 'You have arrived at your destination',
      'recalculating': 'Recalculating route...',
      'no_route_found': 'No route found',
      'gps_unavailable': 'GPS unavailable',
      'start_navigation': 'Start',
      'stop_navigation': 'Stop',
      'alternatives': 'Alternatives',
      'safe_route': 'Safe Route',
      'fastest_route': 'Fastest',
      'shortest_route': 'Shortest',
      'traffic': 'Traffic',
      'rain': 'Rain',
      'language': 'Language',
      'vehicle': 'Vehicle',
      'recenter': 'Recenter',
      'duration': 'Duration',
      'distance': 'Distance',
      'eta': 'ETA',
      'high_risk': 'High Risk',
      'medium_risk': 'Medium Risk',
      'safe': 'Safe',
      'waterlogging': 'Waterlogging',
      'accident': 'Accident',
      'road_block': 'Road Block',
    },
    
    // HINDI
    'hi': {
      'search_placeholder': 'कहाँ जाना है?',
      'search_current_location': 'वर्तमान स्थान',
      'route_found': 'रास्ता मिला: {duration} मिनट, {distance} किमी',
      'navigation_started': 'नेविगेशन शुरू हो गया',
      'navigation_stopped': 'नेविगेशन रुक गया',
      'turn_instruction': '40 मीटर में, {instruction}',
      'arrive_destination': 'आप अपने गंतव्य पर पहुंच गए हैं',
      'recalculating': 'रास्ता फिर से गणना कर रहे हैं...',
      'no_route_found': 'कोई रास्ता नहीं मिला',
      'gps_unavailable': 'GPS उपलब्ध नहीं',
      'start_navigation': 'शुरू',
      'stop_navigation': 'रुकें',
      'alternatives': 'विकल्प',
      'safe_route': 'सुरक्षित रास्ता',
      'fastest_route': 'सबसे तेज़',
      'shortest_route': 'सबसे छोटा',
      'traffic': 'ट्रैफिक',
      'rain': 'बारिश',
      'language': 'भाषा',
      'vehicle': 'वाहन',
      'recenter': 'केंद्र',
      'duration': 'अवधि',
      'distance': 'दूरी',
      'eta': 'पहुंचने का समय',
      'high_risk': 'उच्च जोखिम',
      'medium_risk': 'मध्यम जोखिम',
      'safe': 'सुरक्षित',
      'waterlogging': 'जलभराव',
      'accident': 'दुर्घटना',
      'road_block': 'सड़क अवरोध',
    },
    
    // TELUGU
    'te': {
      'search_placeholder': 'ఎక్కడికి వెళ్ళాలి?',
      'search_current_location': 'ప్రస్తుత స్థానం',
      'route_found': 'మార్గం దొరికింది: {duration} నిమిషాలు, {distance} కిమీ',
      'navigation_started': 'నావిగేషన్ ప్రారంభమైంది',
      'navigation_stopped': 'నావిగేషన్ ఆగిపోయింది',
      'turn_instruction': '40 మీటర్లలో, {instruction}',
      'arrive_destination': 'మీరు మీ గమ్యాన్ని చేరుకున్నారు',
      'recalculating': 'మార్గాన్ని మళ్లీ లెక్కిస్తోంది...',
      'no_route_found': 'మార్గం కనుగొనబడలేదు',
      'gps_unavailable': 'GPS అందుబాటులో లేదు',
      'start_navigation': 'ప్రారంభం',
      'stop_navigation': 'ఆపు',
      'alternatives': 'ప్రత్యామ్నాయాలు',
      'safe_route': 'సురక్షిత మార్గం',
      'fastest_route': 'వేగవంతమైనది',
      'shortest_route': 'చిన్నది',
      'traffic': 'ట్రాఫిక్',
      'rain': 'వర్షం',
      'language': 'భాష',
      'vehicle': 'వాహనం',
      'recenter': 'కేంద్రం',
      'duration': 'వ్యవధి',
      'distance': 'దూరం',
      'eta': 'చేరుకునే సమయం',
      'high_risk': 'అధిక ప్రమాదం',
      'medium_risk': 'మధ్యస్థ ప్రమాదం',
      'safe': 'సురక్షితం',
      'waterlogging': 'నీటి జలదరణ',
      'accident': 'ప్రమాదం',
      'road_block': 'రోడ్డు నిరోధం',
    },
    
    // TAMIL
    'ta': {
      'search_placeholder': 'எங்கு செல்ல வேண்டும்?',
      'search_current_location': 'தற்போதைய இடம்',
      'route_found': 'பாதை கிடைத்தது: {duration} நிமிடங்கள், {distance} கிமீ',
      'navigation_started': 'வழிகாட்டுதல் தொடங்கியது',
      'navigation_stopped': 'வழிகாட்டுதல் நிறுத்தப்பட்டது',
      'turn_instruction': '40 மீட்டரில், {instruction}',
      'arrive_destination': 'நீங்கள் உங்கள் இலக்கை அடைந்துவிட்டீர்கள்',
      'recalculating': 'பாதையை மீண்டும் கணக்கிடுகிறது...',
      'no_route_found': 'பாதை கிடைக்கவில்லை',
      'gps_unavailable': 'GPS கிடைக்கவில்லை',
      'start_navigation': 'தொடங்கு',
      'stop_navigation': 'நிறுத்து',
      'alternatives': 'மாற்றுகள்',
      'safe_route': 'பாதுகாப்பான பாதை',
      'fastest_route': 'வேகமானது',
      'shortest_route': 'குறுகியது',
      'traffic': 'போக்குவரத்து',
      'rain': 'மழை',
      'language': 'மொழி',
      'vehicle': 'வாகனம்',
      'recenter': 'மையம்',
      'duration': 'காலம்',
      'distance': 'தூரம்',
      'eta': 'வரும் நேரம்',
      'high_risk': 'உயர் ஆபத்து',
      'medium_risk': 'நடுத்தர ஆபத்து',
      'safe': 'பாதுகாப்பான',
      'waterlogging': 'நீர் தேக்கம்',
      'accident': 'விபத்து',
      'road_block': 'சாலை தடை',
    },
    
    // KANNADA
    'kn': {
      'search_placeholder': 'ಎಲ್ಲಿಗೆ ಹೋಗಬೇಕು?',
      'search_current_location': 'ಪ್ರಸ್ತುತ ಸ್ಥಳ',
      'route_found': 'ಮಾರ್ಗ ಕಂಡುಬಂದಿದೆ: {duration} ನಿಮಿಷಗಳು, {distance} ಕಿಮೀ',
      'navigation_started': 'ನ್ಯಾವಿಗೇಶನ್ ಪ್ರಾರಂಭವಾಯಿತು',
      'navigation_stopped': 'ನ್ಯಾವಿಗೇಶನ್ ನಿಲ್ಲಿಸಲಾಗಿದೆ',
      'turn_instruction': '40 ಮೀಟರ್‌ಗಳಲ್ಲಿ, {instruction}',
      'arrive_destination': 'ನೀವು ನಿಮ್ಮ ಗಮ್ಯಸ್ಥಾನವನ್ನು ತಲುಪಿದ್ದೀರಿ',
      'recalculating': 'ಮಾರ್ಗವನ್ನು ಮರುಲೆಕ್ಕಾಚಾರ ಮಾಡಲಾಗುತ್ತಿದೆ...',
      'no_route_found': 'ಯಾವುದೇ ಮಾರ್ಗ ಕಂಡುಬಂದಿಲ್ಲ',
      'gps_unavailable': 'GPS ಲಭ್ಯವಿಲ್ಲ',
      'start_navigation': 'ಪ್ರಾರಂಭಿಸಿ',
      'stop_navigation': 'ನಿಲ್ಲಿಸಿ',
      'alternatives': 'ಪರ್ಯಾಯಗಳು',
      'safe_route': 'ಸುರಕ್ಷಿತ ಮಾರ್ಗ',
      'fastest_route': 'ವೇಗವಾದದ್ದು',
      'shortest_route': 'ಚಿಕ್ಕದ್ದು',
      'traffic': 'ಟ್ರಾಫಿಕ್',
      'rain': 'ಮಳೆ',
      'language': 'ಭಾಷೆ',
      'vehicle': 'ವಾಹನ',
      'recenter': 'ಕೇಂದ್ರ',
      'duration': 'ಅವಧಿ',
      'distance': 'ದೂರ',
      'eta': 'ತಲುಪುವ ಸಮಯ',
      'high_risk': 'ಹೆಚ್ಚಿನ ಅಪಾಯ',
      'medium_risk': 'ಮಧ್ಯಮ ಅಪಾಯ',
      'safe': 'ಸುರಕ್ಷಿತ',
      'waterlogging': 'ನೀರು ಕಟ್ಟುವಿಕೆ',
      'accident': 'ಅಪಘಾತ',
      'road_block': 'ರಸ್ತೆ ತಡೆ',
    },
    
    // SPANISH
    'es': {
      'search_placeholder': '¿A dónde vas?',
      'search_current_location': 'Ubicación actual',
      'route_found': 'Ruta encontrada: {duration} min, {distance} km',
      'navigation_started': 'Navegación iniciada',
      'navigation_stopped': 'Navegación detenida',
      'turn_instruction': 'En 40 metros, {instruction}',
      'arrive_destination': 'Has llegado a tu destino',
      'recalculating': 'Recalculando ruta...',
      'no_route_found': 'No se encontró ruta',
      'gps_unavailable': 'GPS no disponible',
      'start_navigation': 'Iniciar',
      'stop_navigation': 'Detener',
      'alternatives': 'Alternativas',
      'safe_route': 'Ruta segura',
      'fastest_route': 'Más rápida',
      'shortest_route': 'Más corta',
      'traffic': 'Tráfico',
      'rain': 'Lluvia',
      'language': 'Idioma',
      'vehicle': 'Vehículo',
      'recenter': 'Recentrar',
      'duration': 'Duración',
      'distance': 'Distancia',
      'eta': 'Hora llegada',
      'high_risk': 'Alto riesgo',
      'medium_risk': 'Riesgo medio',
      'safe': 'Seguro',
      'waterlogging': 'Inundación',
      'accident': 'Accidente',
      'road_block': 'Bloqueo de carretera',
    },
    
    // FRENCH
    'fr': {
      'search_placeholder': 'Où allez-vous?',
      'search_current_location': 'Position actuelle',
      'route_found': 'Itinéraire trouvé: {duration} min, {distance} km',
      'navigation_started': 'Navigation démarrée',
      'navigation_stopped': 'Navigation arrêtée',
      'turn_instruction': 'Dans 40 mètres, {instruction}',
      'arrive_destination': 'Vous êtes arrivé à destination',
      'recalculating': 'Recalcul de l\'itinéraire...',
      'no_route_found': 'Aucun itinéraire trouvé',
      'gps_unavailable': 'GPS indisponible',
      'start_navigation': 'Démarrer',
      'stop_navigation': 'Arrêter',
      'alternatives': 'Alternatives',
      'safe_route': 'Itinéraire sûr',
      'fastest_route': 'Plus rapide',
      'shortest_route': 'Plus court',
      'traffic': 'Trafic',
      'rain': 'Pluie',
      'language': 'Langue',
      'vehicle': 'Véhicule',
      'recenter': 'Recentrer',
      'duration': 'Durée',
      'distance': 'Distance',
      'eta': 'Heure d\'arrivée',
      'high_risk': 'Risque élevé',
      'medium_risk': 'Risque moyen',
      'safe': 'Sûr',
      'waterlogging': 'Inondation',
      'accident': 'Accident',
      'road_block': 'Blocage routier',
    },
    
    // ARABIC
    'ar': {
      'search_placeholder': 'إلى أين تذهب؟',
      'search_current_location': 'الموقع الحالي',
      'route_found': 'تم العثور على الطريق: {duration} دقيقة، {distance} كم',
      'navigation_started': 'بدأ الملاحة',
      'navigation_stopped': 'توقفت الملاحة',
      'turn_instruction': 'في 40 متر، {instruction}',
      'arrive_destination': 'لقد وصلت إلى وجهتك',
      'recalculating': 'إعادة حساب الطريق...',
      'no_route_found': 'لم يتم العثور على طريق',
      'gps_unavailable': 'GPS غير متاح',
      'start_navigation': 'ابدأ',
      'stop_navigation': 'توقف',
      'alternatives': 'البدائل',
      'safe_route': 'طريق آمن',
      'fastest_route': 'الأسرع',
      'shortest_route': 'الأقصر',
      'traffic': 'حركة المرور',
      'rain': 'مطر',
      'language': 'اللغة',
      'vehicle': 'مركبة',
      'recenter': 'إعادة التمركز',
      'duration': 'المدة',
      'distance': 'المسافة',
      'eta': 'وقت الوصول',
      'high_risk': 'خطر عالي',
      'medium_risk': 'خطر متوسط',
      'safe': 'آمن',
      'waterlogging': 'تجمع المياه',
      'accident': 'حادث',
      'road_block': 'حاجز طريق',
    },
  };

  /// Get all supported languages
  List<Language> getSupportedLanguages() {
    return [
      Language(code: 'en', name: 'English', nativeName: 'English', flag: '🇬🇧'),
      Language(code: 'hi', name: 'Hindi', nativeName: 'हिंदी', flag: '🇮🇳'),
      Language(code: 'te', name: 'Telugu', nativeName: 'తెలుగు', flag: '🇮🇳'),
      Language(code: 'ta', name: 'Tamil', nativeName: 'தமிழ்', flag: '🇮🇳'),
      Language(code: 'kn', name: 'Kannada', nativeName: 'ಕನ್ನಡ', flag: '🇮🇳'),
      Language(code: 'es', name: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
      Language(code: 'fr', name: 'French', nativeName: 'Français', flag: '🇫🇷'),
      Language(code: 'ar', name: 'Arabic', nativeName: 'العربية', flag: '🇸🇦'),
    ];
  }

  /// Get TTS language code for Flutter TTS
  String getTTSCode(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'en-US';
      case 'hi':
        return 'hi-IN';
      case 'te':
        return 'te-IN';
      case 'ta':
        return 'ta-IN';
      case 'kn':
        return 'kn-IN';
      case 'es':
        return 'es-ES';
      case 'fr':
        return 'fr-FR';
      case 'ar':
        return 'ar-SA';
      default:
        return 'en-US';
    }
  }

  /// Translate a key with optional arguments
  String translate(
    String languageCode,
    String key, {
    Map<String, dynamic>? args,
  }) {
    final languageMap = _translations[languageCode] ?? _translations['en']!;
    String text = languageMap[key] ?? key;

    // Replace arguments
    if (args != null) {
      args.forEach((argKey, argValue) {
        text = text.replaceAll('{$argKey}', argValue.toString());
      });
    }

    return text;
  }

  /// Check if language is RTL (Right-to-Left)
  bool isRTL(String languageCode) {
    return languageCode == 'ar';
  }

  /// Get text direction
  TextDirection getTextDirection(String languageCode) {
    return isRTL(languageCode) ? TextDirection.rtl : TextDirection.ltr;
  }
}

/// Language model
class Language {
  final String code;
  final String name;
  final String nativeName;
  final String flag;

  Language({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });
}
