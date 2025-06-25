**IMPORTANT SETUP NOTE:** This project requires manual setup due to the development environment's limitations. Please refer to the [**SETUP.md**](./SETUP.md) file for detailed instructions on how to create a local Flutter project and integrate this codebase.
---

# Choretography App README

This README provides an overview of the Choretography application, its features, and how to get it running locally using the manual setup process.

## Installation

<details>
<summary>Toggle to view installation instructions</summary>

1.  **Install Flutter:** Ensure you have the Flutter SDK installed on your system. Follow the official guide: [https://flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install).
2.  **Manual Project Setup:** Follow the instructions in [**SETUP.md**](./SETUP.md) to:
    *   Create a new Flutter project (e.g., `flutter create choretography_app`).
    *   Copy the `lib/`, `test/`, and other relevant files from this repository into your new local project.
    *   Update your local project's `pubspec.yaml` as per `SETUP.md`.
    *   Run `flutter pub get` in your local project.

</details>

## Compilation

<details>
<summary>Toggle to view compilation instructions</summary>

Once you have manually set up the project as described in `SETUP.md` and are inside your local project directory (e.g., `choretography_app`), you can compile the application using standard Flutter commands:

**For Development/Debug Builds:**
```bash
# Build an Android APK (debug)
flutter build apk --debug

# Build for iOS (debug, requires macOS and Xcode)
flutter build ios --debug

# Build for Web
flutter build web
# Consider --no-sound-null-safety if you encounter related issues during initial runs:
# flutter build web --no-sound-null-safety
```

**For Release Builds:**
```bash
# Build an Android App Bundle (release)
flutter build appbundle --release

# Build an Android APK (release)
flutter build apk --release

# Build for iOS (release, requires macOS and Xcode)
flutter build ios --release

# Build for Web (release)
flutter build web --release
```
For more details on Flutter build commands, refer to the [official Flutter documentation on deployment](https://flutter.dev/docs/deployment).
</details>

## Serving Locally (Development)

<details>
<summary>Toggle to view instructions for serving locally</summary>

After completing the manual setup from `SETUP.md`, you can run the application locally for development:

1.  **Ensure a device is running** (emulator or physical device) or select a web browser.
    *   To list available devices: `flutter devices`
2.  **Run the app:**
    ```bash
    # Run on the default selected device/emulator or web browser
    flutter run

    # Run specifically on Chrome (for web)
    flutter run -d chrome
    ```
    The application should launch, and you can take advantage of Flutter's hot reload capabilities.
</details>

## Implemented Features (Conceptual Code Structure)

The following features have been implemented in the codebase provided in this repository. Note that full end-to-end testing and some integrations (like actual image picking) require the manual setup.

-   **Core Models:**
    -   [x] Room Model (`room_model.dart`)
    -   [x] Task Model (`task_model.dart`)
-   **Services (using `shared_preferences` for local persistence):**
    -   [x] Room Service (`room_service.dart`): CRUD operations for rooms, room order persistence.
    -   [x] Task Service (`task_service.dart`): CRUD operations for tasks.
-   **Screens:**
    -   [x] Main Screen (`main_screen.dart`): Displays a list of rooms, allows reordering, navigation to create/details.
    -   [x] Create Room Screen (`create_room_screen.dart`): Form to add new rooms.
    -   [x] Room Details Screen (`room_details_screen.dart`): Displays room details and associated tasks; allows task completion, deletion, and navigation to add/edit tasks.
    -   [x] Add/Edit Task Screen (`add_edit_task_screen.dart`): Form to add or edit tasks, including due date and placeholder recurrence/photo.
-   **Widgets:**
    -   [x] Add Room Form (`add_room_form.dart`): Reusable form widget for room creation.
-   **Utilities:**
    -   [x] Recurrence Utils (`recurrence_utils.dart`): Basic logic for task recurrence checking (placeholder for full implementation).
-   **Basic Widget Tests:**
    -   [x] Initial tests for `MainScreen`, `AddRoomForm`, `RoomDetailsScreen`.
    -   [x] Mock services (`services_mock.dart`) for testing.
-   **Documentation:**
    -   [x] This `README.md`.
    -   [x] `SETUP.md` for manual project creation and setup.

## Roadmap & Pending Items

-   [ ] **Full Image Picker Integration:**
    -   [ ] Implement actual image picking for Room cover photos using `image_picker`.
    -   [ ] Implement actual image picking for Task photos.
    -   [ ] Decide on and implement image storage strategy (local file paths, cloud storage, etc.).
-   [ ] **Advanced Recurrence Rule UI:**
    -   [ ] Develop a user interface for selecting and customizing task recurrence rules in `AddEditTaskScreen`.
    -   [ ] Enhance `RecurrenceUtils` for more complex recurrence logic and upcoming date generation.
-   [ ] **State Management Refinement:**
    -   [ ] Evaluate and potentially integrate a formal state management solution (e.g., Provider, Riverpod, BLoC) if app complexity grows, especially to manage service instances and refresh UI across screens more effectively. This will also simplify widget testing.
-   [ ] **Task Management in Room Model:**
    -   [ ] Decide if `Room.taskIds` should be actively managed by `RoomService` when tasks are deleted, or if `TaskService.getTasksForRoom` is always the source of truth.
-   [ ] **Comprehensive Widget and Integration Testing:**
    -   [ ] Expand widget tests for more interactions and edge cases.
    -   [ ] Implement integration tests for user flows.
-   [ ] **UI/UX Polish:**
    -   [ ] Improve visual design, layout, and user experience across all screens.
    -   [ ] Implement actual image display instead of placeholders.
-   [ ] **Error Handling & Validation:**
    -   [ ] Enhance input validation and user feedback for errors.
-   [ ] **Data Backup/Sync (Optional):**
    -   [ ] Explore options for backing up `shared_preferences` data or syncing with a cloud backend.
-   [ ] **Live Debugging & Testing:**
    -   [ ] Perform thorough testing and debugging in emulators/real devices once the manual setup is complete.

---
*This README provides guidance for using the codebase within a manually created Flutter project.*