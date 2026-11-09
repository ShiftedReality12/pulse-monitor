import Foundation
import Testing
@testable import PulseApp
@testable import PulseCore

@Test func screenSignatureIgnoresSubPercentCpuAndIntraBucketChartNoise() {
    var quiet = Snapshot(); quiet.cpu = 3.2; quiet.memoryUsed = 8_000_000_000; quiet.memoryTotal = 16_000_000_000
    var nudged = quiet; nudged.cpu = 3.4
    var stepped = quiet; stepped.cpu = 4.2
    let plots = PlotHistory()
    let insights = Insights()
    #expect(ScreenSignature.token(snapshot: quiet, plots: plots, insights: insights) == ScreenSignature.token(snapshot: nudged, plots: plots, insights: insights))
    #expect(ScreenSignature.token(snapshot: quiet, plots: plots, insights: insights) != ScreenSignature.token(snapshot: stepped, plots: plots, insights: insights))
}

@Test func diskDisplayTokenIgnoresANewerTimestampInTheSameMinute() {
    let minute = Date(timeIntervalSince1970: 1_700_000_040)
    let same = DiskEstimate(path: "/var/me/Library", bytes: 50_000_000, complete: false, date: minute.addingTimeInterval(10))
    let later = DiskEstimate(path: "/var/me/Library", bytes: 50_000_000, complete: false, date: minute.addingTimeInterval(40))
    let grown = DiskEstimate(path: "/var/me/Library", bytes: 51_000_000, complete: false, date: minute.addingTimeInterval(40))
    let nextMinute = DiskEstimate(path: "/var/me/Library", bytes: 50_000_000, complete: false, date: minute.addingTimeInterval(70))
    #expect(DiskUsageModel.displayToken([same]) == DiskUsageModel.displayToken([later]))
    #expect(DiskUsageModel.displayToken([same]) != DiskUsageModel.displayToken([grown]))
    #expect(DiskUsageModel.displayToken([same]) != DiskUsageModel.displayToken([nextMinute]))
}

@Test func virtualMachineServiceRollsUpToTheResponsibleApp() {
    var app = ProcessSample(pid: 50, identity: 10, name: "com.docker.backend", path: "/Applications/Docker.app/Contents/MacOS/com.docker.backend", resident: 300_000_000, cpu: 1)
    app.rss = 80_000_000
    var vm = ProcessSample(pid: 9, identity: 20, name: "com.apple.Virtualization.VirtualMachine", path: "/System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine", resident: 5_000_000_000, cpu: 2)
    vm.parent = 1
    vm.responsible = 50
    vm.rss = 140_000_000
    let docker = Attribution.groups([app, vm]).first { $0.title == "Docker" }
    #expect(docker?.members.sorted() == [9, 50])
    #expect(docker?.resident == 5_300_000_000)
    #expect(docker?.rss == 220_000_000)
    #expect(docker?.why.contains("RSS 220 MB") == true)
}

@Test func otherUserProcessesSayNeedsAdminInsteadOfUnavailable() {
    var root = ProcessSample(pid: 3, identity: 5, name: "com.docker.vmnetd", path: "/Library/PrivilegedHelperTools/com.docker.vmnetd", resident: nil, cpu: nil)
    root.uid = 0
    root.parent = 1
    let group = Attribution.groups([root])[0]
    #expect(group.memoryLabel == "needs admin")
    #expect(group.compactMetrics.contains("needs admin"))
}

@MainActor @Test func providersRecheckFifteenMinutesAfterLaunch() {
    let monitor = Monitor()
    monitor.stopSampling()
    let started = monitor.providers.detections
    let launched = ProcessInfo.processInfo.systemUptime
    monitor.providerTime = { launched }
    monitor.apply(Mailbox.Batch(snapshot: Snapshot(), plots: nil, insights: nil))
    #expect(monitor.providers.detections == started)
    monitor.providerTime = { launched + 900 }
    monitor.apply(Mailbox.Batch(snapshot: Snapshot(), plots: nil, insights: nil))
    #expect(monitor.providers.detections == started + 1)
}

@Test func diskCardIgnoresTestFixtureFolders() {
    #expect(DiskRootPlan.isTestFixture("/tmp/repo/.build/disk-fixture-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))
    #expect(!DiskRootPlan.isTestFixture("/tmp/repo/Documents"))
}
