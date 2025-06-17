import 'package:flutter/material.dart';
import '../widgets/add_room_form.dart'; // Adjust path as necessary

class CreateRoomScreen extends StatelessWidget {
  const CreateRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Room'),
        // You might want to add a leading back button if this screen
        // is pushed onto a navigation stack.
        // leading: IconButton(
        //   icon: const Icon(Icons.arrow_back),
        //   onPressed: () => Navigator.of(context).pop(),
        // ),
      ),
      body: const Center( // Center the AddRoomForm
        child: SingleChildScrollView( // Allow scrolling if content overflows
          padding: EdgeInsets.all(16.0), // Add some padding around the form
          child: AddRoomForm(),
        ),
      ),
    );
  }
}
