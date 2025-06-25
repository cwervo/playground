// lib/widgets/add_room_form.dart
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_service.dart';
import 'dart:math'; // For Random

class AddRoomForm extends StatefulWidget {
  const AddRoomForm({super.key});

  @override
  State<AddRoomForm> createState() => _AddRoomFormState();
}

class _AddRoomFormState extends State<AddRoomForm> {
  final _formKey = GlobalKey<FormState>();
  final _roomNameController = TextEditingController();
  final RoomService _roomService = RoomService();
  String? _selectedCoverPhotoPath; // Placeholder

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      final roomName = _roomNameController.text;
      // Simulate unique ID generation
      final roomId = DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(9999).toString();

      final newRoom = Room(
        id: roomId,
        name: roomName,
        coverPhotoPath: _selectedCoverPhotoPath ?? 'assets/images/default_room_cover.png',
        // taskIds will be empty by default
      );

      try {
        await _roomService.saveRoom(newRoom);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Room "$roomName" saved!')),
          );
          _roomNameController.clear();
          setState(() {
            _selectedCoverPhotoPath = null;
          });
          Navigator.of(context).pop(true); // Indicate success
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save room: ${e.toString()}')),
          );
        }
      }
    }
  }

  void _selectCoverPhoto() {
     // Placeholder for image selection logic
     // In a real app, this would use image_picker or similar
     setState(() {
         _selectedCoverPhotoPath = 'assets/images/sample_cover_${Random().nextInt(3) + 1}.jpg'; // Cycle through some samples
     });
     ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Simulated cover photo selection: $_selectedCoverPhotoPath')),
     );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextFormField(
            controller: _roomNameController,
            decoration: const InputDecoration(
              labelText: 'Room Name',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a room name';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
             icon: const Icon(Icons.photo_library),
             label: const Text('Select Cover Photo'),
             onPressed: _selectCoverPhoto,
          ),
          if (_selectedCoverPhotoPath != null)
             Padding(
                 padding: const EdgeInsets.only(top: 8.0),
                 child: Text('Selected: $_selectedCoverPhotoPath'),
             ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitForm,
            child: const Text('Create Room'),
          ),
        ],
      ),
    );
  }
}
