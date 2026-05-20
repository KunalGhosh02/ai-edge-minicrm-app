import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile

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

// Several Flutter plugins still apply the Kotlin Gradle Plugin themselves
// (flutter_foreground_task, flutter_litert_lm, objectbox_flutter_libs,
// shared_preferences_android, tflite_flutter, ...) and they don't all agree
// on a JVM target:
//   - flutter_foreground_task / objectbox_flutter_libs: Java 11, Kotlin 11
//   - flutter_litert_lm / shared_preferences_android:  Java 17, Kotlin 17
//   - tflite_flutter:                                  Java 11, Kotlin <KGP default>
// Naively forcing every Kotlin task to JVM 17 (what we tried before) breaks
// the Java-11 plugins with:
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (17).
//
// Instead, for every subproject we pin the Kotlin task's jvmTarget to that
// same subproject's Java targetCompatibility, so each plugin stays
// internally consistent regardless of what value it picked. The app module
// owns its own JVM 17 settings via `android/app/build.gradle.kts`.
//
// We must use `configureEach` rather than `afterEvaluate` because the
// `subprojects { project.evaluationDependsOn(":app") }` block above means
// subprojects can already be evaluated by the time additional `subprojects`
// blocks run. `configureEach` is lazy and registers actions that fire when
// the tasks are realized, which is always late enough to read the Java
// task's finalised `targetCompatibility`.
val jvmTargetByName: Map<String, JvmTarget> =
    mapOf(
        "1.8" to JvmTarget.JVM_1_8,
        "8" to JvmTarget.JVM_1_8,
        "11" to JvmTarget.JVM_11,
        "17" to JvmTarget.JVM_17,
        "21" to JvmTarget.JVM_21,
    )

subprojects {
    tasks.withType<KotlinJvmCompile>().configureEach {
        val javaTargetProvider =
            project.provider {
                project.tasks
                    .withType<JavaCompile>()
                    .map { it.targetCompatibility }
                    .firstOrNull { it.isNotEmpty() }
            }
        compilerOptions {
            jvmTarget.set(
                javaTargetProvider.map { value ->
                    jvmTargetByName[value] ?: JvmTarget.JVM_17
                },
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
