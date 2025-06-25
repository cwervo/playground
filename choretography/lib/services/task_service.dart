// lib/services/task_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart'; // Adjusted import path

class TaskService {
  static const String _taskPrefix = 'task_';

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  Future<void> saveTask(Task task) async {
    final prefs = await _getPrefs();
    await prefs.setString(_taskPrefix + task.id, task.toJson());
  }

  Future<Task?> getTask(String taskId) async {
    final prefs = await _getPrefs();
    final taskString = prefs.getString(_taskPrefix + taskId);
    if (taskString != null) {
      try {
        return Task.fromJson(taskString);
      } catch (e) {
        print('Error decoding task $taskId: $e');
        return null;
      }
    }
    return null;
  }

  Future<List<Task>> getAllTasks() async {
    final prefs = await _getPrefs();
    final taskKeys = prefs.getKeys().where((key) => key.startsWith(_taskPrefix));
    List<Task> tasks = [];
    for (String key in taskKeys) {
      final taskString = prefs.getString(key);
      if (taskString != null) {
         try {
           tasks.add(Task.fromJson(taskString));
         } catch (e) {
           print('Error decoding task from key $key: $e');
         }
      }
    }
    return tasks;
  }

  Future<List<Task>> getTasksForRoom(String roomId) async {
    final allTasks = await getAllTasks();
    return allTasks.where((task) => task.roomId == roomId).toList();
  }

  Future<void> deleteTask(String taskId) async {
    final prefs = await _getPrefs();
    await prefs.remove(_taskPrefix + taskId);
    // Note: If tasks are part of a room's taskIds list, that list needs updating elsewhere.
  }

  Future<void> updateTask(Task task) async {
     await saveTask(task); // Simple alias for now
  }
}
