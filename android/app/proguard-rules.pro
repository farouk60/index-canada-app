# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }

# Stripe Android SDK
-keep class com.stripe.** { *; }
-keep class com.stripe.android.** { *; }
-keep class com.stripe.android.pushProvisioning.** { *; }
-dontwarn com.stripe.android.pushProvisioning.**

# Flutter Stripe Plugin
-keep class com.reactnativestripesdk.** { *; }
-dontwarn com.reactnativestripesdk.**

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep all classes with main methods
-keepclasseswithmembers public class * {
    public static void main(java.lang.String[]);
}

# Image picker and file picker
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn io.flutter.plugins.imagepicker.**
-dontwarn com.mr.flutter.plugin.filepicker.**

# Play Core - Nouvelles bibliothèques compatibles avec Android 14
-keep class com.google.android.play.core.** { *; }
-keep class com.google.android.play.core.appupdate.** { *; }
-keep class com.google.android.play.core.review.** { *; }
-keep class com.google.android.play.core.splitinstall.** { *; }
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
