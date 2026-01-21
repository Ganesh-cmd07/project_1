// Top-level build file for RainSafe Navigator Flutter App
// Supports: flutter_map, geolocator, flutter_tts, shared_preferences, permission_handler

plugins {
    id("com.android.application") version "8.1.0" apply false
    id("com.android.library") version "8.1.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.10" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
        jcenter()
        maven {
            url = uri("https://jitpack.io")
        }
    }
}

// Configure common Android settings for all sub-projects
subprojects {
    afterEvaluate { project ->
        if (project.plugins.hasPlugin("com.android.application") || 
            project.plugins.hasPlugin("com.android.library")) {
            
            extensions.configure<com.android.build.gradle.BaseExtension> {
                // Android SDK Versions
                compileSdkVersion = 34
                ndkVersion = "26.1.10909125"
                
                // Default Config
                defaultConfig {
                    minSdk = 21
                    targetSdk = 34
                    vectorDrawables.useSupportLibrary = true
                }
                
                // Compile Options
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_1_8
                    targetCompatibility = JavaVersion.VERSION_1_8
                }
                
                // Kotlin Options
                kotlinOptions {
                    jvmTarget = "1.8"
                }
                
                // Build Features for Flutter packages
                buildFeatures {
                    viewBinding = false
                    aidl = false
                    renderScript = false
                    resValues = false
                    shaders = false
                }
            }
        }
    }
}

// Build directory configuration
rootProject.buildDir = File(rootProject.projectDir, "build")
subprojects {
    project.buildDir = File("${rootProject.buildDir}/${project.name}")
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
