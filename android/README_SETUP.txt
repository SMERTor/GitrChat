GitrChat Android Gradle notes

The app module build.gradle.kts uses the AGP 9 ApplicationExtension DSL and
Kotlin compilerOptions DSL to avoid deprecated android/kotlinOptions accessors.
It also includes androidx.concurrent:concurrent-futures:1.2.0 for CameraX.

This archive does not include a complete generated Gradle wrapper or the full
Flutter Android toolchain. The project has not been compiled in this environment.
Use a compatible Flutter SDK, Android SDK, Gradle wrapper and plugin versions
in your build environment, then run flutter build apk --release.
