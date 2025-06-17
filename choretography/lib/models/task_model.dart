import 'package:flutter/foundation.dart'; // For listEquals in operator ==

class Task {
  final String id;
  final String roomId;
  final String name;
  final String? description;
  final String? photoPath;
  final bool isCompleted;
  final DateTime? dueDate;
  final Map<String, dynamic>? recurrenceRule;

  Task({
    required this.id,
    required this.roomId,
    required this.name,
    this.description,
    this.photoPath,
    this.isCompleted = false,
    this.dueDate,
    this.recurrenceRule,
  });

  Task copyWith({
    String? id,
    String? roomId,
    String? name,
    String? description,
    String? photoPath,
    bool? isCompleted,
    DateTime? dueDate,
    Map<String, dynamic>? recurrenceRule,
    bool setDueDateNull = false, // Flag to explicitly set dueDate to null
    bool setDescriptionNull = false,
    bool setPhotoPathNull = false,
    bool setRecurrenceRuleNull = false,
  }) {
    return Task(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      description: setDescriptionNull ? null : description ?? this.description,
      photoPath: setPhotoPathNull ? null : photoPath ?? this.photoPath,
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: setDueDateNull ? null : dueDate ?? this.dueDate,
      recurrenceRule: setRecurrenceRuleNull ? null : recurrenceRule ?? this.recurrenceRule,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'roomId': roomId,
      'name': name,
      'description': description,
      'photoPath': photoPath,
      'isCompleted': isCompleted,
      'dueDate': dueDate?.toIso8601String(), // Store DateTime as ISO8601 string
      'recurrenceRule': recurrenceRule,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] as String,
      roomId: map['roomId'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      photoPath: map['photoPath'] as String?,
      isCompleted: map['isCompleted'] as bool? ?? false,
      dueDate: map['dueDate'] == null ? null : DateTime.tryParse(map['dueDate'] as String),
      recurrenceRule: map['recurrenceRule'] == null
          ? null
          : Map<String, dynamic>.from(map['recurrenceRule'] as Map),
    );
  }

  @override
  String toString() {
    return 'Task(id: $id, roomId: $roomId, name: $name, description: $description, photoPath: $photoPath, isCompleted: $isCompleted, dueDate: $dueDate, recurrenceRule: $recurrenceRule)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Task &&
      other.id == id &&
      other.roomId == roomId &&
      other.name == name &&
      other.description == description &&
      other.photoPath == photoPath &&
      other.isCompleted == isCompleted &&
      other.dueDate == dueDate &&
      mapEquals(other.recurrenceRule, recurrenceRule); // Use mapEquals for map comparison
  }

  @override
  int get hashCode {
    return id.hashCode ^
      roomId.hashCode ^
      name.hashCode ^
      description.hashCode ^
      photoPath.hashCode ^
      isCompleted.hashCode ^
      dueDate.hashCode ^
      recurrenceRule.hashCode; // Simple hash for map, consider more robust if needed
  }
}

// Helper for comparing maps, you might need to import foundation.dart from Flutter for listEquals
// For maps, a similar helper or package might be used for deep equality.
// For simplicity, we'll use a basic equality check for recurrenceRule or rely on mapEquals from flutter/foundation.dart
bool mapEquals<T, U>(Map<T, U>? a, Map<T, U>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || a[key] != b[key]) {
      return false;
    }
  }
  return true;
}
