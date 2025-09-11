# hello_world

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

### Google Sign-In

This project uses Google Sign-In for authentication. Before running the app,
provide your OAuth **Web client ID** from the Firebase console so that a valid
ID token can be returned. Pass it at build time using a Dart define:

```bash
flutter run --dart-define=GOOGLE_CLIENT_ID=your_client_id.apps.googleusercontent.com
```

Make sure the package name and SHA-1 fingerprint of your signing certificate
are registered in the Firebase project and that the downloaded
`google-services.json` contains the corresponding OAuth client entries.
