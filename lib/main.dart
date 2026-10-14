import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'screens/camera_detector_screen.dart';

List<CameraDescription> _cameras = <CameraDescription>[];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Erreur lors de la récupération des caméras : ${e.description}');
  }

  runApp(const VinylApp());
}

class VinylApp extends StatelessWidget {
  const VinylApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vinyl Groove Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.amber,
          secondary: Colors.amberAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black87,
          elevation: 0,
        ),
      ),
      home: CameraDetectorScreen(cameras: _cameras),
    );
  }
}
