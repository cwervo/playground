import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_model.dart'; // Adjust path as necessary

class TaskService {
  static const String _taskPrefix = 'task_';

  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  Future<void> saveTask(Task task) async {
    final prefs = await _getPrefs();
    final String taskJson = jsonEncode(task.toMap());
    await prefs.setString('$_taskPrefix${task.id}', taskJson);
  }

  Future<Task?> getTask(String taskId) async {
    final prefs = await _getPrefs();
    final String? taskJson = prefs.getString('$_taskPrefix$taskId');
    if (taskJson != null) {
      try {
        final Map<String, dynamic> taskMap = jsonDecode(taskJson) as Map<String, dynamic>;
        return Task.fromMap(taskMap);
      } catch (e) {
        print('Error decoding task $taskId: $e');
        return null;
      }
    }
    return null;
  }

  Future<List<Task>> getAllTasks() async {
    final prefs = await _getPrefs();
    final List<Task> tasks = [];
    final Set<String> keys = prefs.getKeys();

    for (String key in keys) {
      if (key.startsWith(_taskPrefix)) {
        final String? taskJson = prefs.getString(key);
        if (taskJson != null) {
          try {
            final Map<String, dynamic> taskMap = jsonDecode(taskJson) as Map<String, dynamic>;
            tasks.add(Task.fromMap(taskMap));
          } catch (e) {
            print('Error decoding task from key $key: $e');
            // Optionally, remove the malformed entry
            // await prefs.remove(key);
          }
        }
      }
    }
    return tasks;
  }

  Future<List<Task>> getTasksForRoom(String roomId) async {
    final List<Task> allTasks = await getAllTasks();
    return allTasks.where((task) => task.roomId == roomId).toList();
  }

  Future<void> deleteTask(String taskId) async {
    final prefs = await _getPrefs();
    await prefs.remove('$_taskPrefix$taskId');
    // Note: If tasks contribute to an order list like rooms, that would need updating here too.
    // For now, tasks are independent in terms of ordering persistence via TaskService.
  }

  Future<void> updateTask(Task task) async {
    // This is essentially the same as saveTask, as it will overwrite the existing entry.
    // You might add checks here if needed, e.g., if the task must exist to be updated.
    await saveTask(task);
  }
}
