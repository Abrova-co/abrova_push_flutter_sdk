# AbrovaPush Flutter SDK

Real-time push notifications, in-app messages, inbox, A/B testing, and more for Flutter apps. No Firebase dependency.

## Features

- Push Notifications (Android & iOS)
- In-App Messages (modal, banner, fullscreen)
- Inbox (persistent message center with read/archive)
- A/B Testing (experiments and variant assignment)
- Topic Subscriptions
- Silent Messages
- Notification Tap Handling
- Analytics Tracking
- Auto-reconnection with exponential backoff

## Installation

The package is published on [Abrova Center](https://center.abrova.ir). Add to your `pubspec.yaml`:

```yaml
dependencies:
  abrova_push:
    hosted: https://center.abrova.ir/api/packages/abrova/pub
    version: ^0.1.27
```

iOS and Android need no other setup: the plugin brings the native SDKs from Abrova Center itself.

If your app uses CocoaPods instead of Swift Package Manager, add these two lines at the top of `ios/Podfile`:

```ruby
source 'https://center.abrova.ir/abrova/specs.git'
source 'https://cdn.cocoapods.org/'
```

Then run:

```bash
flutter pub get
```

## Quick Start

### 1. Initialize

```dart
import 'package:abrova_push/abrova_push.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AbrovaPush.init(AbrovaPushConfig(
    apiKey: 'ab_live_your_api_key',  // Get from Abrova Console
  ));

  runApp(MyApp());
}
```

### 2. Register & Listen

```dart
@override
void initState() {
  super.initState();

  // Listen for messages
  AbrovaPush.onMessage((message) {
    print('Title: ${message.title}');
    print('Body: ${message.body}');
    print('Data: ${message.data}');
  });

  // Connection status
  AbrovaPush.onConnectionState((connected) {
    print(connected ? 'Connected' : 'Disconnected');
  });

  // Register device
  AbrovaPush.register(userId: 'user_123');
}
```

### 3. Done!

Your app now receives push notifications.

## Platform Setup

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

#### Optional: Firebase (Android)

Android may close the Abrova connection to save battery. Adding Firebase gives a
second delivery path, so pushes still arrive. Devices where Google services are
blocked or missing keep using the Abrova connection.

1. Add `google-services.json` to `android/app/` and apply the Google services plugin.
2. Add the add-on in `android/app/build.gradle`:

```gradle
dependencies {
    implementation("ir.abrova:abrova-push-fcm:0.1.0")
}
```

3. Upload your Firebase service account in Abrova Console under Push -> Settings.

Nothing else changes: messages arriving over both paths are shown once.

### iOS

Enable in Xcode -> Signing & Capabilities:
- Push Notifications
- Background Modes -> Remote notifications

## Configuration

```dart
await AbrovaPush.init(AbrovaPushConfig(
  apiKey: 'ab_live_...',              // Required - from Abrova Console
  notificationIcon: 'ic_notification', // Optional - Android notification icon
  usePushKit: false,                   // Optional - iOS VoIP mode for calling apps
  showServiceNotification: true,       // Optional - foreground service notification (Android)
  showNotificationInForeground: true,  // Optional - show notifications when app is in foreground
  autoRefresh: true,                   // Optional - refresh the registration on launch (24h or app/SDK/user change)
  sendDiagnostics: true,               // Optional - send counts of the SDK's own errors (no personal data)
));
```

> **Note:** Connection configuration is automatically fetched from the server using your API key. No manual setup needed.

## Callbacks

```dart
// Receive push messages
AbrovaPush.onMessage((AbrovaPushMessage message) {
  print('${message.title}: ${message.body}');
  print('Data: ${message.data}');
  print('Silent: ${message.silent}');
});

// Connection status
AbrovaPush.onConnectionState((bool connected) {});

// Registration complete
AbrovaPush.onRegistered((String deviceId) {});

// Notification tapped (while app is running)
AbrovaPush.onNotificationTapped((AbrovaPushMessage message) {});

// Errors
AbrovaPush.onError((String error) {});

// Detailed errors with error codes
AbrovaPush.onDetailedError((AbrovaPushError error) {
  print('Code: ${error.code}, Message: ${error.message}');
});

// Reconnection attempts
AbrovaPush.onReconnecting((state) {
  print('Attempt ${state.retryAttempt}, next in ${state.nextRetryMs}ms');
});

// Network state changes
AbrovaPush.onNetworkState((state) {
  print('Network: ${state.isAvailable ? "available" : "unavailable"}');
});

// App foreground/background
AbrovaPush.onAppState((state) {
  print('Foreground: ${state.isInForeground}');
});
```

## Notification Tap Handling

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AbrovaPush.init(config);

  // Check if app was launched by tapping a notification
  final initialMessage = await AbrovaPush.getInitialMessage();
  if (initialMessage != null) {
    runApp(MyApp(initialRoute: getRouteFromMessage(initialMessage)));
  } else {
    runApp(MyApp());
  }
}
```

## Topics

```dart
// Subscribe to topic
await AbrovaPush.subscribeTopic('news');
await AbrovaPush.subscribeTopic('promotions');

// Unsubscribe
await AbrovaPush.unsubscribeTopic('promotions');
```

## User Management

```dart
// Set user ID after login
await AbrovaPush.setUserId('user_123');

// Clear user ID on logout
await AbrovaPush.clearUserId();

