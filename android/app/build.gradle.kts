import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ca.indexcanada.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    // Lire key.properties si fourni pour config signer release
    val keystorePropertiesFile = rootProject.file("key.properties")
    // Simple Kotlin parser for key.properties to avoid java.* references in Kotlin script
    val keystoreProperties = mutableMapOf<String, String>()
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.readLines().forEach { line ->
            val l = line.trim()
            if (l.isNotEmpty() && !l.startsWith("#") && l.contains("=")) {
                val (k, v) = l.split("=", limit = 2)
                keystoreProperties[k.trim()] = v.trim()
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Application ID unique pour Index Canada
        // NOTE: Make sure your Firebase project contains an Android app with this package name
        // and that you place the corresponding google-services.json at android/app/google-services.json
        applicationId = "ca.indexcanada.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 21 // Stripe requires minimum API 21
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Configuration pour la production
            // Si key.properties présent, utiliser la signature release
            if (keystorePropertiesFile.exists()) {
                // Avoid shadowing 'storeFile' property by using a different local name
                val storeFilePath = keystoreProperties["storeFile"] ?: "upload-keystore.jks"
                val resolvedStoreFile = file(storeFilePath)
                signingConfigs.create("releaseConfig") {
                    storeFile = resolvedStoreFile
                    storePassword = keystoreProperties["storePassword"]
                    keyAlias = keystoreProperties["keyAlias"]
                    keyPassword = keystoreProperties["keyPassword"]
                }
                signingConfig = signingConfigs.getByName("releaseConfig")
            } else {
                // Fallback: debug signing (local dev only)
                signingConfig = signingConfigs.getByName("debug")
            }
            
            // Activer la minification/R8 et le shrink resources pour la release optimisée
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Export native symbol tables for Play Console (reduces crash obfuscation)
            // Possible values: "NONE", "SYMBOL_TABLE", "FULL". SYMBOL_TABLE is a good balance.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
        }
    }

    // Dependencies required by Android module
    dependencies {
        // Firebase BoM - manage Firebase library versions
        implementation(platform("com.google.firebase:firebase-bom:33.1.1"))
        // Firebase Analytics (no version when using BoM)
        implementation("com.google.firebase:firebase-analytics")
        
        // Nouvelles bibliothèques Play Core compatibles avec targetSdkVersion 34
        implementation("com.google.android.play:app-update:2.1.0")
        implementation("com.google.android.play:app-update-ktx:2.1.0")
        implementation("com.google.android.play:review:2.0.1")
        implementation("com.google.android.play:review-ktx:2.0.1")
    }
}

flutter {
    source = "../.."
}
