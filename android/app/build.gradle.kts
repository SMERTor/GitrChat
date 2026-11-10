plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// AGP 9.0 exposes the public ApplicationExtension DSL. Configure it directly
// instead of the deprecated Project.android(BaseAppModuleExtension) accessor.
extensions.configure<com.android.build.api.dsl.ApplicationExtension>("android") {
    namespace = "com.gitrchat.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gitrchat.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}

// Kotlin's compilerOptions DSL replaces the deprecated kotlinOptions block.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by CameraX 1.5.x APIs used by camera_android_camerax.
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
}
