// test/services_mock.dart
import 'package:choretography_app/models/room_model.dart';
import 'package:choretography_app/models/task_model.dart';
import 'package:choretography_app/services/room_service.dart';
import 'package:choretography_app/services/task_service.dart';
import 'package:mocktail/mocktail.dart'; // We'll assume this can be added to pubspec by user

class MockRoomService extends Mock implements RoomService {}
class MockTaskService extends Mock implements TaskService {}
