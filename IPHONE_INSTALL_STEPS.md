# iPhone installation steps

Project path:

```bash
/Volumes/외장 2TB/ai_diary_app
```

What is ready:

- Flutter SDK is installed at `/Volumes/외장 2TB/flutter`.
- CocoaPods is installed locally at `/Volumes/외장 2TB/ruby-gems`.
- iOS pods are installed.
- iOS build without code signing succeeds.
- App bundle ID is `com.pseudoprogramer.aiDiary`.
- App display name is `하루결`.

Tomorrow:

1. Connect the iPhone to this Mac with a cable.
2. Unlock the iPhone and tap Trust This Computer if asked.
3. Open the Xcode workspace:

```bash
/Volumes/외장 2TB/ai_diary_app/scripts/open_xcode_workspace.sh
```

4. In Xcode, select `Runner` in the left sidebar.
5. Go to `Signing & Capabilities`.
6. Select your Apple Team for the `Runner` target.
7. If Xcode asks, let it manage signing automatically.
8. Select your iPhone as the run destination.
9. Press the Run button.

Optional terminal run:

```bash
cd "/Volumes/외장 2TB/ai_diary_app"
. ./scripts/flutter_env.sh
flutter devices
flutter run -d ios
```

If the iPhone does not appear, keep it unlocked, reconnect the cable, and open Xcode once.
