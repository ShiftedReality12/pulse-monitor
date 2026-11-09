import Foundation
import Darwin

public enum FullDiskAccess {
    /// Silent FDA sentinel only: never read the database or request authorization.
    public static func granted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
