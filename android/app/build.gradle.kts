import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ca.indexcanada.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "ca.indexcanada.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val releaseSigningPropertiesFile = rootProject.file("key.properties")
    val releaseSigningProperties = Properties()
    var releaseSigningLoadError: String? = null

    if (releaseSigningPropertiesFile.isFile) {
        try {
            releaseSigningPropertiesFile.inputStream().use {
                releaseSigningProperties.load(it)
            }
        } catch (error: Exception) {
            releaseSigningLoadError = error.message ?: error.javaClass.simpleName
        }
    }

    val requiredReleaseSigningProperties = listOf(
        "keyAlias",
        "keyPassword",
        "storeFile",
        "storePassword",
    )
    val missingReleaseSigningProperties = requiredReleaseSigningProperties.filter {
        releaseSigningProperties.getProperty(it).isNullOrBlank()
    }
    val releaseKeystoreFile = releaseSigningProperties
        .getProperty("storeFile")
        ?.takeIf { it.isNotBlank() }
        ?.let { file(it) }
    val releaseSigningIssue = when {
        !releaseSigningPropertiesFile.isFile ->
            "android/key.properties est absent."
        releaseSigningLoadError != null ->
            "android/key.properties est illisible : $releaseSigningLoadError"
        missingReleaseSigningProperties.isNotEmpty() ->
            "Propriétés manquantes dans android/key.properties : " +
                missingReleaseSigningProperties.joinToString(", ")
        releaseKeystoreFile == null || !releaseKeystoreFile.isFile ->
            "Le fichier de signature Android déclaré par storeFile est introuvable."
        else -> null
    }
    val allowUnsignedRelease = providers
        .gradleProperty("indexCanada.allowUnsignedRelease")
        .map { it.equals("true", ignoreCase = true) }
        .getOrElse(false)

    signingConfigs {
        if (releaseSigningIssue == null) {
            create("release") {
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
                storeFile = requireNotNull(releaseKeystoreFile)
                storePassword = releaseSigningProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningIssue == null) {
                signingConfig = signingConfigs.getByName("release")
            }
            // Enables code shrinking, obfuscation, and optimization for only
            // your project's release build type.
            isMinifyEnabled = true
            // Enables resource shrinking, which is performed by the
            // Android Gradle plugin.
            isShrinkResources = true
            // Includes the default ProGuard rules files that are packaged with
            // the Android Gradle plugin. To learn more, go to the section about
            // R8 configuration files.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Export native symbol tables for Play Console (reduces crash obfuscation)
            // Possible values: "NONE", "SYMBOL_TABLE", "FULL". SYMBOL_TABLE is a good balance.
            /*
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
            */
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isDebuggable = true
        }
    }

    val validateReleaseSigning = tasks.register("validateReleaseSigning") {
        group = "verification"
        description = "Valide la signature Android avant une compilation release."

        doLast {
            if (releaseSigningIssue != null && !allowUnsignedRelease) {
                throw GradleException(
                    "$releaseSigningIssue Ajoutez une configuration de signature valide " +
                        "ou utilisez explicitement " +
                        "-PindexCanada.allowUnsignedRelease=true pour une vérification CI non distribuable.",
                )
            }

            if (releaseSigningIssue != null) {
                logger.lifecycle(
                    "Compilation release non signée autorisée explicitement : $releaseSigningIssue",
                )
            }
        }
    }

    tasks.matching { it.name == "preReleaseBuild" }.configureEach {
        dependsOn(validateReleaseSigning)
    }
}

flutter {
    source = "../.."
}
