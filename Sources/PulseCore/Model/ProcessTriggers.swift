import Foundation

public struct ProcessDescription: Sendable {
    public let what: String
    public let why: String
}
enum ProcessTriggers {
    static func reason(_ name: String) -> String {
        switch name {
        case "mediaanalysisd":
            return "It runs on its own schedule even if you never open Photos: macOS scans your library while the Mac is idle or plugged in, and new iCloud photos trigger it. Normal; it backs off when you're active."
        case "photoanalysisd", "photolibraryd", "cloudphotod":
            return "New photos, library changes and scheduled Photos maintenance trigger this work, even with Photos closed."
        case "mds", "mds_stores", "mdworker", "mdworker_shared", "corespotlightd":
            return "New or changed files and app content trigger indexing; rebuilding an index can keep it busy."
        case "WindowServer", "Dock", "Finder", "SystemUIServer", "ControlCenter", "loginwindow":
            return "Your login session keeps it running to display and manage the desktop."
        case "kernel_task", "launchd", "logd", "syslogd", "notifyd", "distnoted", "fseventsd":
            return "macOS starts it during boot or login to supervise services and handle system events."
        case "Codex", "Claude Code", "Terminal", "iTerm2", "Code", "Cursor", "Xcode", "Docker", "Safari", "Google Chrome":
            return "The app or development session is open; its launcher is shown when a verified parent chain is available."
        case "Python", "python", "python3", "node", "swift-frontend", "git":
            return "A shell, app or build task launched this tool; the verified owner identifies that task when available."
        case "backupd", "backupd-helper":
            return "A scheduled Time Machine backup or a backup you requested starts this work."
        case "softwareupdated", "installd", "appstoreagent", "storedownloadd":
            return "A scheduled update check or a requested download or installation starts this work."
        case "bird", "cloudd", "fileproviderd", "filecoordinationd", "nsurlsessiond":
            return "File changes, cloud sync and app transfer requests wake this service in the background."
        case "bluetoothd", "bluetoothuserd", "airportd", "wifid", "mDNSResponder", "sharingd", "rapportd":
            return "Enabled network or nearby-device features keep it available; connections and discovery trigger work."
        case "coreaudiod", "audiomxd":
            return "Audio playback, recording and device changes request this service."
        case "trustd", "securityd", "secd", "tccd", "authd", "syspolicyd", "sandboxd":
            return "Apps and macOS request security, privacy or trust checks; the specific request is not exposed here."
        case "apsd", "usernoted", "NotificationCenter":
            return "Enabled notifications and widgets keep it available; incoming notifications trigger activity."
        case "timed", "ntpd": return "macOS periodically checks time servers and corrects the clock."
        case "powerd": return "Boot, sleep, wake, battery changes and app power requests trigger work."
        case "sysmond": return "A monitoring app requests process statistics while its resource display is open."
        default:
            return "macOS or an app requests this service as needed; the exact request or schedule is not exposed here."
        }
    }
}
