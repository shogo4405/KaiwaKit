plugins {
    id("org.jlleitschuh.gradle.ktlint") version "12.3.0"
    alias(libs.plugins.androidApplication) apply false
    alias(libs.plugins.androidLibrary) apply false
    alias(libs.plugins.jetbrainsKotlinAndroid) apply false
    alias(libs.plugins.compose.compiler) apply false
    alias(libs.plugins.jetbrainsDokka) apply false
}

subprojects { apply(plugin = "org.jlleitschuh.gradle.ktlint") }
