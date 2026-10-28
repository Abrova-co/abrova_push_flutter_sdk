import 'package:flutter_test/flutter_test.dart';
import 'package:abrova_push/abrova_push.dart';

void main() {
  group('AbrovaPushLogLevel', () {
    test('all log levels are defined', () {
      expect(AbrovaPushLogLevel.values.length, 6);
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.none));
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.error));
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.warning));
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.info));
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.debug));
      expect(AbrovaPushLogLevel.values, contains(AbrovaPushLogLevel.verbose));
    });
  });

  group('AbrovaPushAnalyticsEvent', () {
    test('all analytics events are defined', () {
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.sdkInitialized));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.deviceRegistered));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.deviceUnregistered));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.messageReceived));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.messageDisplayed));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.connected));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.disconnected));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.connectionError));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.topicSubscribed));
      expect(AbrovaPushAnalyticsEvent.values, contains(AbrovaPushAnalyticsEvent.topicUnsubscribed));
    });
  });

  group('NetworkType', () {
    test('fromString returns correct type for wifi', () {
      expect(NetworkType.fromString('wifi'), NetworkType.wifi);
      expect(NetworkType.fromString('WIFI'), NetworkType.wifi);
    });

    test('fromString returns correct type for cellular', () {
      expect(NetworkType.fromString('cellular'), NetworkType.cellular);
    });

    test('fromString returns correct type for ethernet', () {
      expect(NetworkType.fromString('ethernet'), NetworkType.ethernet);
    });

    test('fromString returns correct type for vpn', () {
      expect(NetworkType.fromString('vpn'), NetworkType.vpn);
    });

    test('fromString returns correct type for none', () {
      expect(NetworkType.fromString('none'), NetworkType.none);
    });

    test('fromString returns unknown for invalid input', () {
      expect(NetworkType.fromString('invalid'), NetworkType.unknown);
      expect(NetworkType.fromString(''), NetworkType.unknown);
    });
  });

  group('NetworkState', () {
    test('creates correctly from map', () {
      final map = {
        'isAvailable': true,
        'networkType': 'wifi',
      };
      final state = NetworkState.fromMap(map);

      expect(state.isAvailable, true);
      expect(state.networkType, NetworkType.wifi);
    });

    test('isWifi returns true for wifi connection', () {
      final state = NetworkState(isAvailable: true, networkType: NetworkType.wifi);
      expect(state.isWifi, true);
      expect(state.isCellular, false);
    });

    test('isCellular returns true for cellular connection', () {
      final state = NetworkState(isAvailable: true, networkType: NetworkType.cellular);
      expect(state.isCellular, true);
      expect(state.isWifi, false);
    });

    test('toString includes all values', () {
      final state = NetworkState(isAvailable: true, networkType: NetworkType.wifi);
      final str = state.toString();
      expect(str, contains('available: true'));
      expect(str, contains('type: wifi'));
    });
  });

  group('AppState', () {
    test('creates correctly from map', () {
      final map = {'isInForeground': true};
      final state = AppState.fromMap(map);

      expect(state.isInForeground, true);
    });

    test('handles missing values with defaults', () {
      final map = <String, dynamic>{};
      final state = AppState.fromMap(map);

      expect(state.isInForeground, false);
    });

    test('toString includes all values', () {
      final state = AppState(isInForeground: true);
      expect(state.toString(), contains('isInForeground: true'));
    });
  });

  group('ReconnectionState', () {
    test('creates correctly from map', () {
      final map = {
        'retryAttempt': 2,
        'nextRetryMs': 5000,
      };
      final state = ReconnectionState.fromMap(map);

      expect(state.retryAttempt, 2);
      expect(state.nextRetryMs, 5000);
    });

    test('nextRetryDuration returns correct Duration', () {
      final state = ReconnectionState(retryAttempt: 1, nextRetryMs: 3000);
      expect(state.nextRetryDuration, Duration(milliseconds: 3000));
    });

    test('handles missing values with defaults', () {
      final map = <String, dynamic>{};
      final state = ReconnectionState.fromMap(map);

      expect(state.retryAttempt, 0);
      expect(state.nextRetryMs, 0);
    });
  });

  group('AppUpdateInfo', () {
    test('creates correctly from map', () {
      final map = {
        'previousVersion': '1.0.0',
        'currentVersion': '1.1.0',
        'needsReregistration': true,
      };
      final info = AppUpdateInfo.fromMap(map);

      expect(info.previousVersion, '1.0.0');
      expect(info.currentVersion, '1.1.0');
      expect(info.needsReregistration, true);
    });

    test('handles missing values with defaults', () {
      final map = <String, dynamic>{};
      final info = AppUpdateInfo.fromMap(map);

      expect(info.previousVersion, 'unknown');
      expect(info.currentVersion, 'unknown');
      expect(info.needsReregistration, false);
    });
  });

  group('AbrovaPushError', () {
    test('creates correctly from map', () {
      final map = {
        'code': 1000,
        'details': 'Connection failed',
      };
      final error = AbrovaPushError.fromMap(map);

      expect(error.code, 1000);
      expect(error.errorCode, AbrovaPushErrorCode.connectionFailed);
      expect(error.message, 'Failed to connect to MQTT broker');
      expect(error.details, 'Connection failed');
    });

    test('handles unknown error code', () {
      final map = {
        'code': 99999,
      };
      final error = AbrovaPushError.fromMap(map);

      expect(error.errorCode, AbrovaPushErrorCode.unknownError);
    });

    test('toMap returns correct structure', () {
      final error = AbrovaPushError(
        errorCode: AbrovaPushErrorCode.connectionTimeout,
        details: 'Timed out after 30s',
      );
      final map = error.toMap();

      expect(map['code'], 1001);
      expect(map['message'], 'Connection timed out');
      expect(map['details'], 'Timed out after 30s');
    });
  });

  group('AbrovaPush Analytics', () {
    test('isAnalyticsEnabled is false by default', () {
      AbrovaPush.disableAnalytics();
      expect(AbrovaPush.isAnalyticsEnabled, false);
    });

    test('enableAnalytics enables analytics', () {
      AbrovaPush.enableAnalytics();
      expect(AbrovaPush.isAnalyticsEnabled, true);
      // Clean up
      AbrovaPush.disableAnalytics();
    });

    test('setAnalyticsHandler enables analytics', () {
      AbrovaPush.setAnalyticsHandler((event, props) {});
      expect(AbrovaPush.isAnalyticsEnabled, true);
      // Clean up
      AbrovaPush.disableAnalytics();
    });

    test('disableAnalytics disables analytics', () {
      AbrovaPush.setAnalyticsHandler((event, props) {});
      AbrovaPush.disableAnalytics();
      expect(AbrovaPush.isAnalyticsEnabled, false);
    });
  });
}
