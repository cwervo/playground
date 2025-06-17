import 'package:flutter/material.dart';
import '../services/room_service.dart'; // Added import for RoomService
import '../models/room_model.dart'; // Added import for Room model

class AddRoomForm extends StatefulWidget {
  const AddRoomForm({super.key});

  @override
  State<AddRoomForm> createState() => _AddRoomFormState();
}

class _AddRoomFormState extends State<AddRoomForm> {
  final _formKey = GlobalKey<FormState>();
  final _roomNameController = TextEditingController();
  String? _selectedCoverPhotoPath; // Placeholder for selected photo path
  final RoomService _roomService = RoomService(); // Instantiate RoomService

  // Make _submitForm async to await saveRoom
  void _submitForm() async {
    if (_formKey.currentState!.validate()) {
      // Form is valid, process the data
      final roomName = _roomNameController.text;
      // Use a default if no photo selected, or handle as required by Room model
      final coverPhotoPath = _selectedCoverPhotoPath ?? 'assets/images/default_room_cover.png';

      // Create a unique ID for the room
      final String roomId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create Room object
      final newRoom = Room(
        id: roomId,
        name: roomName,
        coverPhotoPath: coverPhotoPath,
        // taskIds will default to empty list in the Room model constructor
      );

      try {
        await _roomService.saveRoom(newRoom);

        // Clear the form after submission for good UX
        _roomNameController.clear();
        setState(() {
          _selectedCoverPhotoPath = null;
        });

        if (mounted) { // Check if the widget is still in the tree
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Room "$roomName" saved!')),
          );
        }
      } catch (e) {
         if (mounted) { // Check if the widget is still in the tree
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error saving room: $e')),
            );
         }
        print('Error saving room: $e');
      }
    }
  }

  void _selectCoverPhoto() {
    // Placeholder for image picking logic
    // In a real app, this would use image_picker or similar
    setState(() {
      _selectedCoverPhotoPath = 'dummy/path/to/image.jpg'; // Simulate selection
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cover photo selection simulated.')),
    );
  }

  @override
  void dispose() {
    _roomNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
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
              onPressed: _selectCoverPhoto,
              icon: const Icon(Icons.photo_library),
              label: const Text('Select Cover Photo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (_selectedCoverPhotoPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text('Selected: $_selectedCoverPhotoPath'),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Create Room'),
            ),
          ],
        ),
      ),
    );
  }
}
