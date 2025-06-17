// lib/screens/room_details_screen.dart
import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';
import './add_edit_task_screen.dart'; // Import the new screen

class RoomDetailsScreen extends StatefulWidget {
  final Room room;
  const RoomDetailsScreen({super.key, required this.room});

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final TaskService _taskService = TaskService();
  List<Task> _tasks = [];
  bool _isLoadingTasks = true;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoadingTasks = true;
    });
    try {
      final tasks = await _taskService.getTasksForRoom(widget.room.id);
      setState(() {
        _tasks = tasks;
        _isLoadingTasks = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingTasks = false;
        // Handle error, e.g., show a SnackBar
        if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Failed to load tasks: ${e.toString()}'))
         );
        }
      });
    }
  }

  // Method to delete a task
  Future<void> _deleteTask(String taskId, String taskName) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete the task "$taskName"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await _taskService.deleteTask(taskId);
        // Note: If Room model's taskIds list needs explicit management,
        // that would be an additional step here or in RoomService.
        // For now, assuming task deletion is independent or handled implicitly.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Task "$taskName" deleted successfully!')),
          );
          _fetchTasks(); // Refresh the list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete task: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.room.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Room ID: ${widget.room.id}', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text('Cover Photo Path: ${widget.room.coverPhotoPath}', style: Theme.of(context).textTheme.titleSmall),
            if (widget.room.coverPhotoPath.isNotEmpty && widget.room.coverPhotoPath != 'assets/images/default_room_cover.png')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Container( // Placeholder display for the image
                  height: 150,
                  width: double.infinity,
                  color: Colors.grey[300],
                  alignment: Alignment.center,
                  child: Text('Cover: ${widget.room.coverPhotoPath}'),
                )
                // child: Text('[Placeholder for Room Cover: ${widget.room.coverPhotoPath}]', style: TextStyle(color: Colors.grey)),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: const Text('[No custom room cover photo]', style: TextStyle(color: Colors.grey)),
              ),
            const SizedBox(height: 20),
            Text('Tasks:', style: Theme.of(context).textTheme.titleLarge),
            Expanded(
              child: _isLoadingTasks
                  ? const Center(child: CircularProgressIndicator())
                  : _tasks.isEmpty
                      ? const Center(child: Text('No tasks in this room yet.'))
                      : ListView.builder(
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final task = _tasks[index];
                            return Card(
                              child: ListTile(
                                title: Text(task.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(task.description ?? 'No description'),
                                    if (task.photoPath != null && task.photoPath!.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4.0),
                                        child: Text('[Task Photo: ${task.photoPath}]', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Checkbox(
                                      value: task.isCompleted,
                                      onChanged: (bool? value) async {
                                        if (value == null) return;
                                        final originalCompletedStatus = task.isCompleted;
                                        final taskIndex = index;

                                        setState(() {
                                          _tasks[taskIndex] = task.copyWith(isCompleted: value);
                                        });

                                        try {
                                          await _taskService.updateTask(_tasks[taskIndex]);
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Task "${_tasks[taskIndex].name}" updated.')),
                                            );
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            setState(() {
                                              _tasks[taskIndex] = task.copyWith(isCompleted: originalCompletedStatus);
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Failed to update task: ${e.toString()}')),
                                            );
                                          }
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      tooltip: 'Delete Task',
                                      onPressed: () => _deleteTask(task.id, task.name),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddEditTaskScreen(
                                        roomId: widget.room.id,
                                        task: task, // Pass existing task for editing
                                      ),
                                    ),
                                  );
                                  if (result == true && mounted) {
                                    _fetchTasks(); // Refresh task list if a task was modified
                                  }
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async { // Make onPressed async
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddEditTaskScreen(roomId: widget.room.id), // Pass only roomId for new task
            ),
          );
          if (result == true && mounted) {
            _fetchTasks(); // Refresh task list if a task was added
          }
        },
        tooltip: 'Add Task',
        child: const Icon(Icons.add_task),
      ),
    );
  }
}
