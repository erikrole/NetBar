# Friendly network identity, router context, and trustworthy throughput graphs

Written against: unavailable; `/Users/erole/GitHub/NetBar` is not a Git repository

## Design language

- Audited surface: the NetBar macOS menu-bar status item and its single popover.
- Design sources: the user-supplied screenshot from August 9, 2026; the user's explicit corrections in the same turn; the current native SwiftUI/AppKit implementation in `NetBar/NetBarView.swift` and `NetBar/NetBarApp.swift`.
- Documented decisions: native macOS controls, a restrained material surface, green/yellow/red connectivity state, live throughput, active-route truth, GlobalProtect status, and detailed Wi-Fi radio information.
- Governing owners and consumers: `AppDelegate` owns the status item and popover; `NetworkMonitor` owns the live reading; `SystemNetworkReader` owns system facts; `NetBarView` renders the only popover.
- Explicit exceptions: none documented.

## Findings

| # | Problem | Evidence | Proposed change | Scope | Confidence |
| --- | --- | --- | --- | --- | --- |
| 1 | The most prominent text says `Online`, while the friendly network identity is secondary and the BSD name `en0` is shown twice. | The supplied screenshot shows `Online`, `Wi-Fi · en0`, and a separate `Interface en0` row. The user explicitly requested the Wi-Fi name or Ethernet speed in the title and removal of `en0`. `NetworkReading.routeDetail`, `NetBarView.header`, and `NetBarView.connection` directly produce those strings. | Make friendly connection identity the title, move health to a short subtitle, and remove BSD interface names from every visible row. | Status header and Connection section. | High |
| 2 | The popover does not show the router used by the active route even though the system state provides it. | The live `State:/Network/Global/IPv4` dictionary reports `Router : 192.168.1.1`; the current reader already opens this exact dictionary but extracts only `PrimaryInterface`. The user explicitly requested router information. | Read the active default gateway from the same dynamic-store snapshot and show it as `Router`; use `Unavailable` only when the active state omits it. | System reader, reading model, monitor, Connection section. | High |
| 3 | Two narrow, independently normalized sparklines have no time range, scale, baseline, or peak context. | The screenshot shows isolated spikes with no indication of 60 seconds or each chart's changing scale. `Sparkline` scales each history to its own raw maximum and stretches the available samples across its entire width. The user explicitly requested graph polish. | Replace the two narrow cards with one full-width throughput panel containing two labeled small-multiple lanes, explicit 60-second context, a zero baseline, peak labels, trailing sample placement, and subtle area fills. | Throughput section and its private graph components. | High |

## Improve first

Make friendly connection identity the single owner of the header. It removes the most visible jargon and duplication while making the primary glance answer immediate.

## Evidence chain

- Surface: the rendered NetBar popover in the attached `Screenshot 2026-08-09 at 9.27.10 AM.png`.
- Problem: the header emphasizes generic health, repeats route details, and gives narrow unlabeled charts more space than network identity and router context.
- Design evidence: the user's direct corrections; the existing material, typography, color, and section primitives in `NetBar/NetBarView.swift`; the existing `SCDynamicStore` route authority in `NetBar/SystemNetworkReader.swift`.
- Owner: `NetBar/Models.swift`, `NetBar/SystemNetworkReader.swift`, `NetBar/NetworkMonitor.swift`, `NetBar/NetBarApp.swift`, and `NetBar/NetBarView.swift`.
- Scope and affected surfaces: one macOS status item, one popover, unit tests, and the popover UI test.
- Uncertainty: macOS exposes the default gateway address but not a friendly UniFi device name. CoreWLAN can expose the access point BSSID with permission, but a friendly AP/router name would require reverse DNS or a separate UniFi integration. This plan intentionally displays the authoritative gateway IP.

## Design decision

Treat connectivity state, friendly network identity, transport facts, and traffic history as separate concepts:

- The menu bar is a state-only colored dot.
- The popover title is the network identity: the active SSID for Wi-Fi, `Ethernet · <negotiated speed>` for Ethernet, `Network` for another usable route, and `No connection` offline.
- The subtitle carries health and transport without interface names: `Online · Wi-Fi`, `Checking · Wi-Fi`, or `No internet response · Wi-Fi`. Ethernet omits redundant transport wording when the title already says Ethernet.
- The Connection section shows `Router` and `Local address`, not route and interface implementation details.
- Throughput remains prominent but uses one coherent, labeled 60-second visualization.

