// lib/models/room_model.dart
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For mapEquals if used

class Room {
  final String id;
  final String name;
  final String coverPhotoPath; // Or String? if optional
  final List<String> taskIds;

  Room({
    required this.id,
    required this.name,
    this.coverPhotoPath = 'assets/images/default_room_cover.png', // Example default
    List<String>? taskIds,
  }) : taskIds = taskIds ?? [];

  Room copyWith({
    String? id,
    String? name,
    String? coverPhotoPath,
    List<String>? taskIds,
    bool setCoverPhotoPathNull = false,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPhotoPath: setCoverPhotoPathNull ? '' : (coverPhotoPath ?? this.coverPhotoPath),
      taskIds: taskIds ?? this.taskIds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coverPhotoPath': coverPhotoPath,
      'taskIds': taskIds,
    };
  }

  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      coverPhotoPath: map['coverPhotoPath'] ?? 'assets/images/default_room_cover.png',
      taskIds: List<String>.from(map['taskIds'] ?? []),
    );
  }

  String toJson() => json.encode(toMap());

  factory Room.fromJson(String source) => Room.fromMap(json.decode(source));

  @override
  String toString() {
    return 'Room(id: $id, name: $name, coverPhotoPath: $coverPhotoPath, taskIds: $taskIds)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Room &&
        other.id == id &&
        other.name == name &&
        other.coverPhotoPath == coverPhotoPath &&
        listEquals(other.taskIds, taskIds);
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        coverPhotoPath.hashCode ^
        taskIds.hashCode;
  }
}
