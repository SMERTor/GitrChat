GitrChat Android platform scaffold

The CameraX compile dependency is already included in android/app/build.gradle.kts:
implementation("androidx.concurrent:concurrent-futures:1.2.0")

This source archive intentionally does not contain the Gradle wrapper JAR or the Flutter SDK's Gradle plugin loader files. Those are generated/provided by Flutter tooling.
After installing Flutter, run these commands from the project root:
  flutter create . --platforms android
  flutter pub get
  flutter build apk --release

If flutter create reports that the Android platform already exists, do not delete the project; run:
  flutter create --platforms android .

Then verify that the dependency line above remains in android/app/build.gradle.kts.
The APK build has NOT been run or verified in this environment.
