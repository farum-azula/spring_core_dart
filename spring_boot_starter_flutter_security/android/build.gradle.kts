// The Android part of the plugin: the secret store and the DPoP key on the
// Android Keystore, and the login window on Custom Tabs (androidx.browser).
group = "dev.farumazula.spring_boot_starter_flutter_security"
version = "1.0-SNAPSHOT"

buildscript {
    // 2.4.20+: the build cache deserialization advisory of 2.4.0 is fixed.
    val kotlinVersion = "2.4.21"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.1.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
        // The Android and Kotlin Gradle plugins pull older versions of
        // these, with advisories (the build machine only, nothing of them
        // reaches the APK); the fixed ones replace them.
        constraints {
            classpath("org.bouncycastle:bcprov-jdk18on:1.86")
            classpath("org.bouncycastle:bcpkix-jdk18on:1.86")
            classpath("org.bouncycastle:bcutil-jdk18on:1.86")
            classpath("com.google.guava:guava:33.7.2-jre")
            classpath("org.bitbucket.b_c:jose4j:0.9.7")
            classpath("org.jdom:jdom2:2.0.6.1")
            classpath("org.apache.commons:commons-lang3:3.21.0")
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "dev.farumazula.spring_boot_starter_flutter_security"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        // The Keystore's AES keys exist from API 23.
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Custom Tabs: the login page in the user's browser, inside the app.
    implementation("androidx.browser:browser:1.8.0")
    // The unit tests of the plain JVM code (RedirectMatcher).
    testImplementation("junit:junit:4.13.2")
}
