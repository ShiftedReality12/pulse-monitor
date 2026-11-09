import SwiftUI
import PulseCore

struct ProcessList: View {
    let groups: [ProcessGroup]
    var metric: ProcessMetric?
    var trends: [String: [PlotPoint]] = [:]
    var sampledAt: Date?
    @State private var sort = Sort.impact
    @State private var search = ""
    enum Sort: String, CaseIterable {
        case impact = "Impact", cpu = "CPU", ram = "RAM", name = "Owner", category = "Category", count = "Process count", launcher = "Started by", writes = "Writes"
        func ordered(_ a: ProcessGroup, _ b: ProcessGroup) -> Bool {
            switch self {
            case .impact: a.impact == b.impact ? a.id < b.id : a.impact > b.impact
            case .cpu: (a.cpu ?? -1) > (b.cpu ?? -1)
            case .ram: (a.resident ?? 0) > (b.resident ?? 0)
            case .name: a.title < b.title
            case .category: a.category < b.category
            case .count: a.members.count > b.members.count
            case .launcher: (a.launcher ?? "") < (b.launcher ?? "")
            case .writes: (a.writesPerSecond ?? -1) > (b.writesPerSecond ?? -1)
            }
        }
    }
    private var filtered: [ProcessGroup] {
        let matches = groups.filter { search.isEmpty || "\($0.title) \($0.explanation) \($0.runningReason)".localizedCaseInsensitiveContains(search) }
        return metric?.ranked(matches) ?? matches.sorted(by: sort.ordered)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Find an app, session or process", text: $search).textFieldStyle(.roundedBorder)
                if metric == nil { Picker("Sort by", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.frame(width: 210) }
            }.padding(.horizontal, 24).padding(.top, 16)
            Text("\(filtered.count) owners · CPU is per core · " + HumanCopy.partialFootnote).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filtered) { group in
                        OwnerDisclosure(group: group, metric: metric)
                        if let metric, let points = trends[group.id], let sampledAt { OwnerSparkline(points: points, now: sampledAt, metric: metric) }
                    }
                    if filtered.isEmpty { ContentUnavailableView("No matching owners", systemImage: "magnifyingglass", description: Text("Try another name, or wait for readable process data.")) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
    }
}
