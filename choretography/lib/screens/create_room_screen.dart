// lib/screens/create_room_screen.dart
import 'package:flutter/material.dart';
import '../widgets/add_room_form.dart'; // Adjusted import

class CreateRoomScreen extends StatelessWidget {
  const CreateRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Room'),
      ),
      body: const SingleChildScrollView( // Added SingleChildScrollView
        padding: EdgeInsets.all(16.0), // Added padding
        child: AddRoomForm(),
      ),
    );
  }
}
