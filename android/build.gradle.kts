// Top-level build file for RainSafe Navigator Flutter App
// Supports: flutter_map, geolocator, flutter_tts, shared_preferences, permission_handler




allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://jitpack.io")
        }
    }
}

// Configure common Android settings for all sub-projects
subprojects {
    val project = this
    project.afterEvaluate {
        if (project.plugins.hasPlugin("com.android.application") || 
            project.plugins.hasPlugin("com.android.library")) {
            
            // Use dynamic dispatch to avoid compilation issues with missing accessors in root project
            val android = project.extensions.getByName("android")
            
            if (android is com.android.build.gradle.BaseExtension) {
                android.apply {
                    compileSdkVersion(35)
                    
                    defaultConfig {
                        minSdk = 24
                        targetSdk = 35
                        try {
                            // Safe access for vectorDrawables
                            val vectorDrawables = this.javaClass.getMethod("getVectorDrawables").invoke(this)
                            vectorDrawables.javaClass.getMethod("setUseSupportLibrary", Boolean::class.javaPrimitiveType).invoke(vectorDrawables, true)
                        } catch (e: Exception) {
                            // Ignore if not present
                        }
                    }
                    
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            }
            
            // Configure build features safely
            try {
                val android = project.extensions.getByName("android")
                val buildFeatures = android.javaClass.getMethod("getBuildFeatures").invoke(android)
                buildFeatures.javaClass.getMethod("setBuildConfig", Boolean::class.javaPrimitiveType).invoke(buildFeatures, true)
            } catch (e: Exception) {
                 // Ignore
            }

            // Configure Kotlin JVM toolchain
            project.extensions.findByType(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java)?.apply {
                jvmToolchain(17)
            }
            
            project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                kotlinOptions {
                    jvmTarget = "17"
                }
            }
        }
    }
}

// Build directory configuration
rootProject.layout.buildDirectory.value(rootProject.layout.projectDirectory.dir("../build"))
subprojects {
    project.layout.buildDirectory.value(rootProject.layout.buildDirectory.dir(project.name))
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Clean task
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
