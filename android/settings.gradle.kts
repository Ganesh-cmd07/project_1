pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "project_1"

// --- THE FIX ---
// 1. Load the path from local.properties
def localPropertiesFile = new File(rootProject.projectDir, "local.properties")
def properties = new Properties()

if (localPropertiesFile.exists()) {
    localPropertiesFile.withReader('UTF-8') { reader -> properties.load(reader) }
}

def flutterSdkPath = properties.getProperty("flutter.sdk")
assert flutterSdkPath != null, "flutter.sdk not set in local.properties"

// 2. Point to the REAL SDK location
includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

include(":app")