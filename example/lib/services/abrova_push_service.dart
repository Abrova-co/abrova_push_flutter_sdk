import 'package:flutter/foundation.dart';
import 'package:abrova_push/abrova_push.dart';
// VoIP temporarily disabled - pods not publicly available yet
// import 'package:abrova_push_voip/abrova_push_voip.dart';

/// Service class for managing AbrovaPush SDK initialization and callbacks.
///
/// This demonstrates the recommended way to integrate AbrovaPush in your app.
class AbrovaPushService {
  AbrovaPushService._();
  static final AbrovaPushService instance = AbrovaPushService._();

  // ============================================================
  // IMPORTANT: Replace with your actual API key from Abrova Console
  // ============================================================
  // Replace with your API key from Abrova Console (https://console.abrova.ir)
  static const String apiKey = 'ab_live_your_api_key_here';
  // static const String _appName = 'AbrovaPush Example';

  // State
  bool _initialized = false;
  bool get isInitialized => _initialized;

  String? _deviceId;
  String? get deviceId => _deviceId;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Callbacks for UI updates
  ValueNotifier<bool> connectionState = ValueNotifier(false);
  ValueNotifier<int> unreadInboxCount = ValueNotifier(0);
  ValueNotifier<AbrovaPushMessage?> lastMessage = ValueNotifier(null);
  // VoIP temporarily disabled
  // ValueNotifier<CallData?> incomingCall = ValueNotifier(null);

  // Callback functions that screens can set
  Function(AbrovaPushMessage)? onMessageReceived;
  Function(InAppMessage)? onInAppMessageReady;
  Function(InAppMessage, InAppButton)? onInAppButtonClick;
  Function(InboxMessage)? onInboxMessage;
  Function(AbrovaPushMessage)? onNotificationTapped;

  // Store pending notification tap if callback isn't set yet
  AbrovaPushMessage? _pendingNotificationTap;
  // VoIP temporarily disabled
  // Function(CallData)? onCallAccepted;
  // Function(CallData)? onCallDeclined;

  /// Initialize the AbrovaPush SDK with all callbacks
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Set log level based on build mode
      if (kReleaseMode) {
        await AbrovaPush.setLogLevel(AbrovaPushLogLevel.error);
      } else {
        await AbrovaPush.setLogLevel(AbrovaPushLogLevel.debug);
      }

      // Initialize AbrovaPush with config
      // Note: usePushKit must be false for iOS simulator testing
      // (VoIP/PushKit doesn't work on simulator)
      await AbrovaPush.init(
        const AbrovaPushConfig(
          apiKey: apiKey,
          notificationIcon: 'ic_notification',
          showServiceNotification: false,
          showNotificationInForeground: true,
          usePushKit:
              false, // VoIP handled by abrova_push_voip plugin independently
        ),
      );

      // Setup all callbacks
      _setupCallbacks();

      // Setup analytics handler
      _setupAnalytics();

      // VoIP temporarily disabled
      // await _initializeVoIP();

      _initialized = true;
      debugPrint('[AbrovaPushService] Initialized successfully');

