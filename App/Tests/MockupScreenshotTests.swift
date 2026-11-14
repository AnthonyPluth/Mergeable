import XCTest
import SwiftUI
import MergeableCore
@testable import Mergeable
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders the real screens from fixture data to PNGs for sign-off against docs/mockups. Runs only when
/// SCREENSHOT_DIR is set (CI passes it as TEST_RUNNER_SCREENSHOT_DIR); otherwise every test is skipped.
/// Dark only, 2x. File names are `<platform>-<frame>.png`, platform being `macos` or `ios`.
@MainActor
final class MockupScreenshotTests: XCTestCase {
    private let phone = CGSize(width: 390, height: 844)
    private let window = CGSize(width: 1120, height: 700)

    #if os(macOS)
    private let platform = "macos"
    #else
    private let platform = "ios"
    #endif

    private func outputDir() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("SCREENSHOT_DIR is not set")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPhoneFrames() async throws {
        let dir = try outputDir()
        let scene = MockupFixtures.make()
        try await snapshot(scene.inboxRoot, size: phone, to: dir.appendingPathComponent("\(platform)-iphone-inbox.png"))
        try await snapshot(scene.detailRoot, size: phone, to: dir.appendingPathComponent("\(platform)-iphone-detail.png"))
        try await snapshot(scene.mergeSheetRoot, size: phone, to: dir.appendingPathComponent("\(platform)-iphone-merge-sheet.png"))
    }

    func testMacWindow() async throws {
        #if os(macOS)
        let dir = try outputDir()
        let scene = MockupFixtures.make()
        try await snapshot(scene.macRoot, size: window, to: dir.appendingPathComponent("macos-mac-window.png"))
        #else
        throw XCTSkip("The Mac window is rendered by the macOS run")
        #endif
    }

    /// Hosts the view in a real window (so List, ScrollView, pickers and .task all run), waits, and writes a 2x dark PNG.
    private func snapshot<V: View>(_ view: V, size: CGSize, to url: URL) async throws {
        #if os(macOS)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.setContentSize(size)
        win.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 1_500_000_000)   // let .task and layout settle
        host.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw XCTSkip("no bitmap") }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return XCTFail("PNG encoding failed") }
        try png.write(to: url)
        win.orderOut(nil)
        #else
        let host = UIHostingController(rootView: view)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let win = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        win.frame = CGRect(origin: .zero, size: size)
        win.overrideUserInterfaceStyle = .dark
        win.rootViewController = host
        win.makeKeyAndVisible()
        host.view.frame = win.bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            win.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        guard let png = image.pngData() else { return XCTFail("PNG encoding failed") }
        try png.write(to: url)
        win.isHidden = true
        #endif
    }
}
