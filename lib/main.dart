import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const TopRatedPlacesApp());
}

class TopRatedPlacesApp extends StatelessWidget {
  const TopRatedPlacesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top Rated Places',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