      // Auto-register device for push notifications
      debugPrint('[AbrovaPushService] Registering device...');
      await register();
      debugPrint('[AbrovaPushService] Device registration initiated');
    } catch (e, stackTrace) {
      debugPrint('[AbrovaPushService] Initialization error: $e');
      debugPrint('[AbrovaPushService] Stack trace: $stackTrace');
      // Don't rethrow - allow app to run even if SDK init fails
    }
  }

  /// Setup all AbrovaPush callbacks
  void _setupCallbacks() {
    // ==================== Connection Callbacks ====================

    AbrovaPush.onConnectionState((connected) {
      debugPrint('[AbrovaPushService] Connection state: $connected');
      _isConnected = connected;
      connectionState.value = connected;
    });

    AbrovaPush.onRegistered((deviceId) {
      debugPrint('[AbrovaPushService] Registered with device ID: $deviceId');
      _deviceId = deviceId;
    });

    AbrovaPush.onError((error) {
      debugPrint('[AbrovaPushService] Error: $error');
    });

    AbrovaPush.onDetailedError((error) {
      debugPrint(
        '[AbrovaPushService] Detailed error: ${error.code} - ${error.message}',
      );
    });

    AbrovaPush.onReconnecting((state) {
      debugPrint(
        '[AbrovaPushService] Reconnecting: attempt ${state.retryAttempt}, next in ${state.nextRetryMs}ms',
      );
    });

    AbrovaPush.onNetworkState((state) {
      debugPrint(
        '[AbrovaPushService] Network: ${state.isAvailable ? "available" : "unavailable"} (${state.networkType.name})',
      );
    });

    AbrovaPush.onAppState((state) {
      debugPrint(
        '[AbrovaPushService] App state: ${state.isInForeground ? "foreground" : "background"}',
      );
    });

    AbrovaPush.onAppUpdated((info) {
      debugPrint(
        '[AbrovaPushService] App updated from ${info.previousVersion} to ${info.currentVersion}',
      );
      if (info.needsReregistration) {
        // Re-register device after app update
        register();
      }
    });

    // ==================== Message Callbacks ====================

    AbrovaPush.onMessage((message) {
      debugPrint('[AbrovaPushService] Message received: ${message.title}');
      lastMessage.value = message;
      onMessageReceived?.call(message);
    });

    AbrovaPush.onNotificationAction((event) {
      debugPrint('[AbrovaPushService] Notification action: ${event.actionId}');
      // Handle notification action button taps
      _handleNotificationAction(event);
    });

    AbrovaPush.onNotificationTapped((message) {
      debugPrint('[AbrovaPushService] Notification tapped: ${message.title}');
      debugPrint(
          '[AbrovaPushService] onNotificationTapped callback is: ${onNotificationTapped != null ? "SET" : "NULL"}');
      // Notify the UI about the tapped notification
      if (onNotificationTapped != null) {
        debugPrint(
            '[AbrovaPushService] Calling onNotificationTapped callback...');
        onNotificationTapped!(message);
        debugPrint(
            '[AbrovaPushService] onNotificationTapped callback completed');
      } else {
        debugPrint(
            '[AbrovaPushService] WARNING: No onNotificationTapped callback registered! Storing as pending...');
        _pendingNotificationTap = message;
      }
    });

    // ==================== In-App Message Callbacks ====================

    AbrovaPush.onInAppMessageReady((message) {
      debugPrint('[AbrovaPushService] In-app message ready: ${message.name}');
      onInAppMessageReady?.call(message);
    });

    AbrovaPush.onInAppButtonClick((message, button) {
      debugPrint('[AbrovaPushService] In-app button clicked: ${button.text}');
      onInAppButtonClick?.call(message, button);
    });

    AbrovaPush.onInAppMessageDismissed((message) {
      debugPrint(
          '[AbrovaPushService] In-app message dismissed: ${message.name}');
    });

    // ==================== Inbox Callbacks ====================

    AbrovaPush.onInboxMessage((message) {
      debugPrint(
        '[AbrovaPushService] New inbox message: ${message.content.title}',
      );
      onInboxMessage?.call(message);
      _refreshUnreadCount();
    });

    AbrovaPush.onInboxMessageStatusChanged((messageId, status) {
      debugPrint(
        '[AbrovaPushService] Inbox message $messageId status changed to: $status',
      );
      _refreshUnreadCount();
    });

    // ==================== A/B Testing Callbacks ====================

    AbrovaPush.onABTestVariantAssigned((variant) {
      debugPrint(
        '[AbrovaPushService] A/B test variant assigned: ${variant.variantName} for test ${variant.testId}',
      );
    });

    AbrovaPush.onABTestError((testId, error) {
      debugPrint('[AbrovaPushService] A/B test error for $testId: $error');
    });
  }

  /// Setup analytics handler
  void _setupAnalytics() {
    AbrovaPush.setAnalyticsHandler((event, properties) {
      debugPrint('[AbrovaPushService] Analytics: ${event.name} - $properties');

      // TODO: Send to your analytics service (abrova trace, Firebase, Mixpanel, etc.)
      // Example:
      // FirebaseAnalytics.instance.logEvent(
      //   name: 'abrova_push_${event.name}',
      //   parameters: properties,
      // );
    });
  }

  // VoIP temporarily disabled
  // /// Initialize VoIP plugin
  // Future<void> _initializeVoIP() async { ... }

  /// Handle notification action button taps
  void _handleNotificationAction(NotificationActionEvent event) {
    switch (event.actionId) {
      case 'view':
        debugPrint('User tapped View action');
        // Navigate to content
        break;
      case 'dismiss':
        debugPrint('User tapped Dismiss action');
        break;
      case 'reply':
        debugPrint('User tapped Reply action');
        // Show reply input
        break;
      default:
        debugPrint('Unknown action: ${event.actionId}');
    }
  }

  /// Refresh unread inbox count
  Future<void> _refreshUnreadCount() async {
    final count = await AbrovaPush.getInboxUnreadCount();
    unreadInboxCount.value = count;
  }

  // ==================== Public Methods ====================

  /// Set the notification tapped callback and check for pending taps
  void setNotificationTappedCallback(Function(AbrovaPushMessage)? callback) {
    debugPrint(
        '[AbrovaPushService] setNotificationTappedCallback called, callback is ${callback != null ? "SET" : "NULL"}');
    onNotificationTapped = callback;

    // Check for pending notification tap
    if (callback != null && _pendingNotificationTap != null) {
      debugPrint(
          '[AbrovaPushService] Found pending notification tap, delivering now: ${_pendingNotificationTap!.title}');
      final pending = _pendingNotificationTap!;
      _pendingNotificationTap = null;
      callback(pending);
    }
  }

  /// Get pending notification tap (for cold start scenarios)
  AbrovaPushMessage? getPendingNotificationTap() {
    final pending = _pendingNotificationTap;
    _pendingNotificationTap = null;
    return pending;
  }

  /// Register device for push notifications
  Future<void> register({String? userId, Map<String, String>? metadata}) async {
    await AbrovaPush.register(userId: userId, metadata: metadata);
    _deviceId = await AbrovaPush.getDeviceId();
  }

  /// Unregister device
  Future<void> unregister() async {
    await AbrovaPush.unregister();
    _deviceId = null;
  }

  /// Set user ID (after login)
  Future<void> setUserId(String userId) async {
    await AbrovaPush.setUserId(userId);
  }

  /// Clear user ID (after logout)
  Future<void> clearUserId() async {
    await AbrovaPush.clearUserId();
  }

  /// Subscribe to a topic
  Future<void> subscribeTopic(String topic) async {
    await AbrovaPush.subscribeTopic(topic);
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeTopic(String topic) async {
    await AbrovaPush.unsubscribeTopic(topic);
  }

  /// Check connection status
  Future<bool> checkConnection() async {
    return await AbrovaPush.isConnected();
  }

  /// Get device ID
  Future<String?> getDeviceId() async {
    return await AbrovaPush.getDeviceId();
  }

  // ==================== In-App Messages ====================

  /// Fetch in-app messages
  Future<List<InAppMessage>> fetchInAppMessages() async {
    return await AbrovaPush.fetchInAppMessages();
  }

  /// Trigger in-app on app open
  Future<void> triggerInAppOnAppOpen() async {
    await AbrovaPush.triggerInAppOnAppOpen();
  }

  /// Trigger custom event
  Future<void> triggerInAppEvent(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    await AbrovaPush.triggerInAppEvent(eventName, properties: properties);
  }

  /// Show specific in-app message
  Future<void> showInAppMessage(String messageId) async {
    await AbrovaPush.showInAppMessage(messageId);
  }

  /// Dismiss current in-app message
  Future<void> dismissInAppMessage() async {
    await AbrovaPush.dismissInAppMessage();
  }

  // ==================== Inbox ====================

  /// Get inbox messages
  Future<InboxMessagesResponse> getInboxMessages({
    InboxMessageStatus? status,
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    return await AbrovaPush.getInboxMessages(
      status: status,
      category: category,
      limit: limit,
      offset: offset,
    );
  }

  /// Mark inbox message as read
  Future<void> markInboxMessageAsRead(String messageId) async {
    await AbrovaPush.markInboxMessageAsRead(messageId);
    await _refreshUnreadCount();
  }

  /// Archive inbox message
  Future<void> archiveInboxMessage(String messageId) async {
    await AbrovaPush.archiveInboxMessage(messageId);
  }

  /// Delete inbox message
  Future<void> deleteInboxMessage(String messageId) async {
    await AbrovaPush.deleteInboxMessage(messageId);
  }

  /// Mark all as read
  Future<void> markAllInboxMessagesAsRead() async {
    await AbrovaPush.markAllInboxMessagesAsRead();
    await _refreshUnreadCount();
  }

  /// Get unread count
  Future<int> getInboxUnreadCount() async {
    final count = await AbrovaPush.getInboxUnreadCount();
    unreadInboxCount.value = count;
    return count;
  }

  // ==================== A/B Testing ====================

  /// Get active A/B tests
  Future<List<ABTestSummary>> getActiveABTests() async {
    return await AbrovaPush.getActiveABTests();
  }

  /// Get A/B test variant
  Future<ABTestVariant?> getABTestVariant(
    String testId, {
    bool forceRefresh = false,
  }) async {
    return await AbrovaPush.getABTestVariant(testId,
        forceRefresh: forceRefresh);
  }

  /// Track A/B test impression
  Future<void> trackABTestImpression(String testId, String variantId) async {
    await AbrovaPush.trackABTestImpression(testId, variantId);
  }

  /// Track A/B test click
  Future<void> trackABTestClicked(String testId, String variantId) async {
    await AbrovaPush.trackABTestClicked(testId, variantId);
  }

  // ==================== VoIP ====================
  // VoIP temporarily disabled - pods not publicly available yet
  // Future<void> endCall(String callId) async { ... }
  // Future<void> reportCallConnected(String callId) async { ... }
  // Future<void> showIncomingCall(CallData callData) async { ... }
}
