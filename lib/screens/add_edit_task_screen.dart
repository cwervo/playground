// lib/screens/add_edit_task_screen.dart
import 'package:flutter/material.dart';
import '../models/task_model.dart'; // Adjusted import
import '../services/task_service.dart'; // Adjusted import
import 'dart:math'; // For Random ID generation

class AddEditTaskScreen extends StatefulWidget {
  final String roomId;
  final Task? task; // Null if adding a new task

  const AddEditTaskScreen({super.key, required this.roomId, this.task});

  bool get isEditing => task != null;

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  DateTime? _dueDate;
  Map<String, dynamic>? _recurrenceRule;
  String? _selectedTaskPhotoPath; // Added for task photo

  final TaskService _taskService = TaskService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task?.name);
    _descriptionController = TextEditingController(text: widget.task?.description);
    _dueDate = widget.task?.dueDate;
    _recurrenceRule = widget.task?.recurrenceRule;
    _selectedTaskPhotoPath = widget.task?.photoPath; // Initialize task photo path
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  // Placeholder for recurrence selection
  void _selectRecurrenceRule() {
    // This would open a dialog or another screen to configure recurrence
    // For now, just cycle through a few examples or set to null
    setState(() {
      if (_recurrenceRule == null) {
        _recurrenceRule = {'type': 'daily'};
      } else if (_recurrenceRule!['type'] == 'daily') {
        _recurrenceRule = {'type': 'weekly', 'days': [1,3,5]};
      } else {
        _recurrenceRule = null;
      }
    });
     if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Recurrence set to: ${_recurrenceRule ?? "None"}')),
        );
    }
  }

  Future<void> _saveTask() async {
    if (_formKey.currentState!.validate()) {
      final String name = _nameController.text;
      final String? description = _descriptionController.text.isNotEmpty ? _descriptionController.text : null;

      try {
        if (widget.isEditing) {
          Task updatedTask = widget.task!.copyWith(
            name: name,
            description: description,
            setDueDateNull: _dueDate == null && widget.task!.dueDate != null,
            dueDate: _dueDate,
            setRecurrenceRuleNull: _recurrenceRule == null && widget.task!.recurrenceRule != null,
            recurrenceRule: _recurrenceRule,
            photoPath: _selectedTaskPhotoPath, // Set photoPath
            setPhotoPathNull: _selectedTaskPhotoPath == null && widget.task!.photoPath != null,
          );
          await _taskService.updateTask(updatedTask);
        } else {
          final String newId = DateTime.now().millisecondsSinceEpoch.toString() + Random().nextInt(9999).toString();
          Task newTask = Task(
            id: newId,
            roomId: widget.roomId,
            name: name,
            description: description,
            dueDate: _dueDate,
            recurrenceRule: _recurrenceRule,
            photoPath: _selectedTaskPhotoPath, // Set photoPath for new task
            isCompleted: false,
          );
          await _taskService.saveTask(newTask);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Task ${widget.isEditing ? "updated" : "saved"} successfully!')),
          );
          Navigator.of(context).pop(true); // Indicate success
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save task: ${e.toString()}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit Task' : 'Add Task'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Task Name', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a task name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description (Optional)', border: OutlineInputBorder()),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(_dueDate == null ? 'No due date set' : 'Due: ${_dueDate!.toLocal().toString().split(' ')[0]}'),
                  ),
                  TextButton(
                    onPressed: () => _selectDueDate(context),
                    child: const Text('Set Due Date'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
               Row(
                children: [
                  Expanded(
                    child: Text(_recurrenceRule == null ? 'No recurrence' : 'Recurrence: ${_recurrenceRule.toString()}'),
                  ),
                  TextButton(
                    onPressed: _selectRecurrenceRule,
                    child: const Text('Set Recurrence'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: const Text('Attach Photo to Task'),
                onPressed: _selectTaskPhoto, // Call the new method
              ),
              if (_selectedTaskPhotoPath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text('Selected task photo: $_selectedTaskPhotoPath'),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveTask,
        label: const Text('Save Task'),
        icon: const Icon(Icons.save),
      ),
    );
  }

  // Method to select task photo (placeholder)
  void _selectTaskPhoto() {
    setState(() {
      _selectedTaskPhotoPath = 'assets/images/task_sample_${DateTime.now().millisecond % 3 + 1}.jpg';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Simulated task photo selection: $_selectedTaskPhotoPath')),
      );
    }
  }
}
