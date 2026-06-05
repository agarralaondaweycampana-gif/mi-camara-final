import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAs-Generica-ElMarian-UsaTuProyecto',
    appId: '1:mi-camara-de-seguridad-5bfc2',
    messagingSenderId: '123456789',
    projectId: 'mi-camara-de-seguridad-5bfc2',
    storageBucket: 'mi-camara-de-seguridad-5bfc2.appspot.com',
  );
}
