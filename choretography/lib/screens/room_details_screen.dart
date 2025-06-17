import 'package:flutter/material.dart';
import '../models/room_model.dart'; // Adjust path as necessary

class RoomDetailsScreen extends StatelessWidget {
  final Room room;

  const RoomDetailsScreen({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(room.name),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Room Name: ${room.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              'Cover Photo Path:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            // Placeholder for the image - In a real app, use Image.asset or Image.file
            (room.coverPhotoPath.isNotEmpty && room.coverPhotoPath != 'assets/images/default_room_cover.png')
                ? Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      // In a real app, you might use:
                      // image: DecorationImage(
                      //   image: AssetImage(room.coverPhotoPath), // Or FileImage(File(room.coverPhotoPath))
                      //   fit: BoxFit.cover,
                      // ),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                         const Icon(Icons.image, size: 50, color: Colors.grey),
                         const SizedBox(height: 8),
                         Text(room.coverPhotoPath, textAlign: TextAlign.center),
                      ],
                    )
                  )
                : Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      color: Colors.grey[200],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'No cover photo selected\nor using default.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
            const SizedBox(height: 16),
            Text(
              'Task IDs:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            room.taskIds.isEmpty
                ? const Text('No tasks associated with this room yet.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: room.taskIds.map((id) => Text('- $id')).toList(),
                  ),
          ],
        ),
      ),
    );
  }
}
