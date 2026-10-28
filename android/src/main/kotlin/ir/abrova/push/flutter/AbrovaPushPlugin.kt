package ir.abrova.push.flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.PluginRegistry
import androidx.annotation.NonNull
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ProcessLifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

// Import from native SDK (AAR)
import ir.abrova.push.sdk.AbrovaPush
import ir.abrova.push.sdk.AbrovaPushAuthError
import ir.abrova.push.sdk.AbrovaPushBlockingTokenProvider
import ir.abrova.push.sdk.AbrovaPushCallback
import ir.abrova.push.sdk.AbrovaPushCallbackAdapter
import ir.abrova.push.sdk.AbrovaPushConfig
import ir.abrova.push.sdk.AbrovaPushError
import ir.abrova.push.sdk.AbrovaPushLogLevel
import ir.abrova.push.sdk.AbrovaPushMessage
import ir.abrova.push.sdk.AbrovaPushService
import ir.abrova.push.sdk.Log
import ir.abrova.push.sdk.inapp.InAppMessage
import ir.abrova.push.sdk.inapp.InAppButton
import ir.abrova.push.sdk.inapp.InAppMessageCallback
import ir.abrova.push.sdk.inapp.InAppImpressionAction
import ir.abrova.push.sdk.inbox.InboxCallback
import ir.abrova.push.sdk.inbox.InboxCallbackAdapter
import ir.abrova.push.sdk.inbox.InboxFilter
import ir.abrova.push.sdk.inbox.InboxMessage
import ir.abrova.push.sdk.inbox.InboxMessageStatus
import ir.abrova.push.sdk.inbox.toMap
import ir.abrova.push.sdk.abtesting.ABTestingCallback
import ir.abrova.push.sdk.abtesting.ABTestVariant
import ir.abrova.push.sdk.abtesting.ABTestSummary
import ir.abrova.push.sdk.NetworkState
import ir.abrova.push.sdk.AppState

// Extension functions for A/B testing types to convert to Map for Flutter bridge
fun ABTestVariant.toMap(): Map<String, Any?> {
    return mapOf(
        "testId" to testId,
        "variantId" to variantId,
        "variantName" to variantName,
        "isControlGroup" to isControlGroup,
        "content" to content?.let {
            mapOf(
                "title" to it.title,
                "body" to it.body,
                "data" to it.data,
                "imageUrl" to it.imageUrl,
                "deepLink" to it.deepLink,
                "actions" to it.actions?.map { action ->
                    mapOf(
                        "id" to action.id,
                        "title" to action.title,
                        "action" to action.action
                    )
                }
            )
        }
    )
}

fun ABTestSummary.toMap(): Map<String, Any?> {
    return mapOf(
        "id" to id,
        "name" to name,
        "variantCount" to variantCount,
        "hasControlGroup" to hasControlGroup
    )
}