## Reuse

- Reuse `InternetState`, `TransportKind`, `InfoSection`, `InfoRow`, `ByteRateFormatter`, the existing one-second histories, system colors, rounded continuous cards, and `.regularMaterial`.
- Reuse the existing `State:/Network/Global/IPv4` dynamic-store read as the authority for both primary interface and gateway.
- Exemplar: the current header's native typography and state dot in `NetBar/NetBarView.swift`.
- Replace the private `RateCard` and `Sparkline` only. No shared public chart primitive is warranted for one popover.

## Changes

1. `NetBar/Models.swift`
   - Change: add `routerAddress: String?` and `ethernetLinkSpeedBitsPerSecond: UInt64?` to `NetworkReading`.
   - Change: replace `routeDetail` with deterministic `friendlyTitle` and `statusSubtitle` computations. For active Wi-Fi, prefer a nonempty SSID and fall back to `Wi-Fi`; for Ethernet, append a formatted negotiated speed only when available; never expose `interfaceName` in user-facing copy.
   - Change: add a link-speed formatter that emits `100 Mbps`, `1 Gbps`, `2.5 Gbps`, `5 Gbps`, or `10 Gbps` without false precision.
   - Preserve: the raw BSD interface name internally for counter, address, route, and VPN work.
   - Verify: fixtures cover Wi-Fi with/without SSID, Ethernet with/without negotiated speed, degraded state, and offline state.

2. `NetBar/SystemNetworkReader.swift`
   - Change: return primary interface and `Router` from one `State:/Network/Global/IPv4` read so both facts describe the same system snapshot.
   - Change: add an Ethernet-only negotiated-link-speed reader using the native `SIOCGIFMEDIA`/`ifmediareq` interface query. Map known Ethernet media subtypes to their bit rates and return `nil` for unknown, inactive, or non-Ethernet media. Do not parse shell command output or spawn a polling process.
   - Preserve: CoreWLAN as the Wi-Fi radio authority and 64-bit route counters as the traffic authority.
   - Verify: the current live route returns router `192.168.1.1`; Wi-Fi does not invent an Ethernet speed; an Ethernet fixture formats each supported speed.

3. `NetBar/NetworkMonitor.swift`
   - Change: install the router address and Ethernet link speed into each reading. Read Ethernet speed only when the primary interface resolves as Ethernet.
   - Preserve: one-second throughput sampling, 10-second internet probes, 60 samples, active physical interface selection, and GlobalProtect detection.
   - Verify: changing the primary interface resets rate deltas and updates title/router facts without a stale frame.

4. `NetBar/NetBarApp.swift`
   - Change: make the status item square and render only the colored `●`. Observe connectivity state for menu-bar rendering; do not observe or render throughput values there.
   - Change: keep the accessibility label useful, but phrase it with the friendly title and health state and omit BSD interface names.
   - Preserve: click behavior, transient popover, autosave name, colored state mapping, and tooltip.
   - Verify: menu-bar width stays fixed while traffic changes and XCUITest sees no arrows or rate text in the status-item title.

5. `NetBar/NetBarView.swift`
   - Change: render `friendlyTitle` as the headline and `statusSubtitle` as secondary text. Remove `en0` and all other BSD names from the visible header, Connection section, and VPN tunnel detail.
   - Change: rename the Connection rows to `Router` and `Local address`. Render the authoritative gateway IP or `Unavailable`. Do not call it an access point or infer a hardware name.
   - Change: when Wi-Fi is the active route, omit the duplicate `Network` row from the Wi-Fi section. When Wi-Fi is connected but inactive, keep the SSID and label its usage `Connected, not active`.
   - Change: replace the side-by-side `RateCard`s with one full-width `ThroughputCard`. Put current download and upload values in a compact header, then draw two stacked 38-point lanes. Each lane must use its own labeled scale, show `Peak <rate>`, include a faint zero baseline, fill below the line with a low-opacity vertical gradient, and label the range `Last 60 seconds`.
   - Change: place fewer than 60 samples in their true trailing positions instead of stretching early samples across the full chart. Scale each lane to `max(recent maximum × 1.1, 1)` so all samples remain visible. Do not animate the one-second path changes.
   - Preserve: blue download, purple upload, monospaced rate digits, material surface, location-permission action, refresh action, launch-at-login control, selection for addresses, and native system typography.
   - Verify: the default 360-point popover fits the router, local IP, VPN, active Wi-Fi stats, and throughput context without truncating the graph labels; scrolling remains available for permission or inactive-Wi-Fi details.

