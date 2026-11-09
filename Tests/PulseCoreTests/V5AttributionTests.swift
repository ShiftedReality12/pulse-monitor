import Foundation
import Testing
@testable import PulseCore

private func process(_ pid: Int32, _ parent: Int32 = 0, _ identity: UInt64 = 100, _ name: String = "tool", _ path: String = "/bin/tool") -> ProcessSample {
    var p = ProcessSample(pid: pid, identity: identity, name: name, path: path, resident: 40, cpu: 3)
    p.parent = parent; p.writesPerSecond = 0; return p
}
@Test func reusedParentHiddenIdentityCannotOwnOlderChild() {
    let groups = Attribution.groups([process(10, 20, 10, "python"), process(20, 0, 0, "codex", "/bin/codex")])
    #expect(groups.count == 2)
    #expect(groups.first { $0.category == "AI session" }?.members == [20])
    #expect(groups.allSatisfy { $0.limited })
}
@Test func twoAICycleKeepsEachOwnerWithItsOwnPID() {
    for identity: UInt64 in [0, 100] {
        let groups = Attribution.groups([process(10, 20, identity, "codex"), process(20, 10, identity, "claude")])
        #expect(groups.count == 2)
        for group in groups {
            #expect(group.members.count == 1)
            #expect(group.id == "ai:\(group.members[0]):\(identity)" + (identity == 0 ? ":path:/bin/tool" : ""))
            #expect(group.limited)
        }
    }
}
@Test func identicalNamesDifferentPathsNeverMerge() {
    let groups = Attribution.groups([process(10, 0, 10, "日本 helper 🌡", "/opt/a/helper"), process(20, 0, 20, "日本 helper 🌡", "/opt/b/helper")])
    #expect(groups.count == 2)
    #expect(Set(groups.map(\.id)) == ["exec:/opt/a/helper", "exec:/opt/b/helper"])
}
@Test func canonicalPathsGroupSameExecutable() {
    let groups = Attribution.groups([process(10, 0, 10, "tool", "/opt/a/../tool"), process(20, 0, 20, "tool", "/opt/tool")])
    #expect(groups.count == 1)
    #expect(groups[0].members == [10, 20])
}
@Test func rawProcessTitleCannotReturnThroughPathOrBundle() {
    let p = process(52, 0, 100, "Process 52", "/tmp/Process 52")
    #expect(Attribution.groups([p])[0].title == "Command-line tool in /tmp")
    let b = process(53, 0, 100, "Process 52", "/tmp/Process 52.app/Contents/MacOS/Process 52")
    #expect(Attribution.groups([b])[0].title != "Process 52")
}
@Test func everyDictionaryEntryHasWhatAndWhyWith80NameFixture() {
    let names = "mediaanalysisd photoanalysisd photolibraryd cloudphotod mds mds_stores mdworker mdworker_shared corespotlightd WindowServer kernel_task launchd logd syslogd sysmond configd powerd runningboardd notifyd distnoted cfprefsd trustd securityd secd tccd authd opendirectoryd accountsd loginwindow SystemUIServer ControlCenter Finder Dock Safari sharingd rapportd bluetoothd bluetoothuserd airportd wifid mDNSResponder locationd timed ntpd coreaudiod audiomxd coreduetd duetexpertd suggestd knowledge-agent bird cloudd fileproviderd filecoordinationd nsurlsessiond apsd usernoted NotificationCenter backupd backupd-helper fseventsd diskarbitrationd diskmanagementd storagekitd softwareupdated installd appstoreagent storedownloadd kernelmanagerd iconservicesagent iconservicesd fontd fontworker pkd sandboxd usbd syspolicyd Terminal Python python python3 node git Codex".split(separator: " ").map(String.init)
    #expect(names.count >= 80)
    for name in names { #expect(ProcessDictionary.entries[name] != nil) }
    for entry in ProcessDictionary.entries.values { #expect(!entry.what.isEmpty && !entry.why.isEmpty) }
    for path in ["", "/usr/libexec/mystery", "/Applications/Mystery.app/Contents/MacOS/tool", "/opt/bin/mystery"] {
        let entry = ProcessDictionary.details(name: "mystery", path: path)
        #expect(!entry.what.isEmpty && !entry.why.isEmpty)
    }
}
@Test func mediaAnalysisExplainsIndependentSchedule() {
    let entry = ProcessDictionary.details(name: "mediaanalysisd")
    #expect(entry.what.contains("faces, objects, text"))
    #expect(entry.why.contains("even if you never open Photos"))
    #expect(entry.why.contains("iCloud"))
}
@Test func grokHelpersExplainWhatAndWhy() {
    let group = Attribution.groups([process(10, 0, 100, "Grok Bot Helper", "/Applications/Grok Bot.app/Contents/Frameworks/Helper")])[0]
    #expect(group.title == "Grok Bot")
    #expect(group.runningReason.contains("Grok Bot is open"))
    #expect(group.explanation.contains("renderer, GPU or network"))
    #expect(ProcessDictionary.details(name: "helper", path: "/Applications/Grok Bot.app/Contents/MacOS/helper").why.contains("Grok Bot is open"))
}
@Test func sessionReasonUsesVerifiedLauncherAndFolder() {
    var p = process(20, 10, 200, "codex", "/bin/codex"); p.cwd = "/work/project"
    let group = Attribution.groups([process(10, 0, 100, "herdr", "/Applications/herdr.app/Contents/MacOS/herdr"), p]).first { $0.category == "AI session" }!
    #expect(group.runningReason == "Started by herdr in /work/project.")
}
@Test func appReasonDistinguishesObservedLoginAndLaunchdChains() {
    let app = process(20, 10, 200, "Example", "/Applications/Example.app/Contents/MacOS/Example")
    let login = Attribution.groups([process(10, 0, 100, "loginwindow", "/System/loginwindow"), app]).first { $0.category == "App" }!
    #expect(login.runningReason.contains("Login item or login-session app"))
    let service = Attribution.groups([process(10, 0, 100, "launchd", "/sbin/launchd"), app]).first { $0.category == "App" }!
    #expect(service.runningReason.contains("Started by launchd"))
    #expect(service.runningReason.contains("unavailable"))
}
