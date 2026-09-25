# AList iOS (iSH host)

This is an iOS app that runs AList as a native arm64 Go runtime inside an iSH-derived host. The iSH x86 guest is not started. The app has three tabs: service status and performance, the local AList web UI, and optional background audio/location controls. A read-only view of the latest AList logs is available from the status page.

The server listens on `http://127.0.0.1:5244` by default. LAN access is an explicit, temporary toggle. The built-in administrator credentials are fixed at `admin/admin`, including after relaunch, and the AList UI/API cannot change them. Enabling LAN access exposes that known password to other devices on the network; only enable it on a network you trust.

App data and cache live in this app's own iOS sandbox. The bundle identifier is `com.bp00qd.alistish` and its App Group is `group.com.bp00qd.alistish`, separate from iSH. The web view is created when its tab is opened. Background audio and location are best-effort iOS background modes; neither keeps the service reachable after force-quit or system termination.

## Build

GitHub Actions builds an unsigned arm64 `.ipa` and `.app.zip` on macOS. Download the `AlistISH-unsigned-arm64-ipa` artifact from a successful workflow run to get the IPA. It has the standard `Payload/AlistISH.app` structure but must be signed with your Apple identity and provisioning profile before device installation. To build locally, use a Mac with Xcode, Go 1.26 and `gomobile`:

```sh
git submodule update --init --depth 1 deps/libapps deps/libarchive
go install golang.org/x/mobile/cmd/gomobile@v0.0.0-20260821190718-4776eadac327
gomobile init
./scripts/fetch-web-dist.sh
./scripts/build-ios.sh
xcodebuild -project iSH.xcodeproj -scheme iSH -configuration Release -sdk iphoneos -arch arm64 CODE_SIGNING_ALLOWED=NO build
```

See [iOS build notes](docs/ios-build.md) for signing, verification and runtime details.

## Sources and licenses

- iSH host: [ish-app/ish](https://github.com/ish-app/ish) at `83348361fe65311f6e87ad2e1cbb0ac38d123f69`, with [LICENSE.md](LICENSE.md) and [LICENSE.IOS](LICENSE.IOS) retained. iSH is GPL-3.0 with the stated additional iOS terms.
- AList source in `alist/`: [AlistGo/alist](https://github.com/AlistGo/alist) at `e1c022a9d920559078e5a906d7e1499901857006`, with [AGPL-3.0 license](alist/LICENSE) retained.
- AList web UI: [alist-org/alist-web](https://github.com/alist-org/alist-web) release `3.64.0`. The build downloads `dist.tar.gz` and verifies SHA-256 `b80550662de42a2f8a72d35bca8ed66ec9ad0c24a9a02ceec6a01bf5038cf6f4` before embedding it.

The bundled source and corresponding changes remain in this repository for redistribution under the upstream licenses.
