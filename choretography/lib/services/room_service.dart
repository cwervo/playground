// lib/services/room_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/room_model.dart'; // Adjusted import path

class RoomService {
  static const String _roomPrefix = 'room_';
  static const String _roomOrderKey = 'room_order_key';

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  Future<void> saveRoom(Room room) async {
    final prefs = await _getPrefs();
    await prefs.setString(_roomPrefix + room.id, room.toJson());
  }

  Future<Room?> getRoom(String roomId) async {
    final prefs = await _getPrefs();
    final roomString = prefs.getString(_roomPrefix + roomId);
    if (roomString != null) {
      try {
        return Room.fromJson(roomString);
      } catch (e) {
        print('Error decoding room $roomId: $e');
        return null;
      }
    }
    return null;
  }

  Future<List<Room>> getAllRooms() async {
    final prefs = await _getPrefs();
    final roomKeys = prefs.getKeys().where((key) => key.startsWith(_roomPrefix));
    List<Room> rooms = [];
    for (String key in roomKeys) {
      final roomString = prefs.getString(key);
      if (roomString != null) {
        try {
          rooms.add(Room.fromJson(roomString));
        } catch (e) {
          print('Error decoding room from key $key: $e');
        }
      }
    }

    final roomOrder = await getRoomOrder();
    if (roomOrder != null && roomOrder.isNotEmpty) {
      Map<String, Room> roomMap = {for (var room in rooms) room.id: room};
      List<Room> sortedRooms = [];
      for (String id in roomOrder) {
        if (roomMap.containsKey(id)) {
          sortedRooms.add(roomMap[id]!);
          roomMap.remove(id); // Remove to avoid duplicates and keep track of unordered rooms
        }
      }
      sortedRooms.addAll(roomMap.values); // Add any rooms not in the order list
      return sortedRooms;
    }
    return rooms; // Return unsorted if no order or error
  }

  Future<void> deleteRoom(String roomId) async {
    final prefs = await _getPrefs();
    await prefs.remove(_roomPrefix + roomId);

    List<String>? currentOrder = await getRoomOrder();
    if (currentOrder != null) {
      currentOrder.remove(roomId);
      await saveRoomOrder(currentOrder);
    }
  }

  Future<void> saveRoomOrder(List<String> roomIds) async {
    final prefs = await _getPrefs();
    await prefs.setStringList(_roomOrderKey, roomIds);
  }

  Future<List<String>?> getRoomOrder() async {
    final prefs = await _getPrefs();
    return prefs.getStringList(_roomOrderKey);
  }

  Future<void> updateRoom(Room room) async {
     await saveRoom(room); // Simple alias for now
  }
}
