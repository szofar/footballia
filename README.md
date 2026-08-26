# Footballia

Two independent client apps for [footballia.eu](https://footballia.eu), a football match video archive:

- [`android/`](android/) — Android TV app, Kotlin + Jetpack Compose (Compose for TV).
- [`Footballia/`](Footballia/) — Apple app (macOS/tvOS), SwiftUI.

The two are functional ports of each other; the Swift app is the reference implementation. See the per-directory `CLAUDE.md` files for architecture notes.

## Apple app (Xcode)

Open `Footballia/Footballia.xcodeproj` in Xcode and build/run the macOS (or tvOS) target (⌘R). No package manager — dependencies are Apple frameworks only (SwiftUI, WebKit, AVKit).

## Android TV app

### Prerequisites

- Android Studio (for the bundled Java 17 JBR runtime).
- An Android TV device or emulator reachable over the network.

### Build & run

Gradle needs a Java 17 runtime. If `./gradlew` reports "Unable to locate a Java Runtime", point it at Android Studio's bundled JBR (as below).

Run from the `android/` directory:

```bash
cd ~/projects/footballia/android

# Use a non-default adb server port (optional — only if 5037 is in use)
export ANDROID_ADB_SERVER_PORT=5038

# Point Gradle at Android Studio's bundled Java 17 runtime
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

# Connect to the Android TV device over the network (replace with your device IP)
adb connect 10.0.0.179:5555
adb devices

# Build and install the debug APK
./gradlew clean
./gradlew assembleDebug
./gradlew installDebug
```

`installDebug` deploys to the connected device/emulator. Then exercise the app: login → browse → play a match.

### Other useful commands

```bash
./gradlew :app:compileDebugKotlin      # fast compile check (debug variant)
./gradlew :app:compileReleaseKotlin    # verify the release variant too (it has its own DevCredentials)
```

There is currently no test suite; the app can only be meaningfully exercised on an Android TV device/emulator.
