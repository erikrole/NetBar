# NetBar

NetBar is a native macOS menu bar utility for answering the network questions that matter at a glance:

- whether the Mac is actually routing over Wi-Fi or Ethernet when both are connected
- the Wi-Fi network name or negotiated Ethernet link speed, with a warning when Ethernet is linked but not active
- live download and upload throughput for the active physical interface
- internet reachability, distinct from merely having a local network route
- GlobalProtect connection status
- Wi-Fi SSID, signal, noise, SNR, transmit rate, and channel
- active router and local IP address without exposing BSD interface names

The menu bar shows a native Wi-Fi, Ethernet, or generic network symbol for the route macOS is actually using, with a compact health dot beside it. Green means the internet probe succeeded, yellow means the probe is checking or a local route has not produced a successful internet response, and red means macOS has no usable network path. Live rates stay inside the popover, where separate download and upload graphs show the last 60 one-second samples and their recent peaks. Sampling continues while the popover is closed, so the recent history is ready when you open it.

## Build and run

Requires macOS 14 or later, Xcode, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project NetBar.xcodeproj -scheme NetBar -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/NetBar-*/Build/Products/Debug/NetBar.app
```

NetBar is an accessory app, so it appears only in the menu bar. Wi-Fi network names require Location Services permission on current macOS versions. NetBar requests that permission when you first open the popover. After you allow it, the stable signed app identity lets macOS retain the choice across builds.

## Background efficiency

NetBar reacts immediately to macOS network-path changes. While a route is up, it samples that interface's byte counters about once a second for a rolling 60-second history, and it pauses that timer when nothing is routed. The menu bar redraws only when the route or health changes. With the popover open, only the throughput graphs update on each sample. The heavier interface, Wi-Fi, Ethernet, and internet-health refresh stays on a coalescible 30-second timer while the popover is closed, and 10 seconds while it is open. GlobalProtect's process list check runs only when a tunnel interface is present.

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
