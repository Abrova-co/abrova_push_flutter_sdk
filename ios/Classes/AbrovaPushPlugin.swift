import Flutter
import UIKit
import UserNotifications
import AbrovaPushSDK

/// Flutter plugin that wraps the native AbrovaPush iOS SDK
/// This is similar to how the Android plugin wraps the AAR
public class AbrovaPushPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private static var instance: AbrovaPushPlugin?
    private var showNotificationInForeground: Bool = true

    // Queue for messages that arrive when Flutter is not attached
    private static var pendingMessages: [(String, Any?)] = []
    private static let pendingMessagesLock = NSLock()

    // The plugin instance whose Dart side has a tokenProvider. Nil when none
    // does: nothing is registered with the native SDK then.
    private static weak var tokenProviderOwner: AbrovaPushPlugin?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ir.abrova.push/main", binaryMessenger: registrar.messenger())
        let instance = AbrovaPushPlugin()
        instance.channel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
        AbrovaPushPlugin.instance = instance

        // Claim the notification-centre delegate here, at plugin registration.
        //
        // iOS delivers a tap that launched the app immediately after
        // didFinishLaunchingWithOptions returns, and DROPS it if no delegate is
        // set by then — it is never queued. Registration runs inside the host
        // app's launch (directly, or via didInitializeImplicitFlutterEngine),
        // so this is the last point that is still early enough. Claiming it in
        // init() — when Dart calls AbrovaPush.init — is far too late: the event
        // is already gone, which made a notification tapped while the app was
        // not running open the app and deliver nothing.
        UNUserNotificationCenter.current().delegate = instance

        // Scene-lifecycle hosts divert the launch tap to the scene connection
        // options; AbrovaPushLaunchCatcher captures it. Observe it here, and
        // drain again after initialize() — whichever happens last wins, and
        // takePendingLaunchResponse() only yields the response once.
        // Set up delegate to receive callbacks from native SDK
        AbrovaPush.shared.delegate = instance

        // Deliver any pending messages
        instance.deliverPendingMessages()

        Log.d("Plugin", "Flutter plugin registered")
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Dart can no longer answer: the native SDK goes on with the token it has.
        if AbrovaPushPlugin.tokenProviderOwner === self {
            AbrovaPushPlugin.tokenProviderOwner = nil
            AbrovaPush.shared.setTokenProvider(callback: nil)
        }
    }

    // MARK: - APNs Token Forwarding
    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AbrovaPush.shared.setAPNsToken(deviceToken)
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Log.d("Plugin", "APNs token forwarded: \(String(token.prefix(20)))...")
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.d("Plugin", "APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: - Remote Notification Delivery
    // Silent / background pushes delivered to the app. Confirm delivery, then
    // return false so other plugins (and the host app) still handle it and
    // own the completion handler.
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> Bool {
        AbrovaPush.shared.handleRemoteNotification(userInfo: userInfo)
        return false
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // MARK: - Core Methods
        case "init":
            handleInit(call: call, result: result)

        case "register":
            handleRegister(call: call, result: result)

        case "unregister":
            AbrovaPush.shared.unregister()
            result(nil)

        case "isConnected":
            result(AbrovaPush.shared.isConnected)

        case "getDeviceId":
            result(AbrovaPush.shared.getDeviceId())

        case "getSubscriptionId":
            result(AbrovaPush.shared.getSubscriptionId())

        case "setLogLevel":
            if let args = call.arguments as? [String: Any],
               let level = args["level"] as? String {
                AbrovaPush.shared.setLogLevel(AbrovaPushLogLevel.fromString(level))
            }
            result(nil)

        // MARK: - Topic Subscriptions
        case "subscribeTopic":
            if let args = call.arguments as? [String: Any],
               let topic = args["topic"] as? String {
                AbrovaPush.shared.subscribeTopic(topic)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Topic is required", details: nil))
            }

        case "unsubscribeTopic":
            if let args = call.arguments as? [String: Any],
               let topic = args["topic"] as? String {
                AbrovaPush.shared.unsubscribeTopic(topic)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Topic is required", details: nil))
            }

        // MARK: - User Management
        case "setUserId":
            if let args = call.arguments as? [String: Any],
               let userId = args["userId"] as? String {
                AbrovaPush.shared.setUserId(userId)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "User ID is required", details: nil))
            }

        case "clearUserId":
            AbrovaPush.shared.clearUserId()
            result(nil)

        case "setTokenProvider":
            let enabled = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
            if enabled {
                AbrovaPushPlugin.tokenProviderOwner = self
                AbrovaPush.shared.setTokenProvider(callback: { [weak self] completion in
                    guard let self = self else {
                        completion(.failure(TokenBridgeError("Flutter engine not attached")))
                        return
                    }
                    self.fetchUserTokenFromDart(completion)
                })
            } else {
                AbrovaPushPlugin.tokenProviderOwner = nil
                AbrovaPush.shared.setTokenProvider(callback: nil)
            }
            result(nil)

        case "setUserToken":
            AbrovaPush.shared.setUserToken((call.arguments as? [String: Any])?["token"] as? String)
            result(nil)

        // MARK: - Initial Message
        case "getInitialMessage":
            if let message = takeCapturedLaunchMessage() {
                result(message.toDictionary())
                return
            }
            if let message = AbrovaPush.shared.getInitialMessage() {
                AbrovaPush.shared.clearInitialMessage()
                result(message.toDictionary())
            } else {
                result(nil)
            }

        // MARK: - In-App Messages
        case "fetchInAppMessages":
            AbrovaPush.shared.fetchInAppMessages { messages in
                result(messages.map { $0.toDictionary() })
            }

        case "triggerInAppOnAppOpen":
            AbrovaPush.shared.triggerInAppOnAppOpen()
            result(nil)

        case "triggerInAppEvent":
            if let args = call.arguments as? [String: Any],
               let eventName = args["eventName"] as? String {
                let properties = args["properties"] as? [String: Any]
                AbrovaPush.shared.triggerInAppEvent(eventName, properties: properties)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Event name is required", details: nil))
            }

        case "triggerInAppOnSessionStart":
            AbrovaPush.shared.triggerInAppOnSessionStart()
            result(nil)

        case "showInAppMessage":
            if let args = call.arguments as? [String: Any],
               let messageId = args["messageId"] as? String {
                AbrovaPush.shared.showInAppMessage(messageId)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Message ID is required", details: nil))
            }

        case "dismissInAppMessage":
            AbrovaPush.shared.dismissInAppMessage()
            result(nil)

        case "recordInAppButtonClick":
            if let args = call.arguments as? [String: Any],
               let messageId = args["messageId"] as? String,
               let buttonId = args["buttonId"] as? String {
                AbrovaPush.shared.getInAppMessageManager()
                    .recordImpression(messageId: messageId, action: .buttonClick, buttonId: buttonId)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "messageId and buttonId required", details: nil))
            }

        case "recordInAppDismissed":
            if let args = call.arguments as? [String: Any],
               let messageId = args["messageId"] as? String {
                AbrovaPush.shared.getInAppMessageManager()
                    .recordImpression(messageId: messageId, action: .dismiss)
                result(nil)
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "messageId required", details: nil))
            }

        // MARK: - Inbox
        case "getInboxMessages":
            handleGetInboxMessages(call: call, result: result)

        case "getInboxMessage":
            handleGetInboxMessage(call: call, result: result)

        case "markInboxMessageAsRead":
            handleMarkInboxMessageAsRead(call: call, result: result)

        case "archiveInboxMessage":
            handleArchiveInboxMessage(call: call, result: result)

        case "deleteInboxMessage":
            handleDeleteInboxMessage(call: call, result: result)

        case "markMultipleInboxMessages":
            handleMarkMultipleInboxMessages(call: call, result: result)

        case "markAllInboxMessagesAsRead":
            AbrovaPush.shared.markAllInboxMessagesAsRead(
                onSuccess: { result(nil) },
                onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
            )

        case "getInboxUnreadCount":
            result(AbrovaPush.shared.getInboxUnreadCount())

        case "fetchInboxUnreadCount":
            AbrovaPush.shared.fetchInboxUnreadCount(
                onSuccess: { count in result(count) },
                onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
            )

        case "getCachedInboxMessages":
            result(AbrovaPush.shared.getCachedInboxMessages().map { $0.toDictionary() })

        case "clearInboxCache":
            AbrovaPush.shared.clearInboxCache()
            result(nil)

        // MARK: - A/B Testing
        case "getActiveABTests":
            AbrovaPush.shared.getActiveABTests { testResult in
                switch testResult {
                case .success(let tests):
                    result(tests.map { $0.toDictionary() })
                case .failure(let error):
                    result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                }
            }

        case "getABTestVariant":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String {
                let forceRefresh = args["forceRefresh"] as? Bool ?? false
                AbrovaPush.shared.getABTestVariant(testId: testId, forceRefresh: forceRefresh) { variantResult in
                    switch variantResult {
                    case .success(let variant):
                        result(variant.toDictionary())
                    case .failure(let error):
                        result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID is required", details: nil))
            }

        case "getCachedABTestVariant":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String {
                let variant = AbrovaPush.shared.getCachedABTestVariant(testId: testId)
                result(variant?.toDictionary())
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID is required", details: nil))
            }

        case "trackABTestImpression":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String,
               let variantId = args["variantId"] as? String {
                AbrovaPush.shared.trackABTestImpression(testId: testId, variantId: variantId) { trackResult in
                    switch trackResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID and Variant ID are required", details: nil))
            }

        case "trackABTestOpened":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String,
               let variantId = args["variantId"] as? String {
                AbrovaPush.shared.trackABTestOpened(testId: testId, variantId: variantId) { trackResult in
                    switch trackResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID and Variant ID are required", details: nil))
            }

        case "trackABTestClicked":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String,
               let variantId = args["variantId"] as? String {
                AbrovaPush.shared.trackABTestClicked(testId: testId, variantId: variantId) { trackResult in
                    switch trackResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID and Variant ID are required", details: nil))
            }

        case "trackABTestDisplay":
            if let args = call.arguments as? [String: Any],
               let testId = args["testId"] as? String,
               let variantId = args["variantId"] as? String {
                // Create a minimal variant for tracking
                let variant = ABTestVariant(testId: testId, variantId: variantId, variantName: "", content: nil)
                AbrovaPush.shared.trackABTestDisplay(variant: variant) { trackResult in
                    switch trackResult {
                    case .success:
                        result(nil)
                    case .failure(let error):
                        result(FlutterError(code: "ABTEST_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            } else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "Test ID and Variant ID are required", details: nil))
            }

        case "clearABTestCache":
            AbrovaPush.shared.clearABTestCache()
            result(nil)

        // Log level
        case "getLogLevel":
            result(nil) // iOS doesn't expose log level as a string getter

        // Badge management
        case "getBadgeCount":
            result(UIApplication.shared.applicationIconBadgeNumber)
        case "setBadgeCount":
            if let badgeArgs = call.arguments as? [String: Any],
               let count = badgeArgs["count"] as? Int {
                UIApplication.shared.applicationIconBadgeNumber = count
            }
            result(nil)
        case "clearBadge":
            UIApplication.shared.applicationIconBadgeNumber = 0
            result(nil)
        case "incrementBadge":
            UIApplication.shared.applicationIconBadgeNumber += 1
            result(nil)
        case "decrementBadge":
            let current = UIApplication.shared.applicationIconBadgeNumber
            UIApplication.shared.applicationIconBadgeNumber = max(0, current - 1)
            result(nil)

        // State getters
        case "getNetworkState":
            result(["isAvailable": true, "networkType": "unknown"])
        case "getAppState":
            let foreground = UIApplication.shared.applicationState == .active
            result(["isInForeground": foreground])

        // Service notification (Android-only, no-op on iOS)
        case "isServiceNotificationHidden":
            result(true)
        case "openServiceNotificationSettings":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Handler Methods

    private func handleInit(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Arguments required", details: nil))
            return
        }

        let config = AbrovaPushConfig(
            apiKey: args["apiKey"] as? String ?? "",
            pnHost: args["pnHost"] as? String ?? args["mqttHost"] as? String ?? "",
            pnPort: UInt16(args["pnPort"] as? Int ?? args["mqttPort"] as? Int ?? 1883),
            pnToken: args["pnToken"] as? String ?? args["mqttPassword"] as? String,
            usePushKit: args["usePushKit"] as? Bool ?? false,
            showNotificationInForeground: args["showNotificationInForeground"] as? Bool ?? true,
            autoConnect: args["autoConnect"] as? Bool ?? true,
            appGroup: args["appGroup"] as? String,
            autoRefresh: args["autoRefresh"] as? Bool ?? true,
            wrapperSdkName: args["wrapperSdkName"] as? String,
            wrapperSdkVersion: args["wrapperSdkVersion"] as? String,
            sendDiagnostics: args["sendDiagnostics"] as? Bool ?? true
        )

        AbrovaPush.shared.initialize(config: config)
        self.showNotificationInForeground = args["showNotificationInForeground"] as? Bool ?? true

        // Normally already claimed in didFinishLaunchingWithOptions above;
        // re-assert in case the host app replaced the delegate after launch.
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission
        let usePushKit = args["usePushKit"] as? Bool ?? false
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted && !usePushKit {
                // Only register for APNs when not using PushKit
                // PushKit registration is handled by the native SDK internally
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }

        // Set up callbacks after SDK is initialized (slight delay to ensure SDK is ready)
        DispatchQueue.main.async {
            AbrovaPush.shared.setInboxCallback(self)
            AbrovaPush.shared.setInAppMessageCallback(self)
            AbrovaPush.shared.setABTestingDelegate(self)
        }

        result(nil)
    }

    private func handleRegister(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let userId = args?["userId"] as? String
        // Metadata carries native JSON types (Int, Double, Bool, String) over
        // the method channel so dashboard segments get real numbers/booleans,
        // not stringified values. Pre-0.1.11 forced [String: String].
        let metadata = args?["metadata"] as? [String: Any]

        AbrovaPush.shared.register(userId: userId, metadata: metadata)
        result(nil)
    }

    private func handleGetInboxMessages(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        var filter = InboxFilter()

        if let filterArgs = args?["filter"] as? [String: Any] {
            filter = InboxFilter(
                status: filterArgs["status"] != nil ? InboxMessageStatus.fromString(filterArgs["status"] as! String) : nil,
                category: filterArgs["category"] as? String,
                limit: filterArgs["limit"] as? Int ?? 50,
                offset: filterArgs["offset"] as? Int ?? 0
            )
        }

        AbrovaPush.shared.getInboxMessages(
            filter: filter,
            onSuccess: { response in
                result(response.toDictionary())
            },
            onError: { error in
                result(FlutterError(code: "ERROR", message: error, details: nil))
            }
        )
    }

    private func handleGetInboxMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageId = args["messageId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Message ID is required", details: nil))
            return
        }

        AbrovaPush.shared.getInboxMessage(
            messageId: messageId,
            onSuccess: { message in result(message.toDictionary()) },
            onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
        )
    }

    private func handleMarkInboxMessageAsRead(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageId = args["messageId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Message ID is required", details: nil))
            return
        }

        AbrovaPush.shared.markInboxMessageAsRead(
            messageId: messageId,
            onSuccess: { result(nil) },
            onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
        )
    }

    private func handleArchiveInboxMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageId = args["messageId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Message ID is required", details: nil))
            return
        }

        AbrovaPush.shared.archiveInboxMessage(
            messageId: messageId,
            onSuccess: { result(nil) },
            onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
        )
    }

    private func handleDeleteInboxMessage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageId = args["messageId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Message ID is required", details: nil))
            return
        }

        AbrovaPush.shared.deleteInboxMessage(
            messageId: messageId,
            onSuccess: { result(nil) },
            onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
        )
    }

    private func handleMarkMultipleInboxMessages(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let messageIds = args["messageIds"] as? [String],
              let statusStr = args["status"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Message IDs and status are required", details: nil))
            return
        }

        AbrovaPush.shared.markMultipleInboxMessages(
            messageIds: messageIds,
            status: InboxMessageStatus.fromString(statusStr),
            onSuccess: { result(nil) },
            onError: { error in result(FlutterError(code: "ERROR", message: error, details: nil)) }
        )
    }

    // MARK: - Scene-Launch Tap Replay

    /// Flutter's supported scene-lifecycle hook for plugins.
    ///
    /// Plugins added via `registrar.addApplicationDelegate` are forwarded scene
    /// events by FlutterPluginSceneLifeCycleDelegate. This is the same launch
    /// tap AbrovaPushLaunchCatcher swizzles for; whichever arrives first wins,
    /// since takePendingLaunchResponse() only yields it once.
    @available(iOS 13.0, *)
    @objc public func scene(_ scene: UIScene,
                            willConnectTo session: UISceneSession,
                            options connectionOptions: UIScene.ConnectionOptions) -> Bool {
        if let response = connectionOptions.notificationResponse {
            AbrovaPushLaunchCatcher.store(response)
            return true
        }
        return false
    }

    /// Parses a launch tap captured by AbrovaPushLaunchCatcher, if there is one.
    ///
    /// The captured response is deliberately NOT replayed through
    /// `AbrovaPush.shared.userNotificationCenter(...)`. Two things make that
    /// unreliable at launch on a scene-based host:
    ///
    ///  * it happens before Dart calls `initialize()`, so the SDK is not ready; and
    ///  * `handleNotificationResponse` only stores an initial message when
    ///    `delegate == nil`, and the plugin sets itself as the delegate at
    ///    registration — so the launch tap would be dispatched as a live
    ///    callback and never stored. (Same shape as the Android bug.)
    ///
    /// Parsing here instead makes the result deterministic: the tap is held
    /// until Dart asks for it, then answered synchronously.
    private func takeCapturedLaunchMessage() -> AbrovaPushMessage? {
        guard let response = AbrovaPushLaunchCatcher.takePendingLaunchResponse() else { return nil }

        let userInfo = response.notification.request.content.userInfo
        reportLaunchResponse(userInfo: userInfo, actionIdentifier: response.actionIdentifier)

        if let messageDict = userInfo["abrova_push_message"] as? [String: Any] {
            let payload: [AnyHashable: Any] =
                Dictionary(uniqueKeysWithValues: messageDict.map { ($0.key, $0.value) })
            return AbrovaPushMessage.from(payload: payload)
        }
        return AbrovaPushMessage.from(payload: userInfo)
    }

    /// The launch tap skips the SDK's response handling (see above), so report
    /// it as opened / clicked here. Looked up at run time: the call exists
    /// only in newer AbrovaPushSDK versions, and with an older one this is a
    /// no-op instead of a build error.
    private func reportLaunchResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        let selector = NSSelectorFromString("reportNotificationResponseWithUserInfo:actionIdentifier:")
        guard AbrovaPush.shared.responds(to: selector) else { return }
        _ = AbrovaPush.shared.perform(selector, with: userInfo as NSDictionary, with: actionIdentifier as NSString)
    }

    // MARK: - Signed User Tokens

    private struct TokenBridgeError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Asks Dart for the user token. Completes with nil when Dart says no user
    /// is signed in, and with a failure when Dart cannot answer, so the native
    /// SDK keeps the token it already has.
    private func fetchUserTokenFromDart(_ completion: @escaping (Result<String?, Error>) -> Void) {
        DispatchQueue.main.async {
            guard AbrovaPushPlugin.tokenProviderOwner === self, let channel = self.channel else {
                completion(.failure(TokenBridgeError("Flutter engine not attached")))
                return
            }
            channel.invokeMethod("getUserToken", arguments: nil) { reply in
                if let error = reply as? FlutterError {
                    completion(.failure(TokenBridgeError(error.message ?? error.code)))
                } else if FlutterMethodNotImplemented.isEqual(reply) {
                    completion(.failure(TokenBridgeError("Dart side is not ready")))
                } else {
                    completion(.success(reply as? String))
                }
            }
        }
    }

    // MARK: - Flutter Method Invocation

    private func invokeMethod(_ method: String, arguments: Any?) {
        DispatchQueue.main.async {
            if let channel = self.channel {
                channel.invokeMethod(method, arguments: arguments)
            } else {
                // Queue the message for later delivery
                AbrovaPushPlugin.pendingMessagesLock.lock()
                AbrovaPushPlugin.pendingMessages.append((method, arguments))
                AbrovaPushPlugin.pendingMessagesLock.unlock()
            }
        }
    }

    private func deliverPendingMessages() {
        AbrovaPushPlugin.pendingMessagesLock.lock()
        defer { AbrovaPushPlugin.pendingMessagesLock.unlock() }

        guard !AbrovaPushPlugin.pendingMessages.isEmpty else { return }

        let messages = AbrovaPushPlugin.pendingMessages
        AbrovaPushPlugin.pendingMessages.removeAll()

        DispatchQueue.main.async {
            for (method, arguments) in messages {
                self.channel?.invokeMethod(method, arguments: arguments)
            }
        }
    }
}

