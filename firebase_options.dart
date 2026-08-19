// File generated manually — valores desde Firebase Console / google-services.json

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions no está configurado para web.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions no soporta esta plataforma.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDbVUmCZpvZz6xv14y_kOXMnbEhVVwAXQw',
    appId: '1:571773318972:android:f43b6ccb82b9b5ee501039',
    messagingSenderId: '571773318972',
    projectId: 'anv1-a4c74',
    storageBucket: 'anv1-a4c74.firebasestorage.app',
  );
}
