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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Alguns plugins (ex.: file_picker) vem compilando contra android-34, mas o
// flutter_plugin_android_lifecycle exige 36+. Forca 36 em todos os modulos.
subprojects {
    val ajustar = Action<Project> {
        val android = extensions.findByName("android")
        if (android != null) {
            android.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType).invoke(android, 36)
        }
    }
    if (state.executed) ajustar.execute(this) else afterEvaluate(ajustar)
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
