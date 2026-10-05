import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningFile = file("${System.getProperty("user.home")}/.selafood/signing/store.properties")
val releaseSigning = Properties().apply {
    if (releaseSigningFile.exists()) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}
val releaseSigningRequiredKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val releaseSigningMissingKeys = releaseSigningRequiredKeys.filter {
    releaseSigning.getProperty(it).isNullOrBlank()
}
val releaseSigningStoreFile = releaseSigning.getProperty("storeFile")
    ?.trim()
    ?.takeIf(String::isNotEmpty)
    ?.let(::file)
val releaseSigningConfigured =
    releaseSigningFile.isFile &&
        releaseSigningMissingKeys.isEmpty() &&
        releaseSigningStoreFile?.isFile == true
val releaseSigningProblem = when {
    !releaseSigningFile.isFile -> "ملف إعداد التوقيع غير موجود"
    releaseSigningMissingKeys.isNotEmpty() ->
        "حقول التوقيع الناقصة: ${releaseSigningMissingKeys.joinToString()}"
    releaseSigningStoreFile?.isFile != true -> "ملف مفتاح التوقيع غير موجود"
    else -> ""
}

gradle.taskGraph.whenReady {
    val releaseTaskRequested = allTasks.any { task ->
        task.project == project &&
            task.name.contains("Release", ignoreCase = true)
    }
    if (releaseTaskRequested && !releaseSigningConfigured) {
        throw GradleException(
            "تعذر إنشاء إصدار أندرويد الإنتاجي الموقع: $releaseSigningProblem. " +
                "شغّل tools/configure_android_release_signing.ps1 ثم أعد المحاولة.",
        )
    }
}

android {
    namespace = "com.selafood.store"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.selafood.store"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Salla Merchant Dev")
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "Salla Merchant")
        }
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = requireNotNull(releaseSigningStoreFile)
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) signingConfigs.getByName("release") else null
        }
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

dependencies {
    implementation("com.google.firebase:firebase-messaging:25.0.2")
}
