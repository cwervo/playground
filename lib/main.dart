import 'package:flutter/material.dart';
// Adjust the import path based on your actual project name and structure.
// If pubspec.yaml uses 'choretography_app', this might be:
// import 'package:choretography_app/screens/main_screen.dart';
// For now, assuming MainScreen will be directly accessible via a relative path
// after files are properly organized.
import 'screens/main_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Choretography App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // visualDensity is being deprecated.
        // Use colorSchemeSeed or colorScheme for modern theming.
        // For now, keeping primarySwatch as per original request,
        // but this is an area for future update.
        // visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainScreen(), // Assuming MainScreen is the entry point
    );
  }
}
