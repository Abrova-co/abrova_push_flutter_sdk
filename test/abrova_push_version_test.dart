import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:abrova_push/abrova_push.dart';

void main() {
  test('abrovaPushSdkVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(abrovaPushSdkVersion, match!.group(1));
  });

  test('AbrovaPushConfig forwards wrapper identity and autoRefresh', () {
    final map = const AbrovaPushConfig(apiKey: 'key').toMap();
    expect(map['autoRefresh'], isTrue);
    expect(map['wrapperSdkName'], 'flutter');
    expect(map['wrapperSdkVersion'], abrovaPushSdkVersion);

    final disabled = const AbrovaPushConfig(apiKey: 'key', autoRefresh: false).toMap();
    expect(disabled['autoRefresh'], isFalse);
  });
}
