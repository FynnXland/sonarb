import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung mit einem eigenen Keystore, beschrieben in ~/.handy-keys/key.properties
// (storeFile, storePassword, keyAlias, keyPassword). Die Datei liegt nie im Repository.
// Ohne Keystore schlägt der Release-Build fehl, statt still mit dem Debug-Key zu signieren.
val keyPropertiesFile =
    File(
        System.getenv("USERPROFILE") ?: System.getProperty("user.home"),
        ".handy-keys/key.properties",
    )
val keyProperties = Properties()
val hasReleaseKey =
    keyPropertiesFile.exists().also { exists ->
        if (exists) {
            FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
        }
    }

android {
    namespace = "de.fynn.handy.sonarb"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.fynn.handy.sonarb"
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // Debug läuft als eigene App neben der Release-Version.
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            if (hasReleaseKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Release ohne Keystore abbrechen (siehe oben).
gradle.taskGraph.whenReady {
    val baut = allTasks.any { it.name.contains("Release", ignoreCase = false) && it.project == project }
    if (baut && !hasReleaseKey) {
        throw GradleException(
            "Release-Keystore fehlt: ${keyPropertiesFile.absolutePath}. " +
                "Debug-Builds (flutter build apk --debug) gehen ohne Keystore.",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
