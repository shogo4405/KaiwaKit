plugins {
    alias(libs.plugins.androidLibrary)
    alias(libs.plugins.jetbrainsKotlinAndroid)
    id("maven-publish")
    alias(libs.plugins.jetbrainsDokka)
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
        groupId = "com.github.shogo4405.KaiwaKit"
        artifactId = "kaiwakit"
        version = providers.gradleProperty("kaiwaKitVersion").orElse("0.1.0-SNAPSHOT").get()
    }
}

dokka {
    moduleName.set("KaiwaKit")
    moduleVersion.set(providers.gradleProperty("documentationVersion").orElse("development"))
    dokkaPublications.html {
        outputDirectory.set(layout.buildDirectory.dir("dokka/html"))
        failOnWarning.set(true)
    }
    dokkaSourceSets.configureEach {
        // Android variants share main sources; document release once.
        suppress.set(name != "release")
        includes.from(project.layout.projectDirectory.file("module-docs.md"))
    }
}
