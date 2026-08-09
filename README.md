# NetBar

NetBar is a native macOS menu bar utility for answering the network questions that matter at a glance:

- whether the Mac is actually routing over Wi-Fi or Ethernet when both are connected
- the Wi-Fi network name or negotiated Ethernet link speed, with a warning when Ethernet is linked but not active
- live download and upload throughput for the active physical interface
- internet reachability, distinct from merely having a local network route
- GlobalProtect connection status
- Wi-Fi SSID, signal, noise, SNR, transmit rate, and channel
- active router and local IP address without exposing BSD interface names

The menu bar shows a fixed-width colored badge with a Wi-Fi, Ethernet, or generic network glyph for the route macOS is actually using. Green means the internet probe succeeded, yellow means a local route exists but the internet probe is not responding, and red means macOS has no usable network path. Live rates stay inside the popover, where separate download and upload graphs show the last 60 one-second samples and their recent peaks.

## Build and run

Requires macOS 14 or later, Xcode, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project NetBar.xcodeproj -scheme NetBar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/NetBar-*/Build/Products/Debug/NetBar.app
```

NetBar is an accessory app, so it appears only in the menu bar. Wi-Fi network names require Location Services permission on current macOS versions. NetBar requests that permission automatically the first time it runs. After you allow it, the stable signed app identity lets macOS retain the choice across builds.

## Background efficiency

NetBar reacts immediately to macOS network-path changes. With its popover closed, it refreshes detailed interface, Wi-Fi, Ethernet, VPN, and internet-health information every 30 seconds using a coalescible timer. One-second throughput sampling runs only while the popover is visible, then stops as soon as it closes.

## Test

```sh
xcodebuild -project NetBar.xcodeproj -scheme NetBar -destination 'platform=macOS' test
```

## Releases

NetBar is distributed directly as a signed and notarized Apple Silicon ZIP
attached to a GitHub Release. Homebrew is deferred until the release cadence is
stable.

See [docs/releasing.md](docs/releasing.md) for local and GitHub Actions release
instructions.
