// lib/screens/main_screen.dart
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_service.dart';
import './create_room_screen.dart';
import './room_details_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final RoomService _roomService = RoomService();
  List<Room> _currentRooms = [];
  bool _isLoading = true;
  String? _error;

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
      final rooms = await _roomService.getAllRooms();
      setState(() {
        _currentRooms = rooms;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Failed to load rooms: ${e.toString()}";
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshRoomsAfterModification() async {
     await _fetchRooms();
  }

  void _navigateToCreateRoomScreen() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateRoomScreen()),
    );
    if (result == true && mounted) { // Check if a room was created/modified
      _refreshRoomsAfterModification();
    }
  }

  void _navigateToRoomDetailsScreen(Room room) {
     Navigator.push(
       context,
       MaterialPageRoute(builder: (context) => RoomDetailsScreen(room: room)),
     );
  }

  Future<void> _deleteRoom(String roomId) async {
     bool? confirmed = await showDialog<bool>(
         context: context,
         builder: (BuildContext context) {
             return AlertDialog(
                 title: const Text('Confirm Delete'),
                 content: const Text('Are you sure you want to delete this room and all its tasks?'),
                 actions: <Widget>[
                     TextButton(
                         onPressed: () => Navigator.of(context).pop(false),
                         child: const Text('Cancel'),
                     ),
                     TextButton(
                         onPressed: () => Navigator.of(context).pop(true),
                         child: const Text('Delete'),
                     ),
                 ],
             );
         },
     );

     if (confirmed == true) {
         try {
             await _roomService.deleteRoom(roomId);
             // Optionally, delete associated tasks if not handled by RoomService or backend
             // final taskService = TaskService(); // Assuming TaskService is available
             // final tasksInRoom = await taskService.getTasksForRoom(roomId);
             // for (var task in tasksInRoom) {
             // await taskService.deleteTask(task.id);
             // }
             _refreshRoomsAfterModification();
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Room deleted successfully!')),
                 );
             }
         } catch (e) {
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Failed to delete room: ${e.toString()}')),
                 );
             }
         }
     }
  }

  void _onReorder(int oldIndex, int newIndex) async {
     setState(() {
         if (newIndex > oldIndex) {
             newIndex -= 1;
         }
         final Room item = _currentRooms.removeAt(oldIndex);
         _currentRooms.insert(newIndex, item);
     });
     try {
         List<String> roomIds = _currentRooms.map((room) => room.id).toList();
         await _roomService.saveRoomOrder(roomIds);
     } catch (e) {
         if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
                 SnackBar(content: Text('Failed to save room order: ${e.toString()}')),
             );
             // Optionally, revert order if save fails, or re-fetch
             _fetchRooms();
         }
     }
  }

  Widget _buildBody() {
     if (_isLoading) {
         return const Center(child: CircularProgressIndicator());
     }
     if (_error != null) {
         return Center(child: Text(_error!));
     }
     if (_currentRooms.isEmpty) {
         return const Center(child: Text('No rooms yet. Tap + to add one!'));
     }

     return ReorderableListView.builder(
         itemCount: _currentRooms.length,
         itemBuilder: (context, index) {
             final room = _currentRooms[index];
             return Card(
                 key: ValueKey(room.id),
                 margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                 child: ListTile(
                     leading: CircleAvatar(
                         child: Text(room.name.isNotEmpty ? room.name[0] : '?'),
                         // backgroundImage: room.coverPhotoPath.isNotEmpty && room.coverPhotoPath != 'assets/images/default_room_cover.png'
                         // ? NetworkImage(room.coverPhotoPath) // Or FileImage if local and not asset
                         // : null, // Placeholder or default image
                     ),
                     title: Text(room.name),
                     subtitle: Text('Tasks: ${room.taskIds.length}'), // Example, could be actual count
                     trailing: IconButton(
                         icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                         onPressed: () => _deleteRoom(room.id),
                     ),
                     onTap: () => _navigateToRoomDetailsScreen(room),
                 ),
             );
         },
         onReorder: _onReorder,
     );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choretography - Rooms')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateRoomScreen,
        tooltip: 'Add Room',
        child: const Icon(Icons.add),
      ),
    );
  }
}