6. `NetBarTests/NetBarTests.swift` and `NetBarUITests/NetBarUITests.swift`
   - Change: add unit coverage for friendly titles/subtitles, no-SSID fallback, Ethernet speed formatting, router availability, and chart sample positioning/scale helpers.
   - Change: update the UI test to assert the friendly header, `Router`, `Local address`, and `Last 60 seconds`; assert the status item title is dot-only and no visible `en0` exists.
   - Preserve: the existing connectivity-state, throughput-delta, byte-formatting, Wi-Fi-quality, real status-item, and screenshot coverage.
   - Verify: all unit and macOS UI tests pass with a retained popover screenshot.

7. `README.md`
   - Change: document the dot-only menu bar, friendly network title, Ethernet negotiated speed, router address, and revised graph semantics.
   - Preserve: current build/run/test commands and the explicit Wi-Fi location-permission explanation.
   - Verify: documentation matches the rendered app and does not promise a friendly router/AP name.

## Scope

- Inherit: the only NetBar status item, popover, accessibility summary, tests, and README.
- Verify: Wi-Fi online, Wi-Fi with SSID permission unavailable, Ethernet online with known/unknown speed, local route with failed internet probe, offline, and GlobalProtect connected/disconnected.
- Exclude: UniFi API integration, AP-friendly names, BSSID display, packet capture, per-process traffic, router configuration, DNS changes, VPN changes, public-IP services, persistent history, notifications, and launch-at-login behavior changes.

## Validation

- Product: launch NetBar and confirm the current Mac shows `Role`, `Online · Wi-Fi`, router `192.168.1.1`, local address `192.168.1.206`, no visible `en0`, and a dot-only menu-bar item.
- Interface: capture the popover after at least 60 seconds of traffic, immediately after launch with fewer than 60 samples, with Location Services denied, and with GlobalProtect both disconnected and connected when naturally available.
- System: compare the displayed router with `State:/Network/Global/IPv4 Router`, the local address with the primary interface's IPv4 state, and Ethernet speed with the native media query. Do not infer router model or AP name.
- Repository: `xcodegen generate && xcodebuild -project NetBar.xcodeproj -scheme NetBar -destination 'platform=macOS' test` → build succeeds and every unit/UI test passes.
- Repository: `rg -n 'en0|downloadBytesPerSecond.*compact|uploadBytesPerSecond.*compact' NetBar/NetBarView.swift NetBar/NetBarApp.swift` → no user-visible interface-name or menu-bar throughput rendering remains.

## Useful next signals

After this pass, the highest-value additions are:

1. Internet latency and short-window packet loss, because they explain a connection that is technically online but feels bad.
2. Active DNS server and whether GlobalProtect has overridden it, especially useful on this network because local AdGuard and managed VPN DNS have distinct roles.
3. Public IP with a change timestamp, useful for diagnosing ISP or VPN route changes but requiring an explicit external lookup and privacy decision.
4. A small connection-event history for route, SSID, VPN, and reachability changes, stored locally and bounded.

Do not add all four to the main popover by default. Latency and DNS are the best next pair; put deeper history behind a secondary window if implemented.

## Stop conditions

- Stop if `State:/Network/Global/IPv4` no longer contains the primary route or gateway on a supported macOS release.
- Stop if native media queries cannot distinguish negotiated Ethernet speed from adapter capability; show plain `Ethernet` rather than guessing.
- Stop if showing a friendly access-point/router name requires authenticated UniFi access; that is a separate integration and permission boundary.
- Stop if graph additions force the core status, router, VPN, or active Wi-Fi facts below the initial viewport.

## Design documentation

- After acceptance and validation: keep the durable behavior description in `README.md`; no separate design-system document is needed for this single-surface utility.
