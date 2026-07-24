# Android preview signing setup

Preview builds are signed with a persistent keystore so that installing a new
APK over an existing one preserves all app data. The keystore lives only in
GitHub Actions secrets — it is never committed to the repository.

## One-time setup

### 1. Generate the keystore

```sh
keytool -genkeypair \
  -v \
  -storetype PKCS12 \
  -keystore grepink-preview.jks \
  -alias grepink-preview \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass <STORE_PASSWORD> \
  -keypass <KEY_PASSWORD> \
  -dname "CN=Grepink Preview, O=enlorik, C=US"
```

Keep `grepink-preview.jks` in a safe place (password manager, offline drive).
**Never commit it to the repository.**

### 2. Base64-encode the keystore

```sh
base64 -w 0 grepink-preview.jks
```

### 3. Add GitHub Actions secrets

In the repository go to **Settings → Secrets and variables → Actions** and add:

| Secret name                          | Value                             |
|--------------------------------------|-----------------------------------|
| `ANDROID_PREVIEW_KEYSTORE_BASE64`    | Output of the base64 command above |
| `ANDROID_PREVIEW_KEY_ALIAS`          | `grepink-preview`                 |
| `ANDROID_PREVIEW_KEY_PASSWORD`       | The `<KEY_PASSWORD>` you chose    |
| `ANDROID_PREVIEW_STORE_PASSWORD`     | The `<STORE_PASSWORD>` you chose  |

### 4. Local development (optional)

Create `android/key.properties` (this file is git-ignored):

```
storeFile=/absolute/path/to/grepink-preview.jks
storePassword=<STORE_PASSWORD>
keyAlias=grepink-preview
keyPassword=<KEY_PASSWORD>
```

Without this file, local release builds will fail with a clear error.
Debug builds and `flutter test` are not affected.

## Recovery

If the keystore is lost, existing installs cannot be updated over-the-air.
Users would need to uninstall and reinstall, losing local data unless they
exported a JSON backup first. **Keep the keystore backed up.**
