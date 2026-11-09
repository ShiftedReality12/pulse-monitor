import SwiftUI
import PulseCore

/// Optional per-account usage from the user's own usage reader; the model is empty and the strip absent when none is installed.
struct UsageStrip: View {
    let model: UsageModel
    var body: some View {
        if model.available {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Account usage", systemImage: "chart.bar.xaxis").font(.headline)
                    Spacer()
                    if let checked = model.checkedAt { Text("Checked " + checked.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
                }
                if model.accounts.isEmpty {
                    Text(model.failed ? "The usage reader returned nothing readable." : "Reading usage…").font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(Array(model.accounts.enumerated()), id: \.offset) { AccountCard(account: $0.element) }
                    }
                }
            }.modifier(ContentCard(inset: 16))
        }
    }
}
private struct AccountCard: View {
    let account: UsageAccount
    private var tint: Color {
        switch account.status { case .ok: .green; case .watch: .orange; case .limit: .red; case .unavailable: .secondary }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(account.name).font(.callout.weight(.semibold)).lineLimit(1)
            }
            if account.windows.isEmpty { Text(account.problem ?? "No usage reported").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            ForEach(account.windows, id: \.label) { window in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(window.labelName).font(.caption.weight(.medium))
                        Spacer(minLength: 6)
                        Text("\(window.usedPercent)% used").font(.caption.monospacedDigit())
                    }
                    ProgressView(value: Double(min(100, window.usedPercent)), total: 100).tint(window.usedPercent >= 100 ? .red : window.usedPercent >= 80 ? .orange : .teal)
                    Text("resets in " + window.resets).font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(account.notes, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
            HStack {
                Text(account.status.rawValue).font(.caption2.weight(.semibold)).foregroundStyle(tint)
                if let updated = account.updated { Text("· updated " + updated).font(.caption2).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(tint.opacity(0.07), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.18)))
            .accessibilityElement(children: .combine)
    }
}
