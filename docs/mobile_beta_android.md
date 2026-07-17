# Bobux Android Mobile Beta

This is the first reduced mobile beta. It keeps the same Bobux API and WebSocket server as PC, so Android players can join the same places as Windows players.

## Included In The First Beta

- Login and account session.
- Home, Games, Friends, and Profile tabs.
- Joining published places.
- Sending and receiving friend requests through the same server API.
- Touch joystick, touch camera drag, and Jump button during gameplay.
- Mobile update check from `http://109.71.245.162/mobile/latest.json`.

## Not Included Yet

- Studio / Develop tools on mobile.
- Catalog and avatar editor on mobile.
- Silent self-update. Android does not allow an APK to silently replace itself outside Play Store or managed enterprise installs, so the beta opens the APK download URL when an update is available.

## Godot Export Setup

1. Open `C:\robloxclone\project.godot` in Godot 4.6.2 or newer.
2. Install Android export templates if Godot asks for them.
3. Open `Editor -> Editor Settings -> Export -> Android`.
4. Set the Android SDK, build-tools, platform-tools, and Java/JDK paths.
5. Open `Project -> Export`.
6. Add an Android preset.
7. Set package name to `com.bobux.game`.
8. Set version name to match `application/config/version`.
9. Set version code to match `bobux/mobile/build`.
10. Set app icon to `res://assets/branding/bobux_app_icon.png`.
11. Export a release APK to a path like:

```powershell
C:\robloxclone\dist\Bobux-Android-0.1.0-build1.apk
```

For the current beta preset, use:

- `package/signed`: `true`
- `package/show_as_launcher_app`: `true`
- `launcher_icons/main_192x192`: `res://assets/branding/bobux_android_icon_192.png`
- `launcher_icons/adaptive_foreground_432x432`: `res://assets/branding/bobux_android_icon_432.png`

If Android says the package is invalid or damaged, sign the APK manually:

```powershell
cd C:\robloxclone
.\tools\mobile\sign_android_apk.ps1 -InputApk .\dist\game\bobuxbeta.apk
```

Install the generated `*-signed.apk`.

## Build The Mobile Manifest

Run this after exporting the APK:

```powershell
cd C:\robloxclone
.\tools\mobile\build_mobile_manifest.ps1 -ApkPath .\dist\Bobux-Android-0.1.0-build1.apk -Version "0.1.0-mobile" -Build 1
```

It writes:

```text
C:\robloxclone\mobile\latest.json
```

## Upload To The VPS

Recommended one-command upload:

```powershell
cd C:\robloxclone
.\tools\mobile\deploy_mobile_release.ps1 -ApkPath .\dist\Bobux-Android-0.1.0-build1.apk -Version "0.1.0-mobile" -Build 1
```

Manual upload alternative:

```powershell
scp C:\robloxclone\dist\Bobux-Android-0.1.0-build1.apk root@109.71.245.162:/var/www/bobux/mobile/Bobux-Android-0.1.0-build1.apk
scp C:\robloxclone\mobile\latest.json root@109.71.245.162:/var/www/bobux/mobile/latest.json
ssh root@109.71.245.162 "cp /var/www/bobux/mobile/Bobux-Android-0.1.0-build1.apk /var/www/bobux/mobile/Bobux-Android.apk"
```

Make sure Nginx can serve:

```text
http://109.71.245.162/mobile/latest.json
http://109.71.245.162/mobile/Bobux-Android.apk
```

## Update Flow

Every mobile release:

1. Increase `bobux/mobile/build` in `project.godot`.
2. Increase Android version code in the export preset.
3. Export the APK.
4. Run `tools/mobile/build_mobile_manifest.ps1`.
5. Upload the APK and `latest.json`.
6. Android players will see an update prompt and the game will open the APK download URL.

## Crossplay Checklist

- PC and Android must use the same `cloud/project_url`: `http://109.71.245.162/api`.
- PC and Android must use the same WebSocket endpoint: `ws://109.71.245.162/ws`.
- The mobile beta must not create separate rooms or a separate API.
- Test with one PC account and one Android account in the same place.
