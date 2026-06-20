// File generated manually based on Firebase Console configuration.
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Same Firebase project as student_app (studysync-3fa09).
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyATsYwexjWiTVCN5v0UJg3tQrhhVrKGnYI',
    authDomain: 'studysync-3fa09.firebaseapp.com',
    projectId: 'studysync-3fa09',
    storageBucket: 'studysync-3fa09.firebasestorage.app',
    messagingSenderId: '879075674962',
    appId: '1:879075674962:web:67e78f41038926ca8fc88b',
    measurementId: 'G-C2Q6DZM077',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyATsYwexjWiTVCN5v0UJg3tQrhhVrKGnYI',
    appId: '1:879075674962:android:a80730a3055f022e8fc88b',
    messagingSenderId: '879075674962',
    projectId: 'studysync-3fa09',
    storageBucket: 'studysync-3fa09.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyATsYwexjWiTVCN5v0UJg3tQrhhVrKGnYI',
    appId: '1:879075674962:ios:235e87f9a91fe6b08fc88b',
    messagingSenderId: '879075674962',
    projectId: 'studysync-3fa09',
    storageBucket: 'studysync-3fa09.firebasestorage.app',
    iosBundleId: 'com.studyfinder.adminApp',
  );
}
