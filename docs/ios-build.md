# iOS build and verification

## Build and signing

The `iSH` scheme in `iSH.xcodeproj` builds the iOS host. `scripts/build-ios.sh` produces `build/AlistCore.xcframework` from `alist/iosbridge` for `ios/arm64`; Xcode links that framework into `AlistISH.app`. Both scripts require macOS with Xcode, Go 1.26, `gomobile`, Meson, Ninja, LLVM/LLD and libarchive. The workflow installs these dependencies, downloads the pinned AList web UI, runs Go tests, builds the framework and app, and uploads an unsigned `.app.zip`.

The unsigned artifact is not an IPA and cannot be installed directly. On a Mac, open `iSH.xcodeproj`, select the `iSH` target, set a development team and a bundle ID/App Group that belong to your provisioning profile, and build for a connected arm64 iPhone or iPad. Do not change the bundle ID to `app.ish.iSH`: a separate ID preserves iSH's app container. Signing may require entitlements supported by the chosen profile.

## Runtime

The iSH guest kernel and terminal do not start. The native Go bridge initializes AList in `Library/Application Support/Alist`, uses `Library/Caches/Alist` for temporary files, and starts one HTTP listener on port 5244. It binds to loopback unless LAN access is enabled from the status page. WebDAV shares the HTTP listener. FTP, SFTP, S3 and HTTPS listeners are disabled in the app. The admin account is restored to `admin/admin` on startup; both profile and administrator update endpoints reject credential changes. The setting screen reads the last 200 lines of the AList log on demand and has no command input.

The Go runtime uses a 96 MiB soft memory limit and two Go processors. This is not a cap on the iOS app's physical memory. The performance screen reports process physical footprint, CPU use and Go heap/system statistics. The web view is instantiated only after opening its tab.

## Background behavior

The third tab independently enables silent audio playback and Core Location background updates. Location requires Always authorization; denied or restricted permission is shown in the UI. Audio interruptions and foreground return trigger a status refresh. iOS may still suspend or terminate the app, especially after force-quit, so these modes offer no uptime guarantee. Background location consumes battery and is subject to iOS policy.

## Device acceptance

On a signed arm64 device, verify all three tabs, the read-only log, `admin/admin` on first and subsequent launches, rejection of credential changes, loopback access at 5244, the LAN switch, and isolation from an installed iSH instance. Test both background modes, interruption/permission denial, and return to foreground. Use Instruments Allocations/VM Tracker to measure the foreground idle process footprint; the target is at most 150 MiB. GitHub Actions cannot establish device background behavior or the Instruments result.
