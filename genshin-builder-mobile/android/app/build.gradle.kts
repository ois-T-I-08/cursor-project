plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import org.gradle.api.GradleException

val keystorePropertiesFile = rootProject.file("key.properties")

android {
    namespace = "io.github.oisti08.genshinbuilder"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications scheduled notifications (JDK APIs on older Android)
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.oisti08.genshinbuilder"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        // Credentials are applied only when a release assemble/bundle task runs.
        create("release")
    }

    buildTypes {
        release {
            // No debug signing fallback — release requires a configured upload keystore.
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

fun isAndroidReleaseSigningTask(taskName: String): Boolean {
    if (!taskName.contains("Release")) return false
    if (taskName.contains("UnitTest")) return false
    return taskName.startsWith("assemble") ||
        taskName.startsWith("bundle") ||
        taskName.startsWith("sign") ||
        taskName.contains("bundleRelease") ||
        taskName.contains("assembleRelease")
}

fun requireReleaseSigningProperty(
    props: Properties,
    key: String,
): String {
    val value = props.getProperty(key)?.trim().orEmpty()
    if (value.isEmpty()) {
        throw GradleException(
            "Release signing requires non-empty '$key' in android/key.properties.",
        )
    }
    return value
}

gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { isAndroidReleaseSigningTask(it.name) }
    if (!needsReleaseSigning) return@whenReady

    if (!keystorePropertiesFile.isFile) {
        throw GradleException(
            "Release signing requires android/key.properties " +
                "(see android/key.properties.example). Debug builds do not need it.",
        )
    }

    val props = Properties()
    keystorePropertiesFile.inputStream().use { props.load(it) }

    val storePassword = requireReleaseSigningProperty(props, "storePassword")
    val keyPassword = requireReleaseSigningProperty(props, "keyPassword")
    val keyAlias = requireReleaseSigningProperty(props, "keyAlias")
    val storeFilePath = requireReleaseSigningProperty(props, "storeFile")

    val store = rootProject.file(storeFilePath)
    if (!store.isFile) {
        throw GradleException(
            "Release signing keystore file not found at the path given by storeFile " +
                "in android/key.properties.",
        )
    }

    android.signingConfigs.getByName("release").apply {
        this.storeFile = store
        this.storePassword = storePassword
        this.keyAlias = keyAlias
        this.keyPassword = keyPassword
    }
}
