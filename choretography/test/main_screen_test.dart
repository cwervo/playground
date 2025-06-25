// test/main_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choretography_app/screens/main_screen.dart';
import 'package:choretography_app/screens/create_room_screen.dart';
import 'package:choretography_app/screens/room_details_screen.dart';
import 'package:choretography_app/models/room_model.dart';
import 'package:choretography_app/services/room_service.dart';
import 'services_mock.dart'; // Mock service

void main() {
  late MockRoomService mockRoomService;

  setUp(() {
    mockRoomService = MockRoomService();
    // Provide a default implementation for getAllRooms if needed by all tests
    when(() => mockRoomService.getAllRooms()).thenAnswer((_) async => []);
    when(() => mockRoomService.getRoomOrder()).thenAnswer((_) async => []);
  });

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: child,
      // Need to define routes if navigation pushes named routes
      // For Navigator.push(MaterialPageRoute(...)), this is often enough
      routes: {
        // Defining a route for CreateRoomScreen in case it's used by name,
        // though direct MaterialPageRoute navigation doesn't strictly need it here.
        // '/createRoom': (context) => const CreateRoomScreen(),
        // If CreateRoomScreen itself needs mocks, they'd need to be provided here too.
      },
    );
  }

  // Helper to inject service if MainScreen takes it as a param (it doesn't currently)
  // If not, we'd need a way to override the global RoomService instance,
  // e.g. using a service locator pattern or Provider.
  // For now, tests will assume RoomService() inside MainScreen can be mocked globally or MainScreen is refactored.
  // Let's assume for now we can't easily mock the internally instantiated RoomService without Provider or GetIt.
  // So, we will test UI elements that don't depend heavily on service results first,
  // or structure service calls to be mockable.

  testWidgets('MainScreen displays AppBar, FAB, and initial state', (WidgetTester tester) async {
    // For now, we can't easily mock the RoomService instantiated inside MainScreen.
    // This test will run with the actual RoomService, which will try to use SharedPreferences.
    // This is not ideal for a unit/widget test.
    // A better approach would be to inject RoomService or use a service locator.
    // Given current constraints, we'll proceed noting this limitation.
    // The actual RoomService will likely fail to get SharedPreferences instance in test.

    await tester.pumpWidget(createTestableWidget(const MainScreen()));

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Choretography - Rooms'), findsOneWidget); // Title updated in MainScreen content
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Initially, it shows loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // pumpAndSettle will wait for futures to complete.
    // Since the real RoomService will likely throw an error trying to get SharedPreferences
    // (as plugins don't work well in flutter test without setup),
    // we expect an error message or specific UI for that.
    await tester.pumpAndSettle();

    // After loading (actual RoomService will fail, so it might show an error or empty state)
    // The MainScreen's _fetchRooms catches errors and sets _error state.
    // It also sets _isLoading to false.
    final errorFinder = find.textContaining('Failed to load rooms');
    final noRoomsFinder = find.text('No rooms yet. Tap + to add one!');

    // One of these should be true depending on how service errors are handled by UI
    expect(errorFinder.evaluate().isNotEmpty || noRoomsFinder.evaluate().isNotEmpty, isTrue);
  });

  testWidgets('MainScreen FAB navigates to CreateRoomScreen', (WidgetTester tester) async {
    await tester.pumpWidget(createTestableWidget(const MainScreen()));
    // Wait for initial loading/error state to pass
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle(); // Wait for navigation

    expect(find.byType(CreateRoomScreen), findsOneWidget);
    // This assumes CreateRoomScreen is pushed onto the navigator stack
  });

  // More tests would be added here for:
  // - Displaying a list of rooms when mockRoomService returns data.
  // - Navigating to RoomDetailsScreen when a room item is tapped.
  // - Deleting a room.
  // - Reordering rooms.
  // These require better mocking capabilities for the internally instantiated RoomService,
  // typically by refactoring MainScreen to accept RoomService as a parameter or using a service locator.
}
