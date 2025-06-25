# Choretography App - Manual Setup Guide

This guide provides instructions on how to manually set up the Choretography Flutter application using the codebase provided in this repository. Due to limitations in the automated development environment, the standard Flutter project initialization could not be performed directly.

## Prerequisites

1.  **Install Flutter:** If you don't have Flutter installed, follow the official Flutter installation guide for your operating system: [https://flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install)
    *   Ensure you can run `flutter doctor` without critical errors.
2.  **Git:** Ensure Git is installed on your system to clone/manage this repository.

## Setup Steps

1.  **Clone This Repository (Optional):**
    If you haven't already, clone this repository to your local machine or download the source code.
    ```bash
    # Example:
    # git clone <repository_url>
    # cd <repository_directory>
    ```

2.  **Create a New Flutter Project:**
    Open your terminal or command prompt and navigate to the directory where you want to create your Flutter project (this should be *outside* the cloned repository if you cloned it, or you can create it and then copy files in).
    Run the following command to create a new Flutter project. You can name it `choretography_app` or choose another name.
    ```bash
    flutter create choretography_app
    ```
    This will create a new Flutter project with the standard directory structure.

3.  **Navigate into Your New Project:**
    ```bash
    cd choretography_app
    ```

4.  **Replace `lib/` and `test/` Directories:**
    *   **Delete** the existing `lib/` directory inside your newly created `choretography_app` project.
        ```bash
        # On Linux/macOS
        rm -rf lib

        # On Windows (Command Prompt)
        rd /s /q lib
        ```
    *   **Delete** the existing `test/` directory inside `choretography_app` (if you plan to use the tests from this repository).
        ```bash
        # On Linux/macOS
        rm -rf test

        # On Windows (Command Prompt)
        rd /s /q test
        ```
    *   **Copy** the `lib/` directory from *this repository* (which contains all the application source code) into your `choretography_app` project directory.
    *   **Copy** the `test/` directory from *this repository* (once it's created in a later step, it will contain widget tests) into your `choretography_app` project directory.

5.  **Update `pubspec.yaml`:**
    Open the `pubspec.yaml` file in your `choretography_app` project.
    Add the following dependencies under the `dependencies:` section:
    ```yaml
    dependencies:
      flutter:
        sdk: flutter

      shared_preferences: ^2.2.2 # Or the latest compatible version
      # provider: ^6.0.0  # Uncomment if you decide to use Provider for state management
      # image_picker: ^1.0.0 # Uncomment if you add image picking functionality

      # The following are usually included by default but ensure they are present
      cupertino_icons: ^1.0.2
    ```
    Ensure your `environment:` sdk version is compatible (e.g., `sdk: '>=3.0.0 <4.0.0'`). The version created by `flutter create` should be fine.

    You should also add `dev_dependencies` for testing, including `mocktail` for mocking services:
    ```yaml
    dev_dependencies:
      flutter_test:
        sdk: flutter
      mocktail: ^1.0.0 # Or the latest compatible version for mocking services
      # flutter_lints: ^2.0.0 # Or latest, usually included by default
    ```

6.  **Add Assets (Placeholder):**
    If the application uses local image assets (e.g., default cover photos), you'll need to create an `assets/` folder in your `choretography_app` project root and place the images there. For example:
    ```
    choretography_app/
      assets/
        images/
          default_room_cover.png
          sample_cover_1.jpg
          # etc.
    ```
    Then, declare the assets folder in your `pubspec.yaml`:
    ```yaml
    flutter:
      uses-material-design: true
      assets:
        - assets/images/ # Make sure this path is correct
    ```

7.  **Get Dependencies:**
    In your terminal, inside the `choretography_app` project directory, run:
    ```bash
    flutter pub get
    ```

8.  **Run the Application:**
    You should now be able to run the application:
    ```bash
    flutter run
    ```
    This will typically run the app on a connected device, emulator, or in a web browser if configured.

9.  **Run Widget Tests:**
    Once the `test/` directory is populated with test files, you can run them:
    ```bash
    flutter test
    ```

## Troubleshooting

*   **Import Errors:** If you see import errors after copying the files, double-check that:
    *   All necessary files from this repository's `lib/` directory were copied correctly.
    *   The `pubspec.yaml` file has the correct dependencies, and you've run `flutter pub get`.
    *   The project name used in import statements within the Dart files (e.g., `import 'package:choretography_app/screens/main_screen.dart';` in `lib/main.dart`) matches the `name:` field in your `pubspec.yaml`. If you named your project differently than `choretography_app`, you might need to update these import statements. (The provided `main.dart` uses relative imports like `import 'screens/main_screen.dart';` where possible, which is more robust to project name changes).
*   **Asset Not Found:** If images are not displaying, ensure the `assets/` folder and its contents are correctly placed and declared in `pubspec.yaml`.

---

This setup process allows you to run and test the application code developed so far.

## Image Picking (Optional Feature)

The application includes UI placeholders for attaching photos to rooms and tasks. To enable actual image picking functionality from the device gallery or camera, you will need to add an image picker plugin. A common choice is `image_picker`.

1.  Add `image_picker` to your `pubspec.yaml` dependencies:
    ```yaml
    dependencies:
      # ... other dependencies
      image_picker: ^1.0.7 # Or latest version
    ```
2.  Run `flutter pub get`.
3.  Follow the setup instructions for `image_picker` for each platform (iOS, Android, Web) you intend to support. This often involves adding permissions or specific entries to native configuration files (e.g., `Info.plist` on iOS, `AndroidManifest.xml` on Android). Refer to the `image_picker` package documentation on [pub.dev](https://pub.dev/packages/image_picker).
4.  You will then need to implement the image picking logic in the relevant `_selectCoverPhoto()` (in `add_room_form.dart`) and `_selectTaskPhoto()` (in `add_edit_task_screen.dart`) methods, using the `ImagePicker` class to get an image file and then determining how to store/manage its path.

## CI/CD with GitHub Actions (Placeholder)

A placeholder GitHub Actions workflow file is provided in this repository at `.github/workflows/flutter_build.yml` (relative to the `choretography` directory if you copied it inside).

This workflow (`choretography/.github/workflows/flutter_build.yml`) is designed to:
- Trigger on pushes and pull requests to the main branch that affect files within the `choretography/` directory.
- Set the working directory to `./choretography` for all Flutter commands.
- Check out the code.
- Set up a specific Flutter version.
- Get dependencies (`flutter pub get`).
- Analyze the project (`flutter analyze`).
- Run widget tests (`flutter test`).
- Build the Flutter web application (`flutter build web`).
- Includes a commented-out conceptual placeholder for deploying to GitHub Pages.

**To use this workflow:**
1.  Ensure your Flutter project (created by following the steps above) is a Git repository and pushed to GitHub.
2.  Make sure the `.github/workflows/flutter_build.yml` file (from the `choretography` directory of this repository) is placed in the `.github/workflows/` directory *at the root of your own Git repository*.
3.  You may need to adjust the Flutter version, branch names, paths, and deployment steps to fit your specific needs.
4.  The `working-directory: ./choretography` in the workflow assumes that your Flutter project files (pubspec.yaml, lib, etc.) are in a subdirectory named `choretography` within your repository root. If your Flutter project is at the root of your repository, you would remove the `working-directory` lines or set it to `./`.
5.  For deployment to GitHub Pages, you'll need to configure the `peaceiris/actions-gh-pages` action (or a similar one) correctly, especially the `publish_dir` and `destination_dir` if you want it to live under `/choretography` on your GitHub Pages site. You might also need to set the base URL in your Flutter web build (`--base-href` flag).
