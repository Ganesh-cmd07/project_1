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

// Include Flutter Gradle plugin from ephemeral directory
includeBuild("flutter/ephemeral/packages/flutter_tools/gradle")

include(":app")
