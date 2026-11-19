//
//  SwiftTrace.swift
//  SwiftTraceKit
//
//  Public entry point of the library. Everything a host app needs is exposed
//  here as static members so integration stays a one-liner:
//
//      SwiftTrace.start()
//
//  The heavy lifting lives in `TraceEngine`, which this type forwards to.
//

import Foundation
import UIKit

/// Entry point of SwiftTraceKit.
///
/// Call `start(_:)` once, as early as possible in the app lifecycle (for
/// example in your `App` initializer or `application(_:didFinishLaunchingWithOptions:)`).
/// From then on network calls are captured, performance is sampled and a
/// floating button gives access to the dashboard.
@MainActor
public enum SwiftTrace {

    // MARK: - Lifecycle

    /// Starts SwiftTraceKit with the given configuration.
    ///
    /// Calling it again replaces the configuration. When the configuration's
    /// `availability` does not allow running in the current build (for example
    /// `.debugOnly` in a Release build) this call does nothing, so it is safe
    /// to leave in production code.
    public static func start(_ configuration: TraceConfiguration = TraceConfiguration()) {
        TraceEngine.shared.start(with: configuration)
    }

    /// Stops capturing and monitoring and removes the floating button.
    /// Captured data stays in memory until `clearAll()` is called.
    public static func stop() {
        TraceEngine.shared.stop()
    }

    /// `true` between a successful `start(_:)` and `stop()`.
    public static var isRunning: Bool {
        TraceEngine.shared.isRunning
    }

    /// The configuration passed to the last `start(_:)` call.
    public static var configuration: TraceConfiguration {
        TraceEngine.shared.configuration
    }

    // MARK: - Dashboard

    /// Shows or hides the floating button at runtime.
    ///
    /// The choice lasts for the current launch only, so the button is back on
    /// the next launch. Long pressing the button shows a cross that stops
    /// SwiftTraceKit for the current launch (see `stop()`).
    public static var isFloatingButtonVisible: Bool {
        get { TraceEngine.shared.overlay.isBubbleVisible }
        set { TraceEngine.shared.overlay.isBubbleVisible = newValue }
    }

    /// Presents the dashboard on top of the current screen.
    public static func showDashboard() {
        TraceEngine.shared.overlay.presentDashboard()
    }

    // MARK: - Screens

    /// Name of the screen SwiftTraceKit currently attributes activity to.
    public static var currentScreen: String {
        TraceEngine.shared.screens.current
    }

    /// Sets the current screen name manually.
    ///
    /// Prefer the `.traceScreen(_:)` view modifier in SwiftUI or a
    /// `screenNameProvider` in the configuration. This method is useful for
    /// UIKit code that does not set view controller titles. Pass `nil` to go
    /// back to automatic detection.
    public static func setScreen(_ name: String?) {
        TraceEngine.shared.screens.setManual(name)
    }

    // MARK: - Issues

    /// Every issue raised so far, newest first.
    public static var issues: [TraceIssue] {
        TraceEngine.shared.issues.issues
    }

    /// Removes captured requests, performance history, per-screen statistics
    /// and issues.
    public static func clearAll() {
        TraceEngine.shared.network.clear()
        TraceEngine.shared.performance.clear()
        TraceEngine.shared.issues.clear()
    }

    // MARK: - Leaks

    /// Reports a memory leak if `object` is still alive shortly after this call.
    ///
    /// Call it at the moment an object is expected to go away, for example when
    /// a coordinator finishes or a custom container removes a child. The check
    /// runs after `delay` (or the configured `leakCheckDelay`) and once more
    /// after the same delay, to give animations and caches time to let go.
    public static func expectDeallocation(of object: AnyObject, name: String? = nil, after delay: TimeInterval? = nil) {
        TraceEngine.shared.leaks.expectDeallocation(
            of: object,
            name: name ?? TypeName.of(object),
            screen: TraceEngine.shared.screens.current,
            delay: delay
        )
    }

    // MARK: - Network

    /// Adds SwiftTraceKit's capturing protocol to a session configuration.
    ///
    /// Sessions built from `URLSessionConfiguration.default` or `.ephemeral`
    /// after `start(_:)` are captured automatically. Use this for
    /// configurations that were created before `start(_:)`, or for
    /// configurations you build in other ways.
    public static func enableCapture(for configuration: URLSessionConfiguration) {
        NetworkCapture.insertProtocol(into: configuration)
    }

    /// Records a request manually.
    ///
    /// Use this when your networking layer is not built on `URLSession`, or
    /// when you want full control over what is logged. If you call it for
    /// requests that also go through `URLSession`, set
    /// `capturesURLSessionAutomatically` to `false` to avoid duplicate entries.
    ///
    /// - Parameters:
    ///   - request: The request that was sent, including its body.
    ///   - response: The response, if one was received.
    ///   - data: The response body.
    ///   - error: The transport error, if the request failed.
    ///   - errorMessage: A custom error description. Takes precedence over `error`.
    ///   - startedAt: When the request was sent. Used to compute the duration.
    ///   - screen: The screen that fired the request. Capture it before
    ///     awaiting the response, because the user may navigate away while the
    ///     request is in flight. When `nil`, the current screen is used.
    ///   - isRetry: Marks the entry as a retry, for example after a token refresh.
    nonisolated public static func record(
        request: URLRequest,
        response: URLResponse?,
        data: Data?,
        error: (any Error)? = nil,
        errorMessage: String? = nil,
        startedAt: Date,
        screen: String? = nil,
        isRetry: Bool = false
    ) {
        let state = TraceRuntime.shared.state
        guard state.isRunning else { return }

        let entry = NetworkLogEntry(
            request: request,
            requestBody: request.httpBody,
            response: response as? HTTPURLResponse,
            data: data,
            error: error,
            errorMessage: errorMessage,
            startedAt: startedAt,
            finishedAt: Date(),
            screen: screen ?? state.currentScreen,
            isRetry: isRetry,
            timing: nil,
            maxBodyBytes: state.maxResponseBodyBytes
        )
        Task { @MainActor in
            TraceEngine.shared.network.add(entry)
        }
    }

    /// The screen name as seen from any thread.
    ///
    /// Useful for capturing the screen at the start of a request in a
    /// networking layer that is not isolated to the main actor.
    nonisolated public static var currentScreenSnapshot: String {
        TraceRuntime.shared.state.currentScreen
    }
}