// MARK: - AbrovaPushDelegate
extension AbrovaPushPlugin: AbrovaPushDelegate {
    public func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveMessage message: AbrovaPushMessage) {
        invokeMethod("onMessage", arguments: message.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didChangeConnectionState connected: Bool) {
        invokeMethod("onConnectionState", arguments: connected)
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didRegisterWithDeviceId deviceId: String) {
        invokeMethod("onRegistered", arguments: deviceId)
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveVoIPToken token: String) {
        // Internal - not exposed to Flutter
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithError error: Error) {
        invokeMethod("onError", arguments: error.localizedDescription)
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithDetailedError error: AbrovaPushError) {
        invokeMethod("onDetailedError", arguments: error.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didStartReconnecting state: ReconnectionState) {
        invokeMethod("onReconnecting", arguments: state.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didChangeNetworkState state: NetworkState) {
        invokeMethod("onNetworkState", arguments: state.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didChangeAppState state: AppState) {
        invokeMethod("onAppState", arguments: state.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didDetectAppUpdate info: AppUpdateInfo) {
        invokeMethod("onAppUpdated", arguments: info.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didReceiveNotificationAction action: NotificationAction, forMessage message: AbrovaPushMessage) {
        let messageDict = message.toDictionary()
        invokeMethod("onNotificationAction", arguments: [
            "actionId": action.id,
            "title": messageDict["title"] as Any,
            "body": messageDict["body"] as Any,
            "data": messageDict["data"] as Any,
            "messageId": messageDict["messageId"] as Any
        ])
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didTapNotification message: AbrovaPushMessage) {
        invokeMethod("onNotificationTapped", arguments: message.toDictionary())
    }

    public func abrovaPush(_ abrovaPush: AbrovaPush, didFailWithAuthError event: AbrovaPushAuthErrorEvent) {
        invokeMethod("onAuthError", arguments: [
            "code": event.code,
            "message": event.message
        ])
    }
}

// MARK: - InAppMessageCallback
extension AbrovaPushPlugin: InAppMessageCallback {
    public func inAppMessageReady(_ message: InAppMessage) {
        invokeMethod("onInAppMessageReady", arguments: message.toDictionary())
    }

    public func inAppMessageButtonClicked(_ message: InAppMessage, button: InAppButton) {
        invokeMethod("onInAppButtonClick", arguments: [
            "message": message.toDictionary(),
            "button": button.toDictionary()
        ])
    }

    public func inAppMessageDismissed(_ message: InAppMessage) {
        invokeMethod("onInAppMessageDismissed", arguments: message.toDictionary())
    }

    public func inAppMessageError(_ error: String) {
        invokeMethod("onError", arguments: error)
    }
}

// MARK: - InboxCallback
extension AbrovaPushPlugin: InboxCallback {
    public func inboxMessageReceived(_ message: InboxMessage) {
        invokeMethod("onInboxMessageReceived", arguments: message.toDictionary())
    }

    public func inboxMessageStatusChanged(messageId: String, status: InboxMessageStatus) {
        invokeMethod("onInboxMessageStatusChanged", arguments: [
            "messageId": messageId,
            "status": status.rawValue
        ])
    }
}

// MARK: - ABTestingDelegate
extension AbrovaPushPlugin: ABTestingDelegate {
    public func abTestingManager(_ manager: ABTestingManager, didAssignVariant variant: ABTestVariant) {
        invokeMethod("onABTestVariantAssigned", arguments: variant.toDictionary())
    }

    public func abTestingManager(_ manager: ABTestingManager, didFailWithError error: Error, forTest testId: String?) {
        invokeMethod("onABTestError", arguments: [
            "testId": testId ?? "",
            "error": error.localizedDescription
        ])
    }
}

// MARK: - UNUserNotificationCenterDelegate (foreground notification display)
extension AbrovaPushPlugin: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // This plugin owns the notification-centre delegate, so the SDK never
        // sees willPresent. Forward it so foreground deliveries are confirmed.
        AbrovaPush.shared.handleRemoteNotification(userInfo: notification.request.content.userInfo)

        if showNotificationInForeground {
            if #available(iOS 14.0, *) {
                completionHandler([.banner, .sound, .badge])
            } else {
                completionHandler([.alert, .sound, .badge])
            }
        } else {
            completionHandler([])
        }
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Forward to the SDK — it owns the full tap pipeline (initial-message capture,
        // action routing, delegate dispatch). Plugin's didTapNotification / didReceiveNotificationAction
        // will fire onNotificationTapped / onNotificationAction to Flutter.
        AbrovaPush.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
}
