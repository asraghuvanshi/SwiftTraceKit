# SwiftTraceKit

An in-app debugging toolkit for iOS. Add one line to your app and get:

- a **network inspector** for every request, with latency broken down phase by phase
- a **performance monitor** for memory, CPU, battery drain and thermal state, overall and per screen
- a **memory leak detector** for UIKit view controllers and SwiftUI view models
- an **issues feed** that warns you when something crosses a threshold

All of it opens from a floating button (or by shaking the device) inside the running app. You don't need a proxy, a Mac or Instruments to see what's happening.

By default it only runs when the app is built in Debug, so the integration can stay in your code without ever reaching the App Store.

---

## Contents

- [What it can do](#what-it-can-do)
- [Use cases](#use-cases)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Naming screens](#naming-screens)
- [Detecting memory leaks](#detecting-memory-leaks)
- [Networking setups](#networking-setups)
- [Debug mode switch](#debug-mode-switch)
- [Configuration reference](#configuration-reference)
- [Forwarding issues to your own logging](#forwarding-issues-to-your-own-logging)
- [Keeping it out of production](#keeping-it-out-of-production)
- [How it works](#how-it-works)
- [Limitations](#limitations)
- [FAQ](#faq)

---

## What it can do

### Network inspector

- Captures every `URLSession` request automatically: `URLSession.shared`, custom sessions and libraries built on `URLSession` such as Alamofire. No changes to your networking code are needed.
- Shows the method, URL, status, duration, size, query parameters, body fields (form, JSON and multipart, with file parts summarised), headers and the response.
- Pretty-prints and syntax-colours JSON responses, with find-in-response and a "matching lines only" filter.
- Breaks latency into phases: **DNS lookup, TCP connect, TLS handshake, request send, server wait (time to first byte), download**. It also shows the protocol (h2, h3, http/1.1), whether the connection was reused, the redirect count and the remote address.
- Groups requests by the screen that fired them, with a "This Screen" or "All Calls" switch.
- Searches by endpoint, parameter key, parameter value or `key=value`, and optionally inside response bodies.
- Filters by status (success or failed) and by HTTP method.
- Copies the URL, the request as a **cURL** command, the parameters as JSON or the response, or shares a full text report of the request.
- Masks sensitive headers (Authorization, Cookie, tokens) until you tap "Show".

### Performance monitor

- **Memory**: the live footprint (the same number Xcode's memory gauge shows and that iOS uses to enforce its limit), a two-minute chart, and on real devices how close the app is to its memory limit.
- **CPU**: live usage of the whole process with a two-minute chart.
- **Battery**: level, charging state, Low Power Mode, and the measured **drain rate per hour** while unplugged.
- **Thermal state**: nominal, fair, serious or critical.
- **Network latency statistics**: average, median, 95th percentile, data sent and received, and a list of the slowest endpoints.
- **Per-screen numbers**: visits, time spent, peak memory, the largest memory growth in a single visit, average and peak CPU, request count, average latency and failed requests. You can sort by memory, CPU, time or latency to find the heaviest screen.

### Memory leak detection

- **UIKit**: every view controller defined in your app is checked automatically after it's popped or dismissed. If it's still alive a few seconds later, it's reported along with the usual causes.
- **SwiftUI**: add `.traceLeaks(of: viewModel)` to a screen. When the view leaves the hierarchy, the view model must be released too.
- **Anything else**: call `SwiftTrace.expectDeallocation(of: object)` at the moment an object should go away.

### Issues feed

SwiftTraceKit raises an issue, shows a badge on the floating button and logs to the console when:

| Issue | Raised when |
|---|---|
| Slow request | A request takes longer than `slowRequestDuration` (3 s by default). The message says which phase was slow. |
| Failed request | A transport error or a 5xx response. 4xx responses are not reported, because they are usually part of normal flows. |
| High memory | The footprint is above `highMemoryMegabytes` (500 MB by default). |
| Close to the memory limit | The app uses more than `memoryLimitWarningRatio` (80%) of what iOS allows. Real devices only. |
| Memory grew on screen | Memory grew by more than `screenMemoryGrowthMegabytes` (80 MB) during one visit of a screen. |
| System memory warning | iOS sent `didReceiveMemoryWarning`. |
| Sustained high CPU | CPU stayed above `highCPUPercent` (80%) for `highCPUDuration` (5 s). |
| Fast battery drain | Drain is above `batteryDrainPercentPerHour` (20% per hour) after at least 10 minutes unplugged. |
| Device is hot | The thermal state reached serious or critical. |
| Possible memory leak | A watched object outlived its screen. |

Every issue records the screen that was visible at the time.

---

## Use cases

- **"Which API does this screen call, and with what parameters?"** Open the dashboard on that screen. The Network tab starts on "This Screen".
- **Debugging a bug report from QA.** Ask QA to reproduce the bug, open the failing request, and share the full report or copy it as cURL to replay in Terminal or Postman.
- **"The app feels slow on this screen."** Check the request's timing. Server wait means the backend is slow, download means the payload is too big, and connect or TLS means connection setup.
- **Comparing backend environments.** Watch the 95th percentile latency and the slowest endpoints while you use the app on staging and on production.
- **Hunting retain cycles.** Navigate in and out of screens. Any view controller or view model that doesn't go away is flagged with its name and screen.
- **Finding the screen that eats memory.** Sort Screens by peak memory or largest growth. Image-heavy lists and caches show up immediately.
- **Investigating "the app drains my battery" or "the phone gets hot".** Sort Screens by CPU load, and watch the drain rate and thermal state during a real session on a device.
- **Catching crashes from memory pressure.** The memory limit warning fires before iOS kills the app, which leaves no crash report.
- **Testing without Xcode attached.** With `availability: .always` in an internal QA build, testers get the same tools on their own devices.

---

## Requirements

- iOS 17 or later
- Xcode 16 or later (Swift 6 toolchain)
- Works with SwiftUI, UIKit or both

---

## Installation

### Xcode

1. In your app project, choose **File > Add Package Dependencies...**
2. Paste the repository URL:
   ```
   https://github.com/<your-username>/SwiftTraceKit.git
   ```
3. Choose **Up to Next Major Version** starting at `1.0.0`, and add the `SwiftTraceKit` library to your app target.

### Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/<your-username>/SwiftTraceKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: ["SwiftTraceKit"]
    )
]
```

### Local package (while developing the library)

Choose **File > Add Package Dependencies... > Add Local...** and select the `SwiftTraceKit` folder. Changes to the package show up in the app immediately.

---

## Quick start

### SwiftUI app

```swift
import SwiftUI
import SwiftTraceKit

@main
struct MyApp: App {
    init() {
        SwiftTrace.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### UIKit app

```swift
import UIKit
import SwiftTraceKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        SwiftTrace.start()
        return true
    }
}
```

Run the app from Xcode. A dark round button appears on the right edge. Drag it anywhere, then tap it (or shake the device) to open the dashboard.

Call `start()` as early as possible. Sessions created from `URLSessionConfiguration.default` before `start()` aren't captured automatically (see [Networking setups](#networking-setups)).

---

## Naming screens

Every request, sample and issue is linked to a screen. SwiftTraceKit tries these sources in order:

1. **`screenNameProvider`** in the configuration. Use this if your app has its own router:
   ```swift
   var configuration = TraceConfiguration()
   configuration.screenNameProvider = { AppRouter.shared.currentRouteName }
   SwiftTrace.start(configuration)
   ```
2. **The `.traceScreen(_:)` modifier** on the root view of a SwiftUI screen:
   ```swift
   struct OrderDetailView: View {
       var body: some View {
           List { /* ... */ }
               .traceScreen("Order Detail")
       }
   }
   ```
3. **`SwiftTrace.setScreen("Checkout")`**, set from code (useful in UIKit).
4. **Automatic detection**: the navigation title of the visible screen, or the view controller's class name. This works without any code, but explicit names read better.

---

## Detecting memory leaks

### UIKit

Nothing to do. View controllers defined in your app are checked when they're popped or dismissed. System view controllers are skipped, because some of them are cached on purpose.

### SwiftUI

Attach the modifier to the view that owns the object:

```swift
struct OrderDetailView: View {
    @StateObject private var viewModel = OrderDetailViewModel()

    var body: some View {
        content
            .traceLeaks(of: viewModel)
    }
}
```

When the view is removed from the hierarchy (popped, dismissed or replaced), `viewModel` is expected to be released within a few seconds. Switching tabs or pushing another screen on top doesn't trigger the check, because the view still exists.

Only watch objects the screen **owns**. Singletons and objects passed down from a parent are expected to outlive the view and would be reported wrongly.

### Anywhere else

```swift
func coordinatorDidFinish(_ coordinator: Coordinator) {
    children.removeAll { $0 === coordinator }
    SwiftTrace.expectDeallocation(of: coordinator)
}
```

### Reading a leak report

A report means the object was still alive about 4 seconds (two checks of `leakCheckDelay`) after it should have gone. The usual causes:

- A closure stored by the object that captures `self` strongly (use `[weak self]`)
- A delegate property declared without `weak`
- A `Timer` or `CADisplayLink` that is never invalidated
- A Combine subscription stored on the object that references the object itself
- A `NotificationCenter` observer block that captures `self`

---

## Networking setups

### Plain URLSession or Alamofire

You don't need to do anything. Requests are captured automatically.

### Session configurations created before `start()`

Enable capture on them explicitly:

```swift
let configuration = URLSessionConfiguration.default
SwiftTrace.enableCapture(for: configuration)
let session = URLSession(configuration: configuration)
```

### Your own networking layer (manual recording)

If you'd rather record requests yourself, for example to mark retries or attach custom error messages, turn automatic capture off and call `record`:

```swift
var configuration = TraceConfiguration()
configuration.capturesURLSessionAutomatically = false
SwiftTrace.start(configuration)
```

```swift
func send(_ request: URLRequest) async throws -> Data {
    let startedAt = Date()
    // Capture the screen before awaiting: the user may navigate away while
    // the request is in flight.
    let screen = SwiftTrace.currentScreenSnapshot

    do {
        let (data, response) = try await session.data(for: request)
        SwiftTrace.record(request: request, response: response, data: data,
                          startedAt: startedAt, screen: screen)
        return data
    } catch {
        SwiftTrace.record(request: request, response: nil, data: nil, error: error,
                          startedAt: startedAt, screen: screen)
        throw error
    }
}
```

`record` and `currentScreenSnapshot` can be called from any thread.

### Skipping hosts

```swift
configuration.ignoredHosts = ["analytics.example.com", "sentry.io"]
```

Subdomains match too.

---

## Debug mode switch

Users (testers) can hide or show the floating button at runtime. Long pressing the button shows a cross that stops SwiftTraceKit (button and tracking) until the next launch. The choice is not saved, so the button is back on the next launch:

```swift
struct SettingsView: View {
    @State private var debugMode = SwiftTrace.isFloatingButtonVisible

    var body: some View {
        if SwiftTrace.isRunning {
            Toggle("Debug Mode", isOn: $debugMode)
                .onChange(of: debugMode) { _, isOn in
                    SwiftTrace.isFloatingButtonVisible = isOn
                }
        }
    }
}
```

Wrapping the toggle in `SwiftTrace.isRunning` hides it automatically in builds where SwiftTraceKit doesn't run.

You can also open the dashboard from code with `SwiftTrace.showDashboard()`.

---

## Configuration reference

```swift
var configuration = TraceConfiguration()

// General
configuration.availability = .debugOnly          // .debugOnly, .always, .never
configuration.showsFloatingButton = true
configuration.opensDashboardOnShake = true
configuration.logsIssuesToConsole = true
configuration.onIssue = { issue in /* forward it */ }
configuration.screenNameProvider = { nil }

// Network
configuration.capturesURLSessionAutomatically = true
configuration.maxNetworkEntries = 300
configuration.maxResponseBodyBytes = 2_000_000
configuration.ignoredHosts = []
configuration.sensitiveHeaders = ["authorization", "cookie", "token"]

// Performance
configuration.monitorsPerformance = true
configuration.samplingInterval = 1                // seconds

// Leaks
configuration.detectsViewControllerLeaks = true

// Thresholds
configuration.thresholds.slowRequestDuration = 3          // seconds
configuration.thresholds.highMemoryMegabytes = 500
configuration.thresholds.memoryLimitWarningRatio = 0.8    // 80% of the per-app limit
configuration.thresholds.screenMemoryGrowthMegabytes = 80
configuration.thresholds.highCPUPercent = 80              // percent of one core
configuration.thresholds.highCPUDuration = 5              // seconds
configuration.thresholds.batteryDrainPercentPerHour = 20
configuration.thresholds.batteryObservationWindow = 600   // seconds
configuration.thresholds.leakCheckDelay = 2               // seconds

SwiftTrace.start(configuration)
```

Other API:

| Member | Purpose |
|---|---|
| `SwiftTrace.start(_:)` / `stop()` | Start or stop everything |
| `SwiftTrace.isRunning` | Whether the library is active in this build |
| `SwiftTrace.showDashboard()` | Open the dashboard from code |
| `SwiftTrace.isFloatingButtonVisible` | Runtime "debug mode" switch, for the current launch |
| `SwiftTrace.setScreen(_:)` | Set the screen name manually |
| `SwiftTrace.currentScreen` / `currentScreenSnapshot` | Read the current screen (main actor or any thread) |
| `SwiftTrace.issues` | All issues raised so far |
| `SwiftTrace.clearAll()` | Clear requests, performance history and issues |
| `SwiftTrace.expectDeallocation(of:name:after:)` | Leak check for any object |
| `SwiftTrace.enableCapture(for:)` | Capture a session configuration created before `start()` |
| `SwiftTrace.record(...)` | Record a request manually |
| `.traceScreen(_:)` | Name a SwiftUI screen |
| `.traceLeaks(of:name:)` | Leak check for an object owned by a SwiftUI view |

---

## Forwarding issues to your own logging

```swift
configuration.onIssue = { issue in
    MyLogger.warning("\(issue.kind.title): \(issue.title) on \(issue.screen) - \(issue.message)")
}
```

Issues are also written to the unified log under the subsystem `SwiftTraceKit`, so you can filter for them in Xcode's console or in Console.app.

---

## Keeping it out of production

`availability` decides whether `start()` does anything:

| Value | Xcode run (Debug) | Archive / TestFlight / App Store (Release) |
|---|---|---|
| `.debugOnly` (default) | Runs | Does nothing |
| `.always` | Runs | Runs (use for internal QA builds only) |
| `.never` | Does nothing | Does nothing |

With `.debugOnly`, Release builds get no floating button, no capture, no swizzling and no monitoring. `start()` returns immediately.

If you'd rather not ship the library binary in Release builds at all, wrap the import and the call:

```swift
#if DEBUG
import SwiftTraceKit
#endif

init() {
    #if DEBUG
    SwiftTrace.start()
    #endif
}
```

All data lives in memory only. Nothing is written to disk or sent anywhere.

---

## How it works

- **Network capture**: a `URLProtocol` subclass is registered globally and added to every configuration returned by `URLSessionConfiguration.default` and `.ephemeral`. It replays each request on an internal session and passes the response, data and errors back to your code unchanged, while collecting `URLSessionTaskMetrics` for the timing breakdown.
- **Memory**: `task_info(TASK_VM_INFO).phys_footprint`, the value iOS uses for its memory limit. The remaining headroom comes from `os_proc_available_memory()`.
- **CPU**: the sum of `thread_info(THREAD_BASIC_INFO).cpu_usage` across all non-idle threads of the process.
- **Battery and heat**: `UIDevice` battery level and state, `ProcessInfo.thermalState` and Low Power Mode, plus their change notifications.
- **Leaks**: a weak reference to the object is checked twice after it should have been released. UIKit controllers are hooked through `viewDidDisappear`; SwiftUI uses a token in `@StateObject` storage, which SwiftUI only releases when the view truly leaves the hierarchy.
- **Floating button**: a small `UIWindow` above the app, only as big as the button, so it never blocks touches meant for your UI.

---

## Limitations

These are honest constraints of the platform or of the approach:

- **Battery per screen can't be measured.** iOS doesn't expose energy use per app or per screen. SwiftTraceKit measures real device drain over time and shows CPU load per screen, which is the main driver of energy use.
- **The battery level and drain rate are unavailable on the simulator.** The memory limit is too. Use a real device for those numbers.
- **SSL pinning**: captured requests use default certificate handling, so a custom authentication challenge handler in your own session delegate doesn't run for them. Add pinned hosts to `ignoredHosts` if you need pinning while debugging.
- **Not captured**: background `URLSession` transfers, WebSocket tasks and stream tasks. Upload tasks that pass the body separately (`uploadTask(with:from:)`) are captured without the request body.
- **Leak detection is heuristic.** An object that is legitimately kept alive (for example cached on purpose) is reported. Only watch objects you expect to be released.
- **CPU is a percentage of one core**, so values above 100% are normal on multi-core devices when several threads are busy.

---

## FAQ

**Does it slow down my app?**
Sampling runs once per second and takes microseconds. Network capture adds a copy of each response body in memory, capped by `maxResponseBodyBytes` per request and `maxNetworkEntries` overall.

**Will it conflict with Pulse, netfox or similar tools?**
Several `URLProtocol`-based tools can coexist, but each one replays requests, so running two at once can produce duplicate or missing entries. Use one at a time.

**I see every request twice.**
You're calling `SwiftTrace.record(...)` while automatic capture is also on. Set `capturesURLSessionAutomatically = false`.

**The floating button doesn't appear.**
Check that `SwiftTrace.isRunning` is `true`. With `.debugOnly` the app must be built in the Debug configuration. Also check that it wasn't stopped with the long press cross, or hidden through `isFloatingButtonVisible`, during this launch.

**Can testers use it in TestFlight builds?**
Yes. Set `availability = .always` in a build configuration used only for internal testing, and never in the App Store build.
