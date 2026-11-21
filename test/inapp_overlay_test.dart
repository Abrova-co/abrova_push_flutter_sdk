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
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
          {String? image, String? position, List<Map<String, Object?>> buttons = const [], String title = 'Hello'}) =>
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

  Future<void> show(WidgetTester tester, Map<String, Object?> m, {Locale locale = const Locale('en')}) async {
    await tester.pumpWidget(AbrovaPushInAppOverlay(
      child: MaterialApp(locale: locale, home: const Scaffold(body: SizedBox.expand())),
    ));
    await fromNative('onInAppMessageReady', m);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  double imageRatio(WidgetTester tester) {
    final box = tester.widget<AspectRatio>(find.ancestor(of: find.byType(Image), matching: find.byType(AspectRatio)).first);
    return box.aspectRatio;
  }

  testWidgets('modal image is 2:1, buttons stacked', (tester) async {
    await show(tester, message('modal', image: 'https://x/i.png', buttons: [
      {'id': 'a', 'text': 'Open', 'action': 'dismiss', 'style': 'primary'},
      {'id': 'b', 'text': 'Later', 'action': 'dismiss', 'style': 'text'},
    ]));
    expect(imageRatio(tester), 2);
    final open = tester.getTopLeft(find.text('Open'));
    final later = tester.getTopLeft(find.text('Later'));
    expect(later.dy, greaterThan(open.dy)); // stacked
  });

  testWidgets('card image is 3:1, at the bottom, buttons side by side, no dimming', (tester) async {
    await show(tester, message('card', image: 'https://x/i.png', buttons: [
      {'id': 'a', 'text': 'Yes', 'action': 'dismiss', 'style': 'primary'},
      {'id': 'b', 'text': 'No', 'action': 'dismiss', 'style': 'secondary'},
    ]));
    expect(imageRatio(tester), 3);
    expect((tester.getTopLeft(find.text('Yes')).dy - tester.getTopLeft(find.text('No')).dy).abs(), lessThan(2));
    expect(tester.getBottomLeft(find.text('Yes')).dy, greaterThan(400)); // lower half of the 600 px screen
    expect(find.byWidgetPredicate((w) => w is ColoredBox && w.color.a < 1 && w.color.a > 0.3), findsNothing);
  });

  testWidgets('fullscreen image is 2:1', (tester) async {
    await show(tester, message('fullscreen', image: 'https://x/i.png'));
    expect(imageRatio(tester), 2);
  });

  testWidgets('banner at the bottom when the Console says so, with its buttons', (tester) async {
    await show(tester, message('banner', position: 'bottom', buttons: [
      {'id': 'a', 'text': 'Update', 'action': 'dismiss', 'style': 'primary'},
    ]));
    expect(find.text('Update'), findsOneWidget);
    expect(tester.getCenter(find.text('Hello')).dy, greaterThan(400));
  });

  testWidgets('banner at the top by default', (tester) async {
    await show(tester, message('banner'));
    expect(tester.getCenter(find.text('Hello')).dy, lessThan(200));
  });

  testWidgets('a button records the click and closes the message', (tester) async {
    await show(tester, message('modal', buttons: [
      {'id': 'go', 'text': 'Go', 'action': 'dismiss', 'style': 'primary'},
    ]));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(calls.where((c) => c.method == 'recordInAppButtonClick'), hasLength(1));
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
    expect(InAppMessageContent.fromMap({'title': 'a', 'body': 'b', 'position': 'middle'}).position, isNull);
  });

  test('notification permission: read, opened, and changes come as a stream', () async {
    expect(await AbrovaPush.notificationPermission(), AbrovaPushNotificationPermission.allowed);
    enabled = false;
    expect(await AbrovaPush.notificationPermission(), AbrovaPushNotificationPermission.notAllowed);
    enabled = null; // web: no permission applies
    expect(await AbrovaPush.notificationPermission(), AbrovaPushNotificationPermission.notNeeded);
    expect(await AbrovaPush.openNotificationSettings(), isTrue);

    final next = AbrovaPush.onNotificationPermissionChanged.first;
    await fromNative('onNotificationPermissionChanged', false);
    expect(await next, AbrovaPushNotificationPermission.notAllowed);
  });
}
