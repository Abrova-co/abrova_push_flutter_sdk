# Keep AbrovaPush classes and fields for JSON serialization
-keep class ir.abrova.push.flutter.** { *; }
-keepclassmembers class ir.abrova.push.flutter.** { *; }

# Keep native Abrova Push SDK classes (compiled from source into this plugin)
-keep class ir.abrova.push.sdk.** { *; }
-keepclassmembers class ir.abrova.push.sdk.** { *; }

# Keep PN Protocol classes
-keep class ir.abrova.protocol.** { *; }

# Keep Gson and its reflection-based serialization
-keepattributes *Annotation*
-keepattributes Signature
-keep class com.google.gson.** { *; }

# Keep all model classes with @SerializedName
-keep class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep MQTT classes (Paho uses reflection for SSL and callbacks)
-keep class org.eclipse.paho.** { *; }
-keepclassmembers class org.eclipse.paho.** { *; }
-dontwarn org.eclipse.paho.**

# Keep OkHttp
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
