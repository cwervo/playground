import 'package:flutter/material.dart';
import '../services/room_service.dart'; // Adjust path as necessary
import '../models/room_model.dart';    // Adjust path as necessary
import './create_room_screen.dart';   // Adjust path as necessary
import './room_details_screen.dart'; // Added import for RoomDetailsScreen

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final RoomService _roomService = RoomService();
  // late Future<List<Room>> _roomsFuture; // Replaced by _currentRooms for mutable state
  List<Room> _currentRooms = []; // Holds the currently displayed (and reorderable) rooms
  bool _isLoading = true; // To manage loading state separately
  String? _error; // To hold error messages

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // getAllRooms from RoomService now returns the rooms in the saved order (if any).
      _currentRooms = await _roomService.getAllRooms();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // _refreshRoomsAfterModification calls _fetchRooms which now gets pre-sorted rooms.
  void _refreshRoomsAfterModification() {
     _fetchRooms();
  }


  void _navigateToCreateRoomScreen() async {
    // Await for the CreateRoomScreen to pop, then reload rooms
    // as a new room might have been added.
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
    );

    // Reload rooms if the screen was popped
    _refreshRoomsAfterModification();
  }

  void _onReorder(int oldIndex, int newIndex) async { // Made async
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final Room item = _currentRooms.removeAt(oldIndex);
      _currentRooms.insert(newIndex, item);
    });
    // Persist the new order
    final List<String> roomIds = _currentRooms.map((room) => room.id).toList();
    try {
      await _roomService.saveRoomOrder(roomIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving room order: $e')),
        );
      }
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      return Center(child: Text('Error: $_error'));
    } else if (_currentRooms.isEmpty) {
      return const Center(
        child: Text(
          'No rooms yet. Tap the "+" button to add one!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ReorderableListView.builder(
      itemCount: _currentRooms.length,
      itemBuilder: (context, index) {
        final room = _currentRooms[index];
        return Card(
          key: ValueKey(room.id), // Important for ReorderableListView
          margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar( // Placeholder for cover photo
              backgroundColor: Colors.primaries[index % Colors.primaries.length],
              child: const Icon(Icons.room_service_outlined, color: Colors.white),
            ),
            title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Tasks: ${room.taskIds.length}'), // Example subtitle
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () async {
                final String roomName = room.name; // Store room name for SnackBar before it's potentially removed
                bool confirmDelete = await showDialog(
                  context: context,
                  builder: (BuildContext ctx) {
                    return AlertDialog(
                      title: const Text('Confirm Delete'),
                      content: Text('Are you sure you want to delete "${room.name}"?'),
                      actions: <Widget>[
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                        TextButton(
                          child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    );
                  },
                ) ?? false;

                if (confirmDelete) {
                  // The RoomService.deleteRoom method now also handles updating the order key.
                  await _roomService.deleteRoom(room.id);

                  // Refresh the list from the service, which will provide the updated order.
                  _refreshRoomsAfterModification();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Room "$roomName" deleted.')),
                    );
                  }
                }
              },
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RoomDetailsScreen(room: room),
                ),
              );
            },
          ),
        );
      },
      onReorder: _onReorder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choretography'),
      ),
      body: _buildBody(), // Use a helper method for the body
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateRoomScreen,
        tooltip: 'Add Room',
        child: const Icon(Icons.add),
      ),
    );
  }
}
