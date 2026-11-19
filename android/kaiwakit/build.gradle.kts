plugins {
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.jetbrainsKotlinAndroid)
    id("maven-publish")
}
android {
    namespace = "com.haishinkit.kaiwakit"
    compileSdk = 37
    defaultConfig { minSdk = 29 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    publishing.singleVariant("release") { withSourcesJar() }
}
kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
val haishinKitVersion = providers.gradleProperty("haishinKitVersion").get()

dependencies {
    api("com.github.HaishinKit.HaishinKit~kt:rtc:$haishinKitVersion")
    implementation(libs.androidx.lifecycle.runtime.ktx)
    api(libs.kotlinx.coroutines.core)
    api(libs.kotlinx.serialization.json)
    testImplementation(libs.junit)
}
afterEvaluate {
    publishing.publications.create<MavenPublication>("release") {
        from(components["release"])
        groupId = "com.haishinkit"
        artifactId = "kaiwakit"
        version = "0.1.0-SNAPSHOT"
    }
}
