<!--
This README describes the package. If you publish this package to pub.dev,
this README's contents appear on the landing page for your package.

For information about how to write a good package README, see the guide for
[writing package pages](https://dart.dev/tools/pub/writing-package-pages).

For general information about developing packages, see the Dart guide for
[creating packages](https://dart.dev/guides/libraries/create-packages)
and the Flutter guide for
[developing packages and plugins](https://flutter.dev/to/develop-packages).
-->

TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Platform setup

This package bundles several plugins that require platform-specific
configuration in the consuming app. Follow the instructions below for each
platform you target.

### Android

Open `android/app/src/main/AndroidManifest.xml` and add the permissions used by
the chat module:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Microphone (voice recording) -->
    <uses-permission android:name="android.permission.RECORD_AUDIO" />

    <!-- Location (sending the user's current location) -->
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

    <!-- Camera (taking photos) -->
    <uses-permission android:name="android.permission.CAMERA" />

    <!-- Storage (picking/saving files) -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
</manifest>
```

Notes:

- `ACCESS_FINE_LOCATION` is required for high-accuracy location. If you only
  need approximate location, `ACCESS_COARSE_LOCATION` alone is sufficient.
- If your app targets Android 12+ (API 31+), the `permission_handler` plugin
  requires you to declare the exact permissions you use via
  `android.permission.ACCESS_FINE_LOCATION` etc. in the manifest as shown above.
- If you use the `record` plugin for voice messages, you may also need to add
  the following to your `android/app/build.gradle` (or `build.gradle.kts`):

  ```groovy
  android {
      compileSdkVersion 34
  }
  ```

### iOS

Open `ios/Runner/Info.plist` and add the following usage descriptions. These
strings are shown to the user when the app requests the corresponding
permission, so provide a clear explanation of why the permission is needed.

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone to record voice messages.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app uses your location to share your current location in chat.</string>
<key>NSCameraUsageDescription</key>
<string>This app uses the camera to take photos to share in chat.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>This app accesses your photo library to share images and videos in chat.</string>
```

Notes:

- `NSLocationWhenInUseUsageDescription` is required by the `geolocator` plugin
  to request location access while the app is in use.
- If you need background location updates, add
  `NSLocationAlwaysAndWhenInUseUsageDescription` as well.
- The `record` plugin also requires `NSMicrophoneUsageDescription` (already
  listed above).

### Location map previews

Location attachments render a static, non-movable map preview. The thumbnail
image is fetched from the chat server's location endpoint:

```
GET {baseUrl}/chat/location/get-thumbnail?lat={lat}&lon={lon}
```

The endpoint must return a PNG image for the given coordinates. The `baseUrl`
used is the same one configured on the `ChatConfig`. If the request fails or
the URL is empty, location attachments fall back to a placeholder instead of a
map image. Tapping a location attachment opens the coordinates in the full
Google Maps app.

## Usage

TODO: Include short and useful examples for package users. Add longer examples
to `/example` folder.

```dart
const like = 'sample';
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to
contribute to the package, how to file issues, what response they can expect
from the package authors, and more.
