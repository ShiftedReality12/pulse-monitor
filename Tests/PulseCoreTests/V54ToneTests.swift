import Testing
@testable import PulseCore

@Test func coolHeatDoesNotTurnPinkForCriticalMemory() {
    var snapshot = healthySnapshot()
    snapshot.temperature = 65; snapshot.pressure = .critical
    #expect(snapshot.heatLevel == .cool)
    #expect(snapshot.healthTone == .hot)
    #expect(snapshot.heatTone == .calm)
    #expect(snapshot.heatTone == snapshot.heatLevel.tone)
}
@Test func semanticTonesFollowTheirOwnMetricAndAvailability() {
    var snapshot = healthySnapshot()
    snapshot.memoryTotal = 16_000_000_000; snapshot.memoryUsed = 2_000_000_000
    for (temperature, tone) in [(65.0, Tone.calm), (70, .warm), (85, .hot), (95, .risk)] {
        snapshot.temperature = temperature
        #expect(snapshot.heatTone == tone)
        #expect(snapshot.memoryTone == .calm)
    }
    snapshot.temperature = nil; snapshot.thermal = "Serious"
    #expect(snapshot.heatTone == .risk)
    snapshot.thermal = "Unavailable"; #expect(snapshot.heatTone == .unavailable)
    snapshot.cpu = nil; #expect(snapshot.cpuTone == .unavailable)
    snapshot.cpu = 90; #expect(snapshot.cpuTone == .warm)
    snapshot.diskFree = 1; #expect(snapshot.diskTone == .risk)
    snapshot.diskFree = nil; #expect(snapshot.diskTone == .unavailable)
    snapshot.swapGrowthTenMinutes = 2_000_000_000
    #expect(snapshot.memoryTone == .warm)
}
