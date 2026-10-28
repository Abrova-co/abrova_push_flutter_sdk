# AbrovaPush Flutter Example

A comprehensive example app demonstrating all features of the AbrovaPush Flutter SDK, part of the AbrovaCore ecosystem.

## Features Demonstrated

This example showcases all SDK capabilities:

### 1. Push Notifications
- Device registration with user ID and metadata
- Topic subscription/unsubscription
- Message reception and display
- Notification actions handling
- Deep linking

### 2. In-App Messages
- Modal, banner, fullscreen, and card message types
- Event-based triggers (app_open, session_start, custom events)
- Button actions with deep links
- Rich content with images and styling

### 3. Message Inbox
- Persistent message storage
- Read/unread status management
- Archive and delete operations
- Category filtering
- Unread count badges

### 4. A/B Testing
- Active test listing
- Variant assignment
- Impression, open, and click tracking
- Cache management

### 5. VoIP Calls
- Native call UI (CallKit on iOS, CallStyle on Android)
- Audio and video call support
- Incoming call simulation
- Call management (accept, decline, end)

### 6. Settings & Debug
- Log level configuration
- Analytics toggle
- Cache management
- Connection status monitoring

## Getting Started

### Prerequisites

- Flutter 3.10.0 or higher
- Dart 3.0.0 or higher
- Android SDK 21+ (for Android)
- iOS 13.0+ (for iOS)
- A AbrovaPush API key from the AbrovaCore Console

### Setup

1. **Clone the repository**
   ```bash
   cd /path/to/abrovapush_project/examples/flutter_example
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure your API key**

   Open `lib/services/abrovapush_service.dart` and replace the API key:
   ```dart
   static const String _apiKey = 'ab_live_your_api_key_here';
   ```

4. **Run the app**
   ```bash
   # Run on connected device
   flutter run

   # Run on specific platform
   flutter run -d android
   flutter run -d ios
   ```

### Android Setup

The example includes:
- `AndroidManifest.xml` with all required permissions
- Notification icon (`ic_notification`)
- Deep link scheme (`abrovapush://`)

For release builds, configure signing in `android/app/build.gradle`.

### iOS Setup

The example includes:
- `Info.plist` with background modes (remote-notification, voip)
- Push notification entitlements
- Deep link URL scheme

For push notifications:
1. Enable "Push Notifications" capability in Xcode
2. Configure your APNs certificate in the AbrovaCore Console

## Project Structure

```
flutter_example/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── services/
│   │   └── abrovapush_service.dart     # SDK wrapper service
│   ├── screens/
│   │   ├── home_screen.dart         # Main dashboard
│   │   ├── push_notifications_screen.dart
│   │   ├── inapp_messages_screen.dart
│   │   ├── inbox_screen.dart
│   │   ├── ab_testing_screen.dart
│   │   ├── voip_screen.dart
│   │   ├── call_screen.dart
│   │   └── settings_screen.dart
│   └── widgets/
│       └── inapp_message_widget.dart
├── android/                          # Android configuration
├── ios/                              # iOS configuration
└── pubspec.yaml
```

## SDK Integration Guide

### Initialization

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize with API key (MQTT config auto-fetched)
  await AbrovaPush.init(AbrovaPushConfig(
    apiKey: 'ab_live_your_key',
    notificationIcon: 'ic_notification', // Android only
  ));

  runApp(MyApp());
}
```

### Device Registration

```dart
// Register device
await AbrovaPush.register(
  userId: 'user_123',  // Optional: for targeted notifications
  metadata: {'appVersion': '1.0.0'},
);

// Get device ID
final deviceId = await AbrovaPush.getDeviceId();
```

### Message Handling

```dart
// Listen for messages
AbrovaPush.onMessage((message) {
  print('Received: ${message.title}');
  print('Data: ${message.data}');
});

// Handle notification actions
AbrovaPush.onNotificationAction((event) {
  print('Action: ${event.actionId}');
});
```

### Topics

```dart
await AbrovaPush.subscribeTopic('news');
await AbrovaPush.unsubscribeTopic('promotions');
```

### In-App Messages

```dart
// Trigger on app open
await AbrovaPush.triggerInAppOnAppOpen();

// Trigger custom event
await AbrovaPush.triggerInAppEvent('purchase_complete');

// Listen for messages
AbrovaPush.onInAppMessageReady((message) {
  // Display message
});
```

### Inbox

```dart
// Get messages
final response = await AbrovaPush.getInboxMessages(
  status: InboxMessageStatus.unread,
  limit: 50,
);

// Mark as read
await AbrovaPush.markInboxMessageAsRead(messageId);

// Get unread count
final count = await AbrovaPush.getInboxUnreadCount();
```

### A/B Testing

```dart
// Get variant
final variant = await AbrovaPush.getABTestVariant('test_id');

if (variant != null) {
  // Apply variant
  if (variant.isControl) {
    // Show control
  } else {
    // Show test variant
  }

  // Track impression
  await AbrovaPush.trackABTestImpression(variant.testId, variant.variantId);
}
```

### VoIP Calls

```dart
// Initialize VoIP
await AbrovaPushVoIP.init(
  config: AbrovaPushVoIPConfig(appName: 'My App'),
  onCallAccepted: (callData) {
    // Navigate to call screen
  },
  onCallDeclined: (callData) {
    // Handle declined
  },
);
```

## Connection Monitoring

```dart
AbrovaPush.onConnectionState((connected) {
  print(connected ? 'Connected' : 'Disconnected');
});

AbrovaPush.onReconnecting((state) {
  print('Retry ${state.retryAttempt}, next in ${state.nextRetryMs}ms');
});
```

## Error Handling

```dart
AbrovaPush.onError((error) {
  print('Error: $error');
});

AbrovaPush.onDetailedError((error) {
  print('Code: ${error.code}, Message: ${error.message}');
});
```

## Related Documentation

- [AbrovaCore Console](https://console.abrovacore.io) - Manage your projects
- [AbrovaCore User Management](../../flutter/abrovapush/README.md) - SDK documentation
- [AbrovaCore Ecosystem Docs](https://docs.abrovacore.io) - Full documentation

## License

Copyright (c) AbrovaCore. All rights reserved.
