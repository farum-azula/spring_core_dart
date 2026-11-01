// Only used when this folder is opened as a Gradle project of its own (an
// editor's Java/Gradle server, `gradle build` here): it tells Gradle where
// the Android Gradle plugin of build.gradle.kts comes from. In a Flutter app
// the plugin is included in the app's build, which reads the app's settings
// and not this file; the versions are the example app's
// (example/flutter_guide/android/settings.gradle.kts).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.library") version "9.1.0"
    }
}

rootProject.name = "spring_boot_starter_flutter_security"
