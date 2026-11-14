import 'package:abrova_push/abrova_push.dart';
import 'package:flutter_test/flutter_test.dart';

/// webPush is web-only and opt-in: off, the init map is the same as before; on, the web side gets it.
void main() {
  test('webPush is off by default and not in the init map', () {
    const config = AbrovaPushConfig(apiKey: 'ab_live_test');
    expect(config.webPush, isFalse);
    expect(config.toMap().containsKey('webPush'), isFalse);
  });

  test('webPush: true is passed on', () {
    const config = AbrovaPushConfig(apiKey: 'ab_live_test', webPush: true);
    expect(config.toMap()['webPush'], isTrue);
  });
}
