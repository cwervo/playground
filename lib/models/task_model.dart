// lib/models/task_model.dart
import 'dart:convert';
import 'package:flutter/foundation.dart'; // For mapEquals

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
    bool setDescriptionNull = false,
    bool setPhotoPathNull = false,
    bool setDueDateNull = false,
    bool setRecurrenceRuleNull = false,
  }) {
    return Task(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      description: setDescriptionNull ? null : (description ?? this.description),
      photoPath: setPhotoPathNull ? null : (photoPath ?? this.photoPath),
      isCompleted: isCompleted ?? this.isCompleted,
      dueDate: setDueDateNull ? null : (dueDate ?? this.dueDate),
      recurrenceRule: setRecurrenceRuleNull ? null : (recurrenceRule ?? this.recurrenceRule),
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
      'dueDate': dueDate?.toIso8601String(),
      'recurrenceRule': recurrenceRule,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map) {
    return Task(
      id: map['id'] ?? '',
      roomId: map['roomId'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      photoPath: map['photoPath'],
      isCompleted: map['isCompleted'] ?? false,
      dueDate: map['dueDate'] != null ? DateTime.tryParse(map['dueDate']) : null,
      recurrenceRule: map['recurrenceRule'] != null ? Map<String, dynamic>.from(map['recurrenceRule']) : null,
    );
  }

  String toJson() => json.encode(toMap());
  factory Task.fromJson(String source) => Task.fromMap(json.decode(source));

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
        mapEquals(other.recurrenceRule, recurrenceRule);
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
        recurrenceRule.hashCode;
  }
}
