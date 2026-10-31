allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// The Gradle plugins of the plugin projects pull libraries with
// advisories (the build machine only, nothing of them reaches the APK):
// the Flutter SDK's integration_test declares an older Android Gradle
// plugin in its own buildscript. The fixed versions replace them there
// too (settings.gradle.kts does it for the app's own plugins);
// constraints only ever raise a version.
subprojects {
    val classpath = buildscript.dependencies
    classpath.add("classpath", classpath.platform("io.netty:netty-bom:4.1.139.Final"))
    for (fixed in listOf(
        "org.bouncycastle:bcprov-jdk18on:1.86",
        "org.bouncycastle:bcpkix-jdk18on:1.86",
        "org.bouncycastle:bcutil-jdk18on:1.86",
        "com.google.guava:guava:33.7.2-jre",
        "org.bitbucket.b_c:jose4j:0.9.7",
        "org.jdom:jdom2:2.0.6.1",
        "org.apache.commons:commons-lang3:3.21.0",
        "org.apache.commons:commons-compress:1.28.0",
    )) {
        classpath.constraints.add("classpath", fixed)
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
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
