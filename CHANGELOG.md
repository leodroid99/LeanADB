# Changelog

## 1.0.0

- Add a Windows drag-and-drop launcher for APK installation and general file transfer, including mixed drops and multiple devices.
- Send multiple selected files in one session with per-file results and collision-resistant device filenames.
- Install or update Platform-Tools from a local Google ZIP after archive safety checks, Google signature verification, and downgrade protection.
- Record device screens on Android 4.4+ for a chosen duration up to 180 seconds, then retrieve the MP4.
- Preserve the selected output folder across Platform-Tools updates and keep offline update availability explicitly unknown.
- Add drag-and-drop, offline ZIP, archive traversal, and portable file-preservation tests.

## 0.9.0-beta

- Add a read-only connection diagnosis covering ADB/Fastboot visibility, authorization, offline devices, USB backend, and PATH conflicts.
- Add paged browsing of shared device folders, navigation into subfolders, and safe file/folder receiving.
- Add opt-in bug report capture with a privacy warning.
- Add a persistent file save location choice for screenshots, received files, logs, bug reports, and terminal startup.
- Save portable-install files in a sibling folder so uninstall does not remove them.
- Use collision-resistant names for saved screenshots, logs, and received directories.

## 0.8.0-beta

- Offer a portable installation beside the extracted installer, useful on an external drive without changing PATH or the Start Menu.
- Always show the installation-location chooser in interactive installs, including when another installation was found.
- Clearly distinguish unconfigured LeanADB app updates from working Google Platform-Tools updates.
- Correct the installation-completion summary for portable installs.

## 0.7.0-beta

- Add device details with Android version, API level, model, and CPU architecture.
- Stop split-APK installation on Android versions below API 21.
- Add USB-first Wi-Fi setup for Android 10 and older and a return-to-USB action.
- Add a switch for Google's Windows legacy USB backend when an older device is not detected.
- Add Fastboot device selection and confirmed reboot to Android.
- Fall back to shell screenshot plus pull when direct screenshot capture fails.

## 0.6.0-alpha

- Follow the Windows display language in automatic mode and add a persistent English/Korean language choice.
- Add guided ADB sideload and system/bootloader reboot actions with confirmation.
- Fix the multi-device picker referencing undefined variables.
- Verify uninstall completion, retry transient removal failures, and record failures from deferred cleanup.
- Show whether LeanADB script updates are configured in status output.

## 0.5.0-alpha

- Open the easy menu immediately while update metadata is checked in the background.
- Add failed-check backoff and a cross-process update mutex.
- Record the LeanADB version, SDK license URL, and acceptance time in installation state.
- Register LeanADB in the current user's Windows installed-app list.
- Notify Windows after PATH changes and diagnose competing ADB installations.
- Prefer LocalAppData while retaining Downloads, Desktop, and custom-folder choices.
- Reuse a known existing installation and use the real redirected Downloads folder.
- Add device models and localized connection states, split APK installation, collision-free transfer, file receiving, screenshots, logcat export, wireless debugging, and USB-driver help.
- Add transactional LeanADB self-updates with HTTPS manifests, per-file hashes, rollback, optional Authenticode signing, and signer continuity.
- Add confirmation before interactive uninstall and restrict Start Menu cleanup to LeanADB-owned shortcuts.
- Add Windows PowerShell and PowerShell 7 CI coverage.

## 0.4.0-alpha

- Add the localized easy menu, multi-device selection, APK installation, and file transfer.

## 0.3.0-alpha

- Add localized installation, selectable install locations, validated Google downloads, PATH integration, launchers, update checks, and safe uninstall.
