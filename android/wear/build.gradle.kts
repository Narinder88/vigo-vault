import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// versionName matches the phone app. versionCode is 100000 + the phone
// versionCode so both bundles can ship on one Play listing.
val pubspecFile = rootProject.file("../pubspec.yaml")
val pubspecVersion = Regex("""(?m)^version:\s*(\S+)\+(\d+)\s*$""")
    .find(pubspecFile.readText())
    ?: error(
        "Could not read version from ${pubspecFile.path}. " +
            "Wear OS versionName must match the phone app.",
    )
val syncedVersionName = pubspecVersion.groupValues[1]
val syncedVersionCode = 100_000 + pubspecVersion.groupValues[2].toInt()

android {
    namespace = "com.singh.fitnessssnacklock.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.singh.fitnessssnacklock"
        minSdk = 30
        targetSdk = 36
        versionCode = syncedVersionCode
        versionName = syncedVersionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
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
    implementation("androidx.wear.compose:compose-navigation:$wearComposeVersion")

    implementation("com.google.android.gms:play-services-wearable:18.2.0")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.9.0")

    debugImplementation("androidx.compose.ui:ui-tooling:1.7.6")
}
