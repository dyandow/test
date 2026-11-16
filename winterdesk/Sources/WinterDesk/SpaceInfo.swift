import AppKit
import CoreGraphics
import Darwin

/// Asks the window server whether the main display is currently showing a full-screen Space.
/// Uses the same (undocumented, no-permission) call that window-management tools rely on.
/// Returns nil if it isn't available, so callers can fall back to other checks.
enum SpaceInfo {
    private typealias MainConnectionFn = @convention(c) () -> UInt32
    private typealias CopySpacesFn = @convention(c) (UInt32) -> Unmanaged<CFArray>?

    private static let functions: (MainConnectionFn, CopySpacesFn)? = {
        let all = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        guard let a = dlsym(all, "CGSMainConnectionID") ?? dlsym(all, "SLSMainConnectionID"),
              let b = dlsym(all, "CGSCopyManagedDisplaySpaces") ?? dlsym(all, "SLSCopyManagedDisplaySpaces")
        else { return nil }
        return (unsafeBitCast(a, to: MainConnectionFn.self), unsafeBitCast(b, to: CopySpacesFn.self))
    }()

    private static var mainDisplayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static func mainDisplayIsFullScreen() -> Bool? {
        guard let (mainConnection, copySpaces) = functions,
              let displays = copySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]],
              !displays.isEmpty else { return nil }
        let mainID = mainDisplayUUID
        let display = displays.first { ($0["Display Identifier"] as? String) == "Main" }
            ?? displays.first { ($0["Display Identifier"] as? String)?.caseInsensitiveCompare(mainID ?? "") == .orderedSame }
            ?? displays[0]
        guard let current = display["Current Space"] as? [String: Any],
              let type = (current["type"] as? NSNumber)?.intValue else { return nil }
        return type == 4   // 0 = normal desktop, 4 = full-screen app
    }
}
