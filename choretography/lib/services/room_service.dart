import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_model.dart'; // Adjust path as necessary

class RoomService {
  static const String _roomPrefix = 'room_';
  static const String _roomOrderKey = 'room_order_key'; // Added key for room order

  // Helper method to get SharedPreferences instance
  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  // Save a Room object
  Future<void> saveRoom(Room room) async {
    final prefs = await _getPrefs();
    final String roomJson = jsonEncode(room.toMap());
    await prefs.setString('$_roomPrefix${room.id}', roomJson);
  }

  // Get a single Room object by its ID
  Future<Room?> getRoom(String roomId) async {
    final prefs = await _getPrefs();
    final String? roomJson = prefs.getString('$_roomPrefix$roomId');
    if (roomJson != null) {
      try {
        final Map<String, dynamic> roomMap = jsonDecode(roomJson) as Map<String, dynamic>;
        return Room.fromMap(roomMap);
      } catch (e) {
        print('Error decoding room $roomId: $e');
        return null;
      }
    }
    return null;
  }

  // Get all Room objects
  Future<List<Room>> getAllRooms() async {
    final prefs = await _getPrefs();
    final Map<String, Room> roomsMap = {};
    final Set<String> keys = prefs.getKeys();

    for (String key in keys) {
      if (key.startsWith(_roomPrefix)) {
        final String? roomJson = prefs.getString(key);
        if (roomJson != null) {
          try {
            final Map<String, dynamic> roomMap = jsonDecode(roomJson) as Map<String, dynamic>;
            final room = Room.fromMap(roomMap);
            roomsMap[room.id] = room;
          } catch (e) {
            print('Error decoding room from key $key: $e');
          }
        }
      }
    }

    final List<String>? roomOrder = await getRoomOrder();
    if (roomOrder != null && roomOrder.isNotEmpty) {
      final List<Room> sortedRooms = [];
      for (String roomId in roomOrder) {
        if (roomsMap.containsKey(roomId)) {
          sortedRooms.add(roomsMap[roomId]!);
          roomsMap.remove(roomId); // Remove to keep track of rooms not in order list
        }
      }
      // Add any remaining rooms that were not in the order list (e.g., newly added)
      // These will be added at the end, maintaining their fetched order relative to each other.
      sortedRooms.addAll(roomsMap.values);
      return sortedRooms;
    } else {
      // If no order is saved, return rooms from map (order might not be guaranteed by getKeys)
      // Optionally, sort by name or ID as a default fallback.
      // For now, returning as is from the map's values.
      return roomsMap.values.toList();
    }
  }

  // Delete a Room object by its ID
  Future<void> deleteRoom(String roomId) async {
    final prefs = await _getPrefs();
    await prefs.remove('$_roomPrefix$roomId');
    // Also update the room order after deleting a room
    List<String>? currentOrder = await getRoomOrder();
    if (currentOrder != null) {
      currentOrder.remove(roomId);
      await saveRoomOrder(currentOrder);
    }
  }

  // Methods for saving and retrieving room order
  Future<void> saveRoomOrder(List<String> roomIds) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_roomOrderKey, roomIds);
  }

  Future<List<String>?> getRoomOrder() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_roomOrderKey);
  }

  // Optional: A method to update a room.
  // This would typically involve fetching, modifying, and re-saving,
  // or just re-saving if the Room object passed in has the complete updated data.
  Future<void> updateRoom(Room room) async {
    // This is essentially the same as saveRoom, as it will overwrite the existing entry.
    // You might add checks here if needed, e.g., if the room must exist to be updated.
    await saveRoom(room);
  }
}
