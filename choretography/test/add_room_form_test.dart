// test/add_room_form_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choretography_app/widgets/add_room_form.dart';
import 'package:choretography_app/services/room_service.dart';
import 'services_mock.dart';

// To test AddRoomForm, we'd ideally inject RoomService or use a Provider.
// Since AddRoomForm instantiates its own RoomService, true unit testing is hard.
// We can test the form validation and UI, but the save action will use the real service.

void main() {
  // MockRoomService mockRoomService; // Declare if you can inject

  // setUp(() {
  //   mockRoomService = MockRoomService();
  // });

  Widget createTestableWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child), // AddRoomForm needs a Scaffold ancestor for SnackBar
    );
  }

  testWidgets('AddRoomForm displays form fields and button', (WidgetTester tester) async {
    await tester.pumpWidget(createTestableWidget(const AddRoomForm()));

    expect(find.widgetWithText(TextFormField, 'Room Name'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Select Cover Photo'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Create Room'), findsOneWidget);
  });

  testWidgets('AddRoomForm shows validation error for empty room name', (WidgetTester tester) async {
    await tester.pumpWidget(createTestableWidget(const AddRoomForm()));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Room'));
    await tester.pump(); // Allow time for validation and UI update

    expect(find.text('Please enter a room name'), findsOneWidget);
  });

  // Test for successful submission would require mocking RoomService.saveRoom
  // and verifying Navigator.pop(true) or SnackBar.
  // This is difficult without service injection.
  // Example of how it *could* look if service was injectable:
  /*
  testWidgets('AddRoomForm submits data and pops on success', (WidgetTester tester) async {
    // Assume AddRoomForm takes a RoomService in its constructor for this test
    // final mockRoomService = MockRoomService();
    // when(() => mockRoomService.saveRoom(any())).thenAnswer((_) async => Future.value());

    // await tester.pumpWidget(createTestableWidget(AddRoomForm(roomService: mockRoomService)));

    await tester.enterText(find.widgetWithText(TextFormField, 'Room Name'), 'Test Room');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Room'));
    await tester.pumpAndSettle();

    // verify(() => mockRoomService.saveRoom(any(that: isA<Room>()))).called(1);
    // Expect that Navigator.pop(true) was called - this is harder to test directly
    // or expect a SnackBar message indicating success.
    expect(find.byType(AddRoomForm), findsNothing); // If it pops
  });
  */
}
