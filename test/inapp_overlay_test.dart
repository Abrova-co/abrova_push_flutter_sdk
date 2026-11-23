import 'package:abrova_push/abrova_push.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The built-in in-app display follows the Console's preview: image ratios, banner top or bottom with its
/// buttons, close button on the start side for right-to-left text, card at the bottom without dimming; and the
/// notifications-off API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.abrova.push/main');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  bool? enabled = true;

  setUp(() async {
    calls.clear();
    enabled = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'areNotificationsEnabled':
          return enabled;
        case 'openNotificationSettings':
          return true;
      }
      return null;
    });
    // Installs the SDK's handler for calls from the native side.
    await AbrovaPush.setTokenProvider(null);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> fromNative(String method, Object? args) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  Map<String, Object?> message(String type,
          {String? image,
          String? position,
          List<Map<String, Object?>> buttons = const [],
          String title = 'Hello'}) =>
      {
        'id': 'm-$type',
        'name': 'n',
        'type': type,
        'content': {
          'title': title,
          'body': 'Body text',
          if (image != null) 'imageUrl': image,
          if (position != null) 'position': position,
          'buttons': buttons,
        },
      };

  Future<void> show(WidgetTester tester, Map<String, Object?> m,
      {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(AbrovaPushInAppOverlay(
      child: MaterialApp(
          locale: locale, home: const Scaffold(body: SizedBox.expand())),
    ));
    await fromNative('onInAppMessageReady', m);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double imageRatio(WidgetTester tester) {
    final box = tester.widget<AspectRatio>(find
        .ancestor(of: find.byType(Image), matching: find.byType(AspectRatio))
        .first);
    return box.aspectRatio;
  }

  testWidgets('modal image is 2:1, buttons stacked', (tester) async {
    await show(
        tester,
        message('modal', image: 'https://x/i.png', buttons: [
          {'id': 'a', 'text': 'Open', 'action': 'dismiss', 'style': 'primary'},
          {'id': 'b', 'text': 'Later', 'action': 'dismiss', 'style': 'text'},
        ]));
    expect(imageRatio(tester), 2);
    final open = tester.getTopLeft(find.text('Open'));
    final later = tester.getTopLeft(find.text('Later'));
    expect(later.dy, greaterThan(open.dy)); // stacked
  });

  testWidgets(
      'card image is 3:1, at the bottom, buttons side by side, no dimming',
      (tester) async {
    await show(
        tester,
        message('card', image: 'https://x/i.png', buttons: [
          {'id': 'a', 'text': 'Yes', 'action': 'dismiss', 'style': 'primary'},
          {'id': 'b', 'text': 'No', 'action': 'dismiss', 'style': 'secondary'},
        ]));
    expect(imageRatio(tester), 3);
    expect(
        (tester.getTopLeft(find.text('Yes')).dy -
                tester.getTopLeft(find.text('No')).dy)
            .abs(),
        lessThan(2));
    expect(tester.getBottomLeft(find.text('Yes')).dy,
        greaterThan(400)); // lower half of the 600 px screen
    expect(
        find.byWidgetPredicate(
            (w) => w is ColoredBox && w.color.a < 1 && w.color.a > 0.3),
        findsNothing);
  });

  testWidgets('fullscreen image is 2:1', (tester) async {
    await show(tester, message('fullscreen', image: 'https://x/i.png'));
    expect(imageRatio(tester), 2);
  });

  testWidgets('banner at the bottom when the Console says so, with its buttons',
      (tester) async {
    await show(
        tester,
        message('banner', position: 'bottom', buttons: [
          {
            'id': 'a',
            'text': 'Update',
            'action': 'dismiss',
            'style': 'primary'
          },
        ]));
    expect(find.text('Update'), findsOneWidget);
    expect(tester.getCenter(find.text('Hello')).dy, greaterThan(400));
  });

  testWidgets('banner at the top by default', (tester) async {
    await show(tester, message('banner'));
    expect(tester.getCenter(find.text('Hello')).dy, lessThan(200));
  });

  testWidgets('a button records the click and closes the message',
      (tester) async {
    await show(
        tester,
        message('modal', buttons: [
          {'id': 'go', 'text': 'Go', 'action': 'dismiss', 'style': 'primary'},
        ]));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(
        calls.where((c) => c.method == 'recordInAppButtonClick'), hasLength(1));
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('close sits on the left for right-to-left text', (tester) async {
    await show(tester, message('modal', title: 'سلام'));
    final close = tester.getCenter(find.byIcon(Icons.close));
    final title = tester.getCenter(find.text('سلام'));
    expect(close.dx, lessThan(title.dx));
  });

  test('banner position is read and translations keep it', () {
    final m = InAppMessage.fromMap({
      ...message('banner', position: 'bottom'),
      'localizations': [
        {
          'locale': 'fa',
          'content': {'title': 'سلام', 'body': 'ب'},
        }
      ],
    });
    expect(m.content.position, 'bottom');
    expect(m.getLocalizedContent('fa-IR').position, 'bottom');
    expect(
        InAppMessageContent.fromMap(
            {'title': 'a', 'body': 'b', 'position': 'middle'}).position,
        isNull);
  });

  test('notification permission: read, opened, and changes come as a stream',
      () async {
    expect(await AbrovaPush.notificationPermission(),
        AbrovaPushNotificationPermission.allowed);
    enabled = false;
    expect(await AbrovaPush.notificationPermission(),
        AbrovaPushNotificationPermission.notAllowed);
    enabled = null; // web: no permission applies
    expect(await AbrovaPush.notificationPermission(),
        AbrovaPushNotificationPermission.notNeeded);
    expect(await AbrovaPush.openNotificationSettings(), isTrue);

    // A new listener first gets the current state (the SDK reports it at start, often before the app listens),
    // then each change.
    enabled = false;
    final events = <AbrovaPushNotificationPermission>[];
    final sub = AbrovaPush.onNotificationPermissionChanged.listen(events.add);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(events, [AbrovaPushNotificationPermission.notAllowed]);
    await fromNative('onNotificationPermissionChanged', true);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(events.last, AbrovaPushNotificationPermission.allowed);
    await sub.cancel();

    // A change that arrives while the current state is being read: the older state never comes after it.
    enabled = false;
    final second = <AbrovaPushNotificationPermission>[];
    final sub2 = AbrovaPush.onNotificationPermissionChanged.listen(second.add);
    await fromNative('onNotificationPermissionChanged', true);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(second.last, AbrovaPushNotificationPermission.allowed);
    await sub2.cancel();
  });

  test('config sends the two new options only when turned off', () {
    final map = const AbrovaPushConfig(apiKey: 'k').toMap();
    expect(map.containsKey('askNotificationPermission'),
        isFalse); // default on: the native default
    expect(map.containsKey('autoInAppTriggers'), isFalse);
    final own = const AbrovaPushConfig(
            apiKey: 'k',
            askNotificationPermission: false,
            autoInAppTriggers: false)
        .toMap();
    expect(own['askNotificationPermission'], isFalse);
    expect(own['autoInAppTriggers'], isFalse);
  });

  // Team on a Samsung 11-23: above MaterialApp, the overlay's Overlay was the app's root one; a text field's
  // Copy/Paste toolbar went there, found no localizations and failed (a grey page in release).
  testWidgets(
      'above MaterialApp, a text field still shows its Copy/Paste toolbar',
      (tester) async {
    await tester.pumpWidget(AbrovaPushInAppOverlay(
      child:
          const MaterialApp(home: Scaffold(body: Center(child: TextField()))),
    ));
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('with no message on screen, taps reach the app', (tester) async {
    var taps = 0;
    await tester.pumpWidget(AbrovaPushInAppOverlay(
      child: MaterialApp(
          home: Scaffold(
              body: Center(
                  child: TextButton(
                      onPressed: () => taps++, child: const Text('Go'))))),
    ));
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('a message that comes before the overlay listens shows once it does', (tester) async {
    // The screen of an app whose process outlived it: "App open" fires before the new screen's overlay exists.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await fromNative('onInAppMessageReady', message('modal', title: 'Early'));
    await tester.pumpWidget(AbrovaPushInAppOverlay(
      child: MaterialApp(home: const Scaffold(body: SizedBox.expand())),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Early'), findsOneWidget);
  });

  testWidgets('a waiting message is handed over only once', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await fromNative('onInAppMessageReady', message('banner', title: 'Once'));
    var got = 0;
    AbrovaPush.onInAppMessageReady((_) => got++);
    AbrovaPush.onInAppMessageReady((_) => got++);
    await tester.pump();
    expect(got, 1);
  });
}
