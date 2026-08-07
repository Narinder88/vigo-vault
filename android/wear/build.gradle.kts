import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Sync version with pubspec.yaml (source of truth) and Flutter local.properties.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { reader ->
        localProperties.load(reader)
    }
}

fun readFlutterVersionFromPubspec(): Pair<Int, String> {
    val pubspecFile = rootProject.file("../pubspec.yaml")
    if (!pubspecFile.exists()) {
        throw GradleException("pubspec.yaml not found at ${pubspecFile.absolutePath}")
    }
    val versionLine = pubspecFile.readLines()
        .firstOrNull { it.trimStart().startsWith("version:") }
        ?: throw GradleException("version: entry not found in pubspec.yaml")
    val versionSpec = versionLine.substringAfter("version:").trim().removeSurrounding("\"")
    val versionName = versionSpec.substringBefore("+")
    val versionCode = versionSpec.substringAfter("+", missingDelimiterValue = "1").toInt()
    return versionCode to versionName
}

val pubspecVersion = readFlutterVersionFromPubspec()
// pubspec.yaml is the source of truth so Wear always matches the Flutter app.
val flutterVersionCode = pubspecVersion.first
val flutterVersionName = pubspecVersion.second

android {
    namespace = "com.singh.fitnessssnacklock.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.singh.fitnessssnacklock"
        minSdk = 30
        targetSdk = 36
        versionCode = flutterVersionCode
        versionName = flutterVersionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    val wearComposeVersion = "1.4.0"
    val lifecycleVersion = "2.8.7"
    val activityComposeVersion = "1.9.3"

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:$activityComposeVersion")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:$lifecycleVersion")

    implementation("androidx.wear.compose:compose-material:$wearComposeVersion")
    implementation("androidx.wear.compose:compose-foundation:$wearComposeVersion")

    implementation("com.google.android.gms:play-services-wearable:18.2.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling:1.7.6")
}
