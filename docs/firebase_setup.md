# Firebase App Distribution setup

The `firebase-distribute` workflow (`.github/workflows/firebase-distribute.yml`)
builds a signed release APK and distributes it to testers via Firebase App
Distribution. It is triggered manually from the GitHub Actions UI.

## Human setup checklist

- [ ] **Create a Firebase project** at https://console.firebase.google.com
- [ ] **Add an Android app** with package name `com.enlorik.grepink`
- [ ] **Skip** Google Services JSON — this workflow does not use Analytics or
  Crashlytics, so `google-services.json` is not required
- [ ] **Enable App Distribution** in the Firebase console (Engage → App Distribution)
- [ ] **Add testers or a tester group** in the console
- [ ] **Generate a CI token**: run `firebase login:ci` locally and copy the token
- [ ] **Add GitHub secrets**:

| Secret name        | Where to find it                                           |
|--------------------|-------------------------------------------------------------|
| `FIREBASE_TOKEN`          | Output of `firebase login:ci`                                  |
| `FIREBASE_APP_ID`         | Firebase console → Project settings → Your apps → App ID      |
| `FIREBASE_TESTER_GROUPS`  | Comma-separated group aliases (optional; omit to skip groups)  |

  Also ensure the four signing secrets from `docs/android_signing.md` are set.

## Running a distribution

1. Go to the repository on GitHub → **Actions** → **Firebase App Distribution**
2. Click **Run workflow**
3. Optionally fill in release notes for testers
4. Click the green **Run workflow** button

The workflow will:
1. Run `flutter analyze` and `flutter test`
2. Build a signed release APK (versionCode = GitHub run number)
3. Upload the APK as a GitHub artifact (retained 30 days)
4. Push the APK to Firebase App Distribution

## Installing on a Samsung tablet

1. Open the Firebase console or the Firebase App Tester app on the device
2. Download and install the APK
3. If you have an existing installation, install directly over it — data is preserved
   because both builds use the same signing key and package ID

## Immediate backup while testing

Before installing a new build, export your notes: **Settings → Export notes**.
Save the JSON file to Google Drive or Downloads. This is the fastest recovery
path if anything goes wrong.
