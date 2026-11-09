import SwiftUI
import PulseCore

struct GlanceView: View {
    @Bindable var monitor: Monitor
    let openOverview: @MainActor () -> Void
    var body: some View {
        let _ = monitor.renderToken
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    VerdictHero(copy: monitor.verdict, compact: true)
                    VitalGrid(snapshot: monitor.snapshot, plots: monitor.plots, disk: monitor.disk, compact: true)
                    HStack {
                        Text("Biggest users").font(.headline)
                        Spacer()
                        Text("Resource use").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 6) {
                        if monitor.snapshot.groups.isEmpty { Text("Waiting for readable processes").foregroundStyle(.secondary) }
                        ForEach(Array(monitor.snapshot.groups.prefix(5))) { OwnerRow(group: $0, compact: true).equatable() }
                    }.renderBounds("culprits")
                    Text("Ranked by RAM, CPU and writes.\n" + HumanCopy.partialFootnote).font(.caption2).foregroundStyle(.secondary)
                }.padding(2)
            }.frame(height: 750).coordinateSpace(name: "glance-viewport").renderBounds("viewport")
            Divider()
            HStack(spacing: 8) {
                Button(action: openOverview) { Label("Open Pulse", systemImage: "arrow.up.forward.app").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 26) }
                    .buttonStyle(.glassProminent).tint(.accentColor).foregroundStyle(.white)
                SettingsLink { Image(systemName: "gearshape").frame(width: 26, height: 26) }.buttonStyle(.glass).accessibilityLabel("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power").frame(width: 26, height: 26) }.buttonStyle(.glass).accessibilityLabel("Quit Pulse")
            }.environment(\.appearsActive, true)
        }.padding(14).frame(width: 420)
            .onPreferenceChange(GlanceBoundsKey.self) { RenderDiagnostics.shared.captureBounds($0) }
            .onAppear { monitor.visibility("glance", shown: true) }.onDisappear { monitor.visibility("glance", shown: false) }
    }
}
