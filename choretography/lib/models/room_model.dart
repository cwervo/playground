class Room {
  final String id;
  final String name;
  final String coverPhotoPath;
  final List<String> taskIds;

  Room({
    required this.id,
    required this.name,
    required this.coverPhotoPath,
    List<String>? taskIds,
  }) : this.taskIds = taskIds ?? []; // Default to an empty list if null

  // It's good practice to include methods for JSON serialization/deserialization
  // and a copyWith method, though not explicitly requested, they are common for models.

  // Factory constructor for creating a new Room instance from a map
  factory Room.fromMap(Map<String, dynamic> map) {
    return Room(
      id: map['id'] as String,
      name: map['name'] as String,
      coverPhotoPath: map['coverPhotoPath'] as String,
      taskIds: List<String>.from(map['taskIds'] ?? []),
    );
  }

  // Method for converting a Room instance to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'coverPhotoPath': coverPhotoPath,
      'taskIds': taskIds,
    };
  }

  // Method for creating a copy of the Room instance with updated fields
  Room copyWith({
    String? id,
    String? name,
    String? coverPhotoPath,
    List<String>? taskIds,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      coverPhotoPath: coverPhotoPath ?? this.coverPhotoPath,
      taskIds: taskIds ?? this.taskIds,
    );
  }

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
      other.taskIds.toString() == taskIds.toString(); // Simple list comparison for this example
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      coverPhotoPath.hashCode ^
      taskIds.hashCode;
  }
}
