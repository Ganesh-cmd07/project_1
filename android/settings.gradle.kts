pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "7.3.0" apply false
    id("org.jetbrains.kotlin.android") version "1.7.20" apply false
}

// Read local.properties
val localPropertiesFile = File(rootProject.projectDir, "local.properties")
val properties = java.util.Properties()

if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream ->
        properties.load(stream)
    }
}

// Get Flutter SDK path
val flutterSdkPath = properties.getProperty("flutter.sdk")
    ?: throw GradleException("flutter.sdk not set in local.properties")

// Include Flutter
includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

include(":app")