// Firebase settings for the "clone-2353a" project, written by hand from the
// project's web app config (same shape `flutterfire configure` generates).
//
// Only a web app is registered in that project, so Android uses the web
// app's id for now. Firestore and Auth work this way; for a proper Android
// setup, register an Android app (package `com.example.real_world_exploration`)
// in the Firebase console and run `flutterfire configure`, which replaces this
// file and adds android/app/google-services.json.
//
// These values identify the project; they are not secrets. Access to data is
// controlled by the project's Firestore security rules.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        // iOS has no registered app yet, and Firebase doesn't support Windows
        // or Linux desktop. main.dart catches this and runs without Social.
        throw UnsupportedError(
          'Firebase is not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyApef2eESqK5HwdLc2wBrNVnd757ez_U4w',
    appId: '1:933831748841:web:1235e32ca012afd4d49478',
    messagingSenderId: '933831748841',
    projectId: 'clone-2353a',
    authDomain: 'clone-2353a.firebaseapp.com',
    storageBucket: 'clone-2353a.firebasestorage.app',
    measurementId: 'G-L5P9KWX63M',
  );

  /// Temporary: the web app's id until an Android app is registered.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyApef2eESqK5HwdLc2wBrNVnd757ez_U4w',
    appId: '1:933831748841:web:1235e32ca012afd4d49478',
    messagingSenderId: '933831748841',
    projectId: 'clone-2353a',
    storageBucket: 'clone-2353a.firebasestorage.app',
  );
}
