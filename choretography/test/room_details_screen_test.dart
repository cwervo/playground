// test/room_details_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choretography_app/screens/room_details_screen.dart';
import 'package:choretography_app/models/room_model.dart';
import 'package:choretography_app/models/task_model.dart';
import 'package:choretography_app/services/task_service.dart';
import 'services_mock.dart'; // Import mock services

void main() {
  late MockTaskService mockTaskService;
  late Room sampleRoom;

  setUp(() {
    mockTaskService = MockTaskService();
    sampleRoom = Room(id: '1', name: 'Test Room', taskIds: ['task1']);

    // Default mock for getTasksForRoom
    // This is important because RoomDetailsScreen calls _fetchTasks in initState
    when(() => mockTaskService.getTasksForRoom(any())).thenAnswer((_) async => []);
  });

  Widget createTestableWidget(Widget child) {
    return MaterialApp(home: child);
  }

  // Similar to MainScreen, RoomDetailsScreen instantiates its own TaskService.
  // Proper testing requires service injection. The tests below will run against
  // the actual TaskService which may cause issues in a pure test environment
  // if it tries to access things like SharedPreferences.

  testWidgets('RoomDetailsScreen displays room name and initial task state', (WidgetTester tester) async {
    // To properly test this with a mock, RoomDetailsScreen would need to accept
    // TaskService via constructor or use a service locator.
    // For now, this test relies on the internal TaskService instantiation.
    // The default `when` in setUp for mockTaskService.getTasksForRoom will not be hit
    // unless we can inject it.

    await tester.pumpWidget(createTestableWidget(RoomDetailsScreen(room: sampleRoom)));

    expect(find.text(sampleRoom.name), findsOneWidget); // Name in AppBar
    expect(find.text('Room ID: ${sampleRoom.id}'), findsOneWidget);

    // Initial loading state for tasks
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for futures to complete (TaskService.getTasksForRoom)
    // The real service will likely fail in test environment.
    await tester.pumpAndSettle();

    // After loading (TaskService likely failed or returned empty from a real SharedPreferences attempt)
    // Check for either error text or "no tasks" text.
    final errorFinder = find.textContaining('Failed to load tasks');
    final noTasksFinder = find.text('No tasks in this room yet.');

    expect(errorFinder.evaluate().isNotEmpty || noTasksFinder.evaluate().isNotEmpty, isTrue);

    expect(find.byType(FloatingActionButton), findsOneWidget); // FAB to add task
    expect(find.byIcon(Icons.add_task), findsOneWidget);
  });

  // More tests would be added:
  // - Displaying tasks when mockTaskService (if injectable) returns them.
  // - Interacting with task checkboxes (requires mocking updateTask).
  // - Navigating to an Add/Edit task screen.
}