class AbrovaPushPlugin : FlutterPlugin, MethodCallHandler, ActivityAware,
    PluginRegistry.NewIntentListener {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var lifecycleObserver: LifecycleEventObserver? = null
    private var isInForeground = true

    companion object {
        private const val TAG = "Plugin"
        private const val CHANNEL_NAME = "ir.abrova.push/main"

        var instance: AbrovaPushPlugin? = null

        // Queue for messages that arrive when Flutter is not attached
        private val pendingMessages = mutableListOf<Pair<String, Any?>>()

        // Track lifecycle observer registration
        private var lifecycleObserverRegistered = false

        // Track if Flutter/app is in foreground - accessible by AbrovaPushService
        @Volatile
        var isFlutterInForeground = false
            private set

        /**
         * Check if Flutter engine is active and app is in foreground.
         * Used by AbrovaPushService to decide whether to show native notifications.
         */
        fun isFlutterActive(): Boolean {
            return instance != null && isFlutterInForeground
        }

        // The plugin instance whose Dart side has a tokenProvider. Null when
        // none does: nothing is registered with the native SDK then.
        @Volatile
        private var tokenProviderOwner: AbrovaPushPlugin? = null

        private const val TOKEN_REPLY_TIMEOUT_MS = 10_000L

        private val mainHandler by lazy { android.os.Handler(android.os.Looper.getMainLooper()) }

        /**
         * Asks Dart for the user token. Runs on a native SDK background thread.
         * Returns null when Dart says no user is signed in; throws when Dart
         * cannot answer, so the native SDK keeps the token it already has.
         */
        private fun fetchUserTokenFromDart(): String? {
            val owner = tokenProviderOwner ?: throw IllegalStateException("Flutter engine not attached")
            val latch = java.util.concurrent.CountDownLatch(1)
            val token = java.util.concurrent.atomic.AtomicReference<String?>(null)
            val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)

            mainHandler.post {
                try {
                    if (tokenProviderOwner !== owner) {
                        failure.set(IllegalStateException("Flutter engine not attached"))
                        latch.countDown()
                        return@post
                    }
                    owner.channel.invokeMethod("getUserToken", null, object : Result {
                        override fun success(result: Any?) {
                            token.set(result as? String)
                            latch.countDown()
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            failure.set(IllegalStateException(errorMessage ?: errorCode))
                            latch.countDown()
                        }

                        override fun notImplemented() {
                            failure.set(IllegalStateException("Dart side is not ready"))
                            latch.countDown()
                        }
                    })
                } catch (e: Exception) {
                    failure.set(e)
                    latch.countDown()
                }
            }

            if (!latch.await(TOKEN_REPLY_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)) {
                throw java.util.concurrent.TimeoutException("tokenProvider did not answer in time")
            }
            failure.get()?.let { throw it }
            return token.get()
        }
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "====== PLUGIN ATTACHED TO ENGINE ======")
        Log.d(TAG, "Existing instance: ${instance != null}")
        Log.d(TAG, "Pending messages: ${pendingMessages.size}")
        Log.d(TAG, "=======================================")

        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        instance = this

        // Deliver any pending messages that arrived while Flutter was detached
        deliverPendingMessages()
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        Log.d(TAG, "====== PLUGIN DETACHED FROM ENGINE ======")
        Log.d(TAG, "=========================================")

        // Dart can no longer answer: the native SDK goes on with the token it has.
        if (tokenProviderOwner === this) {
            tokenProviderOwner = null
            AbrovaPush.setBlockingTokenProvider(null)
        }

        channel.setMethodCallHandler(null)
        instance = null
        Log.d(TAG, "Plugin detached from engine")
    }

    private fun invokeFlutterMethod(method: String, arguments: Any?) {
        try {
            Log.d(TAG, "====== INVOKE FLUTTER METHOD ======")
            Log.d(TAG, "Method: $method")
            Log.d(TAG, "Arguments: $arguments")
            Log.d(TAG, "===================================")

            val currentInstance = instance
            if (currentInstance != null && currentInstance::channel.isInitialized) {
                currentInstance.channel.invokeMethod(method, arguments)
                Log.d(TAG, "invokeFlutterMethod succeeded")
            } else {
                Log.w(TAG, "Channel not available! Queueing message for later delivery")
                synchronized(pendingMessages) {
                    pendingMessages.add(Pair(method, arguments))
                    Log.d(TAG, "Message queued. Total pending: ${pendingMessages.size}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "invokeFlutterMethod failed: ${e.message}")
        }
    }

    private fun deliverPendingMessages() {
        synchronized(pendingMessages) {
            if (pendingMessages.isEmpty()) {
                Log.d(TAG, "No pending messages to deliver")
                return
            }

            Log.d(TAG, "====== DELIVERING PENDING MESSAGES ======")
            Log.d(TAG, "Count: ${pendingMessages.size}")

            val messages = pendingMessages.toList()
            pendingMessages.clear()

            for ((method, arguments) in messages) {
                try {
                    Log.d(TAG, "Delivering: $method -> $arguments")
                    if (::channel.isInitialized) {
                        channel.invokeMethod(method, arguments)
                        Log.d(TAG, "Delivered successfully")
                    } else {
                        Log.e(TAG, "Channel still not initialized!")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to deliver pending message: ${e.message}")
                }
            }
            Log.d(TAG, "========================================")
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init" -> {
                val config = call.arguments as Map<*, *>
                initAbrovaPush(config)
                result.success(null)
            }
            "register" -> {
                val userId = call.argument<String>("userId")
                val metadata = call.argument<Map<String, Any>>("metadata")
                try {
                    AbrovaPush.register(userId, metadata)
                    result.success(null)
                } catch (e: Exception) {
                    android.util.Log.e(TAG, "Register failed: ${e.message}", e)
                    result.error("REGISTER_ERROR", e.message, null)
                }
            }
            "unregister" -> {
                AbrovaPush.unregister()
                result.success(null)
            }
            "subscribeTopic" -> {
                val topic = call.argument<String>("topic")
                if (topic != null) {
                    AbrovaPush.subscribeTopic(topic)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Topic cannot be null", null)
                }
            }
            "unsubscribeTopic" -> {
                val topic = call.argument<String>("topic")
                if (topic != null) {
                    AbrovaPush.unsubscribeTopic(topic)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Topic cannot be null", null)
                }
            }
            "isConnected" -> {
                result.success(AbrovaPush.isConnected())
            }
            "getDeviceId" -> {
                result.success(AbrovaPush.getDeviceId())
            }
            "getSubscriptionId" -> {
                result.success(AbrovaPush.getSubscriptionId())
            }
            "setUserId" -> {
                val userId = call.argument<String>("userId")
                if (userId != null) {
                    AbrovaPush.setUserId(userId)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "User ID cannot be null", null)
                }
            }
            "clearUserId" -> {
                AbrovaPush.clearUserId()
                result.success(null)
            }
            // Signed user tokens
            "setTokenProvider" -> {
                if (call.argument<Boolean>("enabled") == true) {
                    tokenProviderOwner = this
                    AbrovaPush.setBlockingTokenProvider(AbrovaPushBlockingTokenProvider { fetchUserTokenFromDart() })
                } else {
                    tokenProviderOwner = null
                    AbrovaPush.setBlockingTokenProvider(null)
                }
                result.success(null)
            }
            "setUserToken" -> {
                AbrovaPush.setUserToken(call.argument<String>("token"))
                result.success(null)
            }
            "getInitialMessage" -> {
                val message = AbrovaPush.getInitialMessage()
                if (message != null) {
                    AbrovaPush.clearInitialMessage()
                    result.success(message.toMap())
                } else {
                    result.success(null)
                }
            }
            "getClickedAction" -> {
                val action = AbrovaPush.getClickedAction()
                result.success(action)
            }
            "setLogLevel" -> {
                val level = call.argument<String>("level") ?: "debug"
                val logLevel = when (level.lowercase()) {
                    "none" -> AbrovaPushLogLevel.NONE
                    "error" -> AbrovaPushLogLevel.ERROR
                    "warning" -> AbrovaPushLogLevel.WARNING
                    "info" -> AbrovaPushLogLevel.INFO
                    "debug" -> AbrovaPushLogLevel.DEBUG
                    "verbose" -> AbrovaPushLogLevel.VERBOSE
                    else -> AbrovaPushLogLevel.DEBUG
                }
                AbrovaPush.setLogLevel(logLevel)
                Log.d(TAG, "Log level set to: $logLevel")
                result.success(null)
            }
            // In-App Messages
            "fetchInAppMessages" -> {
                AbrovaPush.fetchInAppMessages { messages ->
                    val messageList = messages.map { it.toMap() }
                    result.success(messageList)
                }
            }
            "triggerInAppOnAppOpen" -> {
                AbrovaPush.triggerInAppOnAppOpen()
                result.success(null)
            }
            "triggerInAppEvent" -> {
                val eventName = call.argument<String>("eventName")
                val properties = call.argument<Map<String, Any>>("properties")
                if (eventName != null) {
                    AbrovaPush.triggerInAppEvent(eventName, properties)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Event name cannot be null", null)
                }
            }
            "triggerInAppOnSessionStart" -> {
                AbrovaPush.triggerInAppOnSessionStart()
                result.success(null)
            }
            "showInAppMessage" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    AbrovaPush.showInAppMessage(messageId)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGUMENT", "Message ID cannot be null", null)
                }
            }
            "dismissInAppMessage" -> {
                AbrovaPush.dismissInAppMessage()
                result.success(null)
            }
            "recordInAppButtonClick" -> {
                val messageId = call.argument<String>("messageId")
                val buttonId = call.argument<String>("buttonId")
                if (messageId != null && buttonId != null) {
                    try {
                        AbrovaPush.getInAppMessageManager()
                            .recordImpression(messageId, InAppImpressionAction.BUTTON_CLICK, buttonId)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("RECORD_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "messageId and buttonId required", null)
                }
            }
            "recordInAppDismissed" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    try {
                        AbrovaPush.getInAppMessageManager()
                            .recordImpression(messageId, InAppImpressionAction.DISMISS)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("RECORD_FAILED", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGUMENT", "messageId required", null)
                }
            }
            // Inbox Methods
            "getInboxMessages" -> {
                val status = call.argument<String>("status")
                val category = call.argument<String>("category")
                val limit = call.argument<Int>("limit") ?: 50
                val offset = call.argument<Int>("offset") ?: 0

                val filter = InboxFilter(
                    status = status?.let {
                        when (it.lowercase()) {
                            "unread" -> InboxMessageStatus.UNREAD
                            "read" -> InboxMessageStatus.READ
                            "archived" -> InboxMessageStatus.ARCHIVED
                            else -> null
                        }
                    },
                    category = category,
                    limit = limit,
                    offset = offset
                )

                AbrovaPush.getInboxMessages(
                    filter = filter,
                    onSuccess = { response ->
                        result.success(mapOf(
                            "messages" to response.messages.map { it.toMap() },
                            "total" to response.total,
                            "unreadCount" to response.unreadCount
                        ))
                    },
                    onError = { error ->
                        result.error("INBOX_ERROR", error, null)
                    }
                )
            }
            "getInboxMessage" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    AbrovaPush.getInboxMessage(
                        messageId = messageId,
                        onSuccess = { message ->
                            result.success(message.toMap())
                        },
                        onError = { error ->
                            result.error("INBOX_ERROR", error, null)
                        }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Message ID cannot be null", null)
                }
            }
            "markInboxMessageAsRead" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    AbrovaPush.markInboxMessageAsRead(
                        messageId = messageId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("INBOX_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Message ID cannot be null", null)
                }
            }
            "archiveInboxMessage" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    AbrovaPush.archiveInboxMessage(
                        messageId = messageId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("INBOX_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Message ID cannot be null", null)
                }
            }
            "deleteInboxMessage" -> {
                val messageId = call.argument<String>("messageId")
                if (messageId != null) {
                    AbrovaPush.deleteInboxMessage(
                        messageId = messageId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("INBOX_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Message ID cannot be null", null)
                }
            }
            "markMultipleInboxMessages" -> {
                val messageIds = call.argument<List<String>>("messageIds")
                val statusStr = call.argument<String>("status")
                if (messageIds != null && statusStr != null) {
                    val status = when (statusStr.lowercase()) {
                        "unread" -> InboxMessageStatus.UNREAD
                        "read" -> InboxMessageStatus.READ
                        "archived" -> InboxMessageStatus.ARCHIVED
                        "deleted" -> InboxMessageStatus.DELETED
                        else -> InboxMessageStatus.READ
                    }
                    AbrovaPush.markMultipleInboxMessages(
                        messageIds = messageIds,
                        status = status,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("INBOX_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Message IDs and status cannot be null", null)
                }
            }
            "markAllInboxMessagesAsRead" -> {
                AbrovaPush.markAllInboxMessagesAsRead(
                    onSuccess = { result.success(null) },
                    onError = { error -> result.error("INBOX_ERROR", error, null) }
                )
            }
            "getInboxUnreadCount" -> {
                result.success(AbrovaPush.getInboxUnreadCount())
            }
            "fetchInboxUnreadCount" -> {
                AbrovaPush.fetchInboxUnreadCount(
                    onSuccess = { count -> result.success(count) },
                    onError = { error -> result.error("INBOX_ERROR", error, null) }
                )
            }
            "getCachedInboxMessages" -> {
                val messages = AbrovaPush.getCachedInboxMessages()
                result.success(messages.map { it.toMap() })
            }
            "clearInboxCache" -> {
                AbrovaPush.clearInboxCache()
                result.success(null)
            }
            // A/B Testing Methods
            "getActiveABTests" -> {
                AbrovaPush.getActiveABTests(
                    onSuccess = { tests ->
                        result.success(tests.map { it.toMap() })
                    },
                    onError = { error ->
                        result.error("ABTEST_ERROR", error, null)
                    }
                )
            }
            "getABTestVariant" -> {
                val testId = call.argument<String>("testId")
                val forceRefresh = call.argument<Boolean>("forceRefresh") ?: false
                if (testId != null) {
                    AbrovaPush.getABTestVariant(
                        testId = testId,
                        forceRefresh = forceRefresh,
                        onSuccess = { variant ->
                            result.success(variant.toMap())
                        },
                        onError = { error ->
                            result.error("ABTEST_ERROR", error, null)
                        }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID cannot be null", null)
                }
            }
            "getCachedABTestVariant" -> {
                val testId = call.argument<String>("testId")
                if (testId != null) {
                    val variant = AbrovaPush.getCachedABTestVariant(testId)
                    result.success(variant?.toMap())
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID cannot be null", null)
                }
            }
            "trackABTestImpression" -> {
                val testId = call.argument<String>("testId")
                val variantId = call.argument<String>("variantId")
                if (testId != null && variantId != null) {
                    AbrovaPush.trackABTestImpression(
                        testId = testId,
                        variantId = variantId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("ABTEST_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID and Variant ID cannot be null", null)
                }
            }
            "trackABTestOpened" -> {
                val testId = call.argument<String>("testId")
                val variantId = call.argument<String>("variantId")
                if (testId != null && variantId != null) {
                    AbrovaPush.trackABTestOpened(
                        testId = testId,
                        variantId = variantId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("ABTEST_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID and Variant ID cannot be null", null)
                }
            }
            "trackABTestClicked" -> {
                val testId = call.argument<String>("testId")
                val variantId = call.argument<String>("variantId")
                if (testId != null && variantId != null) {
                    AbrovaPush.trackABTestClicked(
                        testId = testId,
                        variantId = variantId,
                        onSuccess = { result.success(null) },
                        onError = { error -> result.error("ABTEST_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID and Variant ID cannot be null", null)
                }
            }
            "trackABTestDisplay" -> {
                val testId = call.argument<String>("testId")
                val variantId = call.argument<String>("variantId")
                if (testId != null && variantId != null) {
                    // trackDisplay sends impression then opened - replicate this behavior
                    AbrovaPush.trackABTestImpression(
                        testId = testId,
                        variantId = variantId,
                        onSuccess = {
                            AbrovaPush.trackABTestOpened(
                                testId = testId,
                                variantId = variantId,
                                onSuccess = { result.success(null) },
                                onError = { error -> result.error("ABTEST_ERROR", error, null) }
                            )
                        },
                        onError = { error -> result.error("ABTEST_ERROR", error, null) }
                    )
                } else {
                    result.error("INVALID_ARGUMENT", "Test ID and Variant ID cannot be null", null)
                }
            }
            "clearABTestCache" -> {
                AbrovaPush.clearABTestingCache()
                result.success(null)
            }
            // Log Level
            "getLogLevel" -> {
                result.success(AbrovaPush.getLogLevel().name.lowercase())
            }
            // Badge Management
            "getBadgeCount" -> {
                result.success(AbrovaPush.getBadgeCount())
            }
            "setBadgeCount" -> {
                val count = call.argument<Int>("count") ?: 0
                AbrovaPush.setBadgeCount(count)
                result.success(null)
            }
            "clearBadge" -> {
                AbrovaPush.clearBadge()
                result.success(null)
            }
            "incrementBadge" -> {
                val by = call.argument<Int>("by") ?: 1
                AbrovaPush.incrementBadge(by)
                result.success(null)
            }
            "decrementBadge" -> {
                val by = call.argument<Int>("by") ?: 1
                AbrovaPush.decrementBadge(by)
                result.success(null)
            }
            // State Getters
            "getNetworkState" -> {
                val state = AbrovaPush.getNetworkState()
                result.success(mapOf(
                    "isAvailable" to state.isAvailable,
                    "networkType" to state.networkType.name.lowercase()
                ))
            }
            "getAppState" -> {
                val state = AbrovaPush.getAppState()
                result.success(mapOf(
                    "isInForeground" to state.isInForeground,
                    "currentActivity" to state.currentActivity
                ))
            }
            // Service Notification
            "isServiceNotificationHidden" -> {
                result.success(AbrovaPush.isServiceNotificationHidden())
            }
            "openServiceNotificationSettings" -> {
                AbrovaPush.openServiceNotificationSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun initAbrovaPush(config: Map<*, *>) {
        // Build config - only apiKey is required from Flutter
        // MQTT config is fetched automatically from server
        val abrovaPushConfig = AbrovaPushConfig(
            apiKey = config["apiKey"] as String,
            notificationIcon = config["notificationIcon"] as? String,
            showServiceNotification = (config["showServiceNotification"] as? Boolean) ?: true,
            showNotificationInForeground = (config["showNotificationInForeground"] as? Boolean) ?: true,
            autoRefresh = (config["autoRefresh"] as? Boolean) ?: true,
            wrapperSdkName = config["wrapperSdkName"] as? String,
            wrapperSdkVersion = config["wrapperSdkVersion"] as? String,
            sendDiagnostics = (config["sendDiagnostics"] as? Boolean) ?: true
        )

        // Initialize native SDK
        AbrovaPush.init(context, abrovaPushConfig)

        // Set up callback to forward events to Flutter
        AbrovaPush.setCallback(object : AbrovaPushCallbackAdapter() {
            override fun onMessageReceived(message: AbrovaPushMessage) {
                Log.d(TAG, "Message received: ${message.title}")
                invokeFlutterMethod("onMessage", message.toMap())
            }

            override fun onConnectionStateChanged(connected: Boolean) {
                Log.d(TAG, "Connection state changed: $connected")
                invokeFlutterMethod("onConnectionState", connected)
            }

            override fun onRegistered(deviceId: String) {
                Log.d(TAG, "Device registered: $deviceId")
                invokeFlutterMethod("onRegistered", deviceId)
            }

            override fun onError(error: String) {
                Log.e(TAG, "Error: $error")
                invokeFlutterMethod("onError", error)
            }

            override fun onDetailedError(error: AbrovaPushError) {
                Log.e(TAG, "Detailed error: ${error.code} - ${error.message}")
                invokeFlutterMethod("onDetailedError", error.toMap())
            }

            override fun onReconnecting(attempt: Int, nextRetryMs: Long) {
                Log.d(TAG, "Reconnecting: attempt=$attempt, nextRetry=${nextRetryMs}ms")
                invokeFlutterMethod("onReconnecting", mapOf(
                    "retryAttempt" to attempt,
                    "nextRetryMs" to nextRetryMs
                ))
            }

            override fun onNetworkStateChanged(isAvailable: Boolean, networkType: String) {
                Log.d(TAG, "Network state: available=$isAvailable, type=$networkType")
                invokeFlutterMethod("onNetworkState", mapOf(
                    "isAvailable" to isAvailable,
                    "networkType" to networkType
                ))
            }

            override fun onAppStateChanged(isInForeground: Boolean) {
                Log.d(TAG, "App state: foreground=$isInForeground")
                invokeFlutterMethod("onAppState", mapOf(
                    "isInForeground" to isInForeground
                ))
            }

            override fun onAppUpdated(previousVersion: String, currentVersion: String, needsReregistration: Boolean) {
                Log.d(TAG, "App updated: $previousVersion -> $currentVersion")
                invokeFlutterMethod("onAppUpdated", mapOf(
                    "previousVersion" to previousVersion,
                    "currentVersion" to currentVersion,
                    "needsReregistration" to needsReregistration
                ))
            }

            override fun onNotificationTapped(message: AbrovaPushMessage) {
                Log.d(TAG, "Notification tapped: ${message.title}")
                invokeFlutterMethod("onNotificationTapped", message.toMap())
            }

            override fun onAuthError(error: AbrovaPushAuthError) {
                // Only meaningful while Dart is listening: not queued for later.
                if (instance == null) return
                invokeFlutterMethod("onAuthError", mapOf(
                    "code" to error.code,
                    "message" to error.message
                ))
            }

            override fun onNotificationAction(message: AbrovaPushMessage, actionId: String) {
                Log.d(TAG, "Notification action: $actionId for ${message.title}")
                invokeFlutterMethod("onNotificationAction", mapOf(
                    "actionId" to actionId,
                    "title" to message.title,
                    "body" to message.body,
                    "data" to message.data,
                    "messageId" to message.messageId
                ))
            }
        })

        // Set up in-app message callback to forward events to Flutter
        AbrovaPush.setInAppMessageCallback(object : InAppMessageCallback {
            override fun onMessageReady(message: InAppMessage) {
                Log.d(TAG, "In-app message ready: ${message.name}")
                invokeFlutterMethod("onInAppMessageReady", message.toMap())
            }

            override fun onButtonClicked(message: InAppMessage, button: InAppButton) {
                Log.d(TAG, "In-app button clicked: ${button.text}")
                invokeFlutterMethod("onInAppButtonClick", mapOf(
                    "message" to message.toMap(),
                    "button" to button.toMap()
                ))
            }

            override fun onMessageDismissed(message: InAppMessage) {
                Log.d(TAG, "In-app message dismissed: ${message.name}")
                invokeFlutterMethod("onInAppMessageDismissed", message.toMap())
            }

            override fun onError(error: String) {
                Log.e(TAG, "In-app message error: $error")
                invokeFlutterMethod("onError", error)
            }
        })

        // Set up inbox callback to forward real-time inbox updates to Flutter
        AbrovaPush.getInboxManager().setCallback(object : InboxCallback {
            override fun onMessageReceived(message: ir.abrova.push.sdk.inbox.InboxMessage) {
                Log.d(TAG, "Inbox message received: ${message.content.title}")
                invokeFlutterMethod("onInboxMessageReceived", mapOf(
                    "id" to message.id,
                    "title" to message.content.title,
                    "body" to message.content.body,
                    "imageUrl" to message.content.imageUrl,
                    "deepLink" to message.content.deepLink,
                    "category" to message.category,
                    "status" to (message.status.name.lowercase()),
                    "createdAt" to message.createdAt
                ))
            }

            override fun onMessageStatusChanged(messageId: String, status: ir.abrova.push.sdk.inbox.InboxMessageStatus) {
                Log.d(TAG, "Inbox message status changed: $messageId -> $status")
                invokeFlutterMethod("onInboxMessageStatusChanged", mapOf(
                    "messageId" to messageId,
                    "status" to status.name.lowercase()
                ))
            }
        })

        // Set up A/B testing callback to forward events to Flutter
        AbrovaPush.setABTestingCallback(object : ABTestingCallback {
            override fun onVariantAssigned(variant: ABTestVariant) {
                Log.d(TAG, "A/B test variant assigned: ${variant.variantName}")
                invokeFlutterMethod("onABTestVariantAssigned", variant.toMap())
            }

            override fun onError(testId: String?, error: String) {
                Log.e(TAG, "A/B test error for $testId: $error")
                invokeFlutterMethod("onABTestError", mapOf(
                    "testId" to (testId ?: ""),
                    "error" to error
                ))
            }
        })

        Log.d(TAG, "AbrovaPush SDK initialized with native AAR")
    }

    // Called from native to send events to Flutter
    fun invokeMethod(method: String, arguments: Any?) {
        invokeFlutterMethod(method, arguments)
    }

    // MARK: - ActivityAware implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        Log.d(TAG, "====== ATTACHED TO ACTIVITY ======")
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        isFlutterInForeground = true
        setupLifecycleObserver()
        // Set activity for in-app messages (also processes any launch-tap intent).
        AbrovaPush.setCurrentActivity(activity)
        Log.d(TAG, "==================================")
    }

    override fun onDetachedFromActivityForConfigChanges() {
        Log.d(TAG, "Detached from activity for config changes")
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
        AbrovaPush.setCurrentActivity(null)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        Log.d(TAG, "Reattached to activity for config changes")
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        AbrovaPush.setCurrentActivity(activity)
    }

    override fun onDetachedFromActivity() {
        Log.d(TAG, "====== DETACHED FROM ACTIVITY ======")
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
        AbrovaPush.setCurrentActivity(null)
        Log.d(TAG, "====================================")
    }

    override fun onNewIntent(intent: Intent): Boolean {
        Log.d(TAG, "onNewIntent received — forwarding to AbrovaPush")
        AbrovaPush.handleNotificationIntent(intent)
        return false
    }

    private fun setupLifecycleObserver() {
        if (lifecycleObserverRegistered) {
            Log.d(TAG, "Lifecycle observer already registered")
            return
        }

        lifecycleObserver = LifecycleEventObserver { _, event ->
            Log.d(TAG, "====== LIFECYCLE EVENT: ${event.name} ======")

            when (event) {
                Lifecycle.Event.ON_START -> {
                    if (!isInForeground) {
                        isInForeground = true
                        isFlutterInForeground = true
                        Log.d(TAG, "App returned to foreground - checking MQTT connection")
                        onAppForeground()
                    }
                }
                Lifecycle.Event.ON_STOP -> {
                    isInForeground = false
                    isFlutterInForeground = false
                    Log.d(TAG, "App went to background")
                    onAppBackground()
                }
                else -> {}
            }
        }

        try {
            ProcessLifecycleOwner.get().lifecycle.addObserver(lifecycleObserver!!)
            lifecycleObserverRegistered = true
            Log.d(TAG, "Lifecycle observer registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register lifecycle observer: ${e.message}")
        }
    }

    private fun onAppForeground() {
        Log.d(TAG, "Flutter foreground state: true")

        // Trigger MQTT reconnection if not connected
        if (!AbrovaPush.isConnected()) {
            Log.d(TAG, "MQTT not connected - triggering reconnect on foreground")
            AbrovaPushService.reconnectNow()
        } else {
            Log.d(TAG, "MQTT already connected")
        }

        invokeFlutterMethod("onAppState", mapOf("isInForeground" to true))
    }

    private fun onAppBackground() {
        Log.d(TAG, "Flutter foreground state: false")
        invokeFlutterMethod("onAppState", mapOf("isInForeground" to false))
    }
}