// Register with user ID and metadata
await AbrovaPush.register(
  userId: 'user_123',
  metadata: {'appVersion': '1.0.0', 'language': 'en'},
);
```

## Signed User Tokens

Optional. If your server issues Abrova user tokens, give the SDK a `tokenProvider` and every request is
sent on behalf of that signed-in user. It is the same token (and can be the same function) you pass to
Abrova Chat. Without a provider the SDK works exactly as before.

```dart
Future<String> fetchAbrovaToken() async {
  final res = await myApi.post('/abrova/token'); // your server mints the token
  return res.data['token'] as String;
}

await AbrovaPush.init(AbrovaPushConfig(
  apiKey: 'ab_live_your_api_key',
  tokenProvider: fetchAbrovaToken, // return null when no user is signed in
));

AbrovaPush.onAuthError((event) {
  // token_invalid, token_required, token_expired, token_mismatch, token_provider_failed
  print('Auth error: ${event.code}');
});
```

`AbrovaPush.setTokenProvider(...)` sets or removes the provider later, and `AbrovaPush.setUserToken(token)`
hands over a token you fetched yourself.

## In-App Messages

```dart
// Trigger in-app messages on app open
await AbrovaPush.triggerInAppOnAppOpen();

// Trigger custom event
await AbrovaPush.triggerInAppEvent('purchase_complete', properties: {
  'amount': 29.99,
});

// Listen for in-app messages
AbrovaPush.onInAppMessageReady((message) {
  print('In-app message: ${message.name}');
});

AbrovaPush.onInAppButtonClick((message, button) {
  print('Button clicked: ${button.text}');
});
```

## Inbox

```dart
// Get inbox messages
final response = await AbrovaPush.getInboxMessages(
  status: InboxMessageStatus.unread,
  limit: 50,
);

// Mark as read
await AbrovaPush.markInboxMessageAsRead(messageId);

// Archive
await AbrovaPush.archiveInboxMessage(messageId);

// Get unread count
final count = await AbrovaPush.getInboxUnreadCount();

// Listen for new inbox messages
AbrovaPush.onInboxMessage((message) {
  print('New inbox message: ${message.content.title}');
});
```

## A/B Testing

```dart
// Get active tests
final tests = await AbrovaPush.getActiveABTests();

// Get variant for a test
final variant = await AbrovaPush.getABTestVariant('test_id');
if (variant != null) {
  print('Variant: ${variant.variantName}');
  print('Content: ${variant.content}');
}

// Track events
await AbrovaPush.trackABTestImpression('test_id', 'variant_id');
await AbrovaPush.trackABTestClicked('test_id', 'variant_id');

// Listen for variant assignments
AbrovaPush.onABTestVariantAssigned((variant) {
  print('Assigned to: ${variant.variantName}');
});
```

## Analytics Tracking

Track SDK events for your analytics service:

```dart
AbrovaPush.setAnalyticsHandler((event, properties) {
  // Send to your analytics service
  FirebaseAnalytics.instance.logEvent(
    name: 'abrova_push_${event.name}',
    parameters: properties,
  );
});
```

## Log Levels

```dart
import 'package:flutter/foundation.dart';

if (kReleaseMode) {
  await AbrovaPush.setLogLevel(AbrovaPushLogLevel.error);
} else {
  await AbrovaPush.setLogLevel(AbrovaPushLogLevel.debug);
}

// Available: none, error, warning, info, debug, verbose
```

## Utilities

```dart
final connected = await AbrovaPush.isConnected();
final deviceId = await AbrovaPush.getDeviceId();
await AbrovaPush.unregister();
```

## Example

See the [example](example/) directory for a complete working app with all features demonstrated.

## VoIP Calls (Optional)

For apps with calling features, add the [abrova_push_voip](https://center.abrova.ir/packages/abrova_push_voip/) plugin for native incoming call UI:

```yaml
dependencies:
  abrova_push:
    hosted: https://center.abrova.ir/api/packages/abrova/pub
    version: ^0.1.27
  abrova_push_voip:  # Optional - for calling apps
    hosted: https://center.abrova.ir/api/packages/abrova/pub
    version: ^0.1.3
```

```dart
// Initialize VoIP after AbrovaPush
await AbrovaPushVoIP.init(
  config: AbrovaPushVoIPConfig(appName: 'MyApp'),
  onCallAccepted: (callData) => navigateToCallScreen(callData),
  onCallDeclined: (callData) => notifyCallDeclined(callData.callId),
);

// Set API key for VoIP token registration
final deviceId = await AbrovaPush.getDeviceId();
await AbrovaPushVoIP.setApiKey(apiKey: 'ab_live_...', deviceId: deviceId);
```

To trigger an incoming call, send a push with `type: "voip_call"` in the data:

```json
{
  "title": "Incoming Call",
  "body": "John Doe is calling",
  "data": {
    "type": "voip_call",
    "callerName": "John Doe",
    "callerId": "user_456",
    "callerAvatar": "https://example.com/avatar.jpg",
    "callType": "video"
  }
}
```

The `type: "voip_call"` triggers VoIP delivery (PushKit on iOS, high-priority on Android). Without it, the message is delivered as a regular push notification. See the [abrova_push_voip README](https://center.abrova.ir/packages/abrova_push_voip/) for full setup guide.

## Links

- [Abrova Push](https://abrova.ir/cloud/abrova-push) - Learn more about Abrova Push
- [Documentation](https://abrova.ir/cloud/abrova-push/docs/quick-start) - Full documentation and guides
- [Abrova Console](https://console.abrova.ir) - Manage your push notifications

## License

MIT License - see [LICENSE](LICENSE) for details.
