// Root Gradle build for Android project.
// This script includes a small SDK auto-detection helper so Gradle can
// populate `local.properties` with `sdk.dir` when an environment variable
// is set (ANDROID_SDK_ROOT or ANDROID_HOME). It also preserves existing
// properties.

// Auto-detect Android SDK and ensure `sdk.dir` is present in local.properties when possible.
// This helps avoid the common "SDK location not found" error during Gradle configuration.
run {
    val localPropsFile = rootProject.file("local.properties")
    val props = java.util.Properties()
    if (localPropsFile.exists()) {
        props.load(localPropsFile.inputStream())
    }

    // Check current properties and environment variables
    val sdkDirFromProps: String? = props.getProperty("sdk.dir")
    val sdkFromEnv = System.getenv("ANDROID_SDK_ROOT") ?: System.getenv("ANDROID_HOME")

    if (sdkDirFromProps.isNullOrBlank()) {
        if (!sdkFromEnv.isNullOrBlank()) {
            props.setProperty("sdk.dir", sdkFromEnv)
            localPropsFile.outputStream().use { props.store(it, "Updated by build script to point to Android SDK") }
            println("[build.gradle.kts] Set sdk.dir in local.properties to: $sdkFromEnv")
        } else {
            logger.warn("Android SDK not found. Please set sdk.dir in android/local.properties or ANDROID_HOME/ANDROID_SDK_ROOT environment variable.")
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
