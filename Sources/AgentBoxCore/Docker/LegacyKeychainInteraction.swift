import Foundation
import Security

/// Compatibility for existing login-keychain records. LAContext applies to the
/// data-protection backend; legacy SecItemCopyMatching_osx can otherwise prompt
/// (and wait indefinitely) during an automatic reconnect.
enum LegacyKeychainInteraction {
    private static let lock = NSLock()
    static func withoutUI<T>(
        get: (UnsafeMutablePointer<DarwinBoolean>) -> OSStatus = SecKeychainGetUserInteractionAllowed,
        set: (Bool) -> OSStatus = SecKeychainSetUserInteractionAllowed,
        operation: () throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        var previous: DarwinBoolean = true
        guard get(&previous) == errSecSuccess else { throw BrowserComputerError.tokenAuthorizationRequired }
        guard set(false) == errSecSuccess else { throw BrowserComputerError.tokenAuthorizationRequired }
        defer { _ = set(previous.boolValue) }
        return try operation()
    }
}
