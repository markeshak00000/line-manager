This source archive intentionally does not ship a fake Gradle wrapper.
Run `tools/build_android.ps1` from the project root on Windows after installing
Flutter and Android Studio. The script generates the official Android platform
scaffold using the Flutter SDK installed on that computer, then installs the
project's AndroidManifest template and runs code generation, analysis, tests,
and the release APK build.
