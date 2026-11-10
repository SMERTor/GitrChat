// Make CameraX's missing transitive type available to Android library plugins too.
// Adding the dependency only to :app does not put it on :camera_android_camerax's
// Java compile classpath.
subprojects {
    plugins.withId("com.android.library") {
        dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
    }
}
