//
//  OverlayController.swift
//  SwiftTraceKit
//
//  Owns the floating button and presents the dashboard.
//
//  The button lives in its own small UIWindow above the app. That keeps it
//  visible over sheets and full screen covers, and because the window is only
//  as big as the button, it never intercepts touches meant for the app.
//

import SwiftUI
import UIKit

@MainActor
final class OverlayController {

    private var bubbleWindow: TraceBubbleWindow?
    private weak var dashboard: UIViewController?
    private var sceneObserver: NSObjectProtocol?

    /// Runtime override, kept in memory only so the button comes back on the
    /// next launch.
    private var visibilityOverride: Bool?

    /// Current choice for this session; falls back to the configuration's default.
    var isBubbleVisible: Bool {
        get { visibilityOverride ?? TraceEngine.shared.configuration.showsFloatingButton }
        set {
            visibilityOverride = newValue
            refresh()
        }
    }

    // MARK: - Installation

    /// `SwiftTrace.start()` is often called before any window exists (for
    /// example in the `App` initializer), so installation also listens for
    /// the first scene activation.
    func install() {
        if sceneObserver == nil {
            sceneObserver = NotificationCenter.default.addObserver(
                forName: UIScene.didActivateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func uninstall() {
        if let sceneObserver {
            NotificationCenter.default.removeObserver(sceneObserver)
        }
        sceneObserver = nil
        bubbleWindow?.isHidden = true
        bubbleWindow = nil
        dashboard?.dismiss(animated: true)
    }

    private func refresh() {
        guard TraceEngine.shared.isRunning, isBubbleVisible else {
            bubbleWindow?.isHidden = true
            bubbleWindow = nil
            return
        }
        if bubbleWindow == nil, let scene = UIKitHierarchy.activeScene() {
            bubbleWindow = TraceBubbleWindow(
                windowScene: scene,
                onTap: { [weak self] in self?.presentDashboard() },
                // Stopping tears down this very window, so wait until the
                // gesture handler that triggered it has returned.
                onClose: { Task { @MainActor in TraceEngine.shared.stop() } }
            )
        }
        bubbleWindow?.isHidden = dashboard != nil
    }

    // MARK: - Dashboard

    func presentDashboard() {
        guard TraceEngine.shared.isRunning,
              dashboard == nil,
              let top = UIKitHierarchy.topViewController() else { return }

        let controller = TraceDashboardController(
            rootView: TraceDashboardView(initialScreen: TraceEngine.shared.screens.current) { [weak self] in
                self?.dashboard?.dismiss(animated: true)
            }
        )
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        dashboard = controller
        bubbleWindow?.isHidden = true
        top.present(controller, animated: true)
    }

    /// Called by the dashboard when it disappears, whether closed with the
    /// button or swiped down.
    func dashboardDidClose() {
        dashboard = nil
        refresh()
    }
}

/// Dedicated type so the rest of the library can recognise (and ignore) the
/// dashboard in the view controller hierarchy.
final class TraceDashboardController: UIHostingController<TraceDashboardView> {}

// MARK: - Bubble window

/// Whether the bubble is showing its close (cross) control after a long press.
@MainActor
final class TraceBubbleState: ObservableObject {
    @Published var showsClose = false
}

/// A tiny window that is the button itself.
final class TraceBubbleWindow: UIWindow {

    private static let size: CGFloat = 58
    private static let margin: CGFloat = 10
    /// The cross turns back into the normal button if left untouched.
    private static let closeTimeout: Duration = .seconds(4)

    private let onTap: () -> Void
    private let onClose: () -> Void
    private let state = TraceBubbleState()
    private var dragOffset: CGPoint = .zero
    private var closeTimeoutTask: Task<Void, Never>?

    init(windowScene: UIWindowScene, onTap: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onTap = onTap
        self.onClose = onClose
        super.init(windowScene: windowScene)

        windowLevel = .alert + 1
        backgroundColor = .clear

        let host = UIHostingController(rootView: TraceBubbleView(state: state))
        host.view.backgroundColor = .clear
        rootViewController = host

        let bounds = windowScene.coordinateSpace.bounds
        frame = CGRect(
            x: bounds.width - Self.size - Self.margin,
            y: bounds.height * 0.62,
            width: Self.size,
            height: Self.size
        )

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:))))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:))))
        isHidden = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // While the button shows the cross, the whole button is the close
        // target, so there is no small corner to miss.
        if state.showsClose {
            setShowsClose(false)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onClose()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            setShowsClose(true)
        case .ended, .cancelled:
            // Start the timeout only once the finger is lifted, so the user
            // gets the full time to tap the cross.
            if state.showsClose { startCloseTimeout() }
        default:
            break
        }
    }

    private func setShowsClose(_ shows: Bool) {
        closeTimeoutTask?.cancel()
        closeTimeoutTask = nil
        withAnimation(.spring(duration: 0.25)) {
            state.showsClose = shows
        }
    }

    private func startCloseTimeout() {
        closeTimeoutTask?.cancel()
        closeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeTimeout)
            guard !Task.isCancelled else { return }
            self?.setShowsClose(false)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let scene = windowScene else { return }
        // Work in scene coordinates, because the window itself moves while
        // dragging and its own coordinate space would move with it.
        let point = convert(gesture.location(in: self), to: scene.coordinateSpace)

        switch gesture.state {
        case .began:
            dragOffset = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        case .changed:
            frame.origin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
        case .ended, .cancelled:
            snapToEdge(in: scene)
        default:
            break
        }
    }

    /// Snaps to the nearest side, kept inside the safe area.
    private func snapToEdge(in scene: UIWindowScene) {
        let bounds = scene.coordinateSpace.bounds
        let insets = scene.windows.first { $0.isKeyWindow }?.safeAreaInsets ?? .zero

        let minX = insets.left + Self.margin
        let maxX = bounds.width - insets.right - Self.size - Self.margin
        let minY = insets.top + Self.margin
        let maxY = bounds.height - insets.bottom - Self.size - Self.margin

        let targetX = frame.midX < bounds.midX ? minX : maxX
        let targetY = min(max(frame.minY, minY), maxY)

        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.5) {
            self.frame.origin = CGPoint(x: targetX, y: targetY)
        }
    }
}

// MARK: - Bubble view

private struct TraceBubbleView: View {
    @ObservedObject var state: TraceBubbleState
    @ObservedObject private var network = TraceEngine.shared.network
    @ObservedObject private var issues = TraceEngine.shared.issues

    /// Unseen issues take priority over the request count, because they are
    /// what the developer should look at next.
    private var badge: (text: String, color: Color)? {
        if issues.unseenCount > 0 {
            return (issues.unseenCount > 99 ? "99+" : "\(issues.unseenCount)", .orange)
        }
        guard let last = network.entries.first else { return nil }
        let count = network.entries.count
        return (count > 99 ? "99+" : "\(count)", last.isFailure ? .red : .green)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(state.showsClose ? Color.red : Color(white: 0.12))
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .overlay(
                    Image(systemName: state.showsClose ? "xmark" : "waveform.path.ecg")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                )
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                .padding(5)

            if let badge, !state.showsClose {
                Text(badge.text)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(badge.color))
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
            }
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel(state.showsClose ? "Stop SwiftTraceKit" : "SwiftTraceKit dashboard")
    }
}
