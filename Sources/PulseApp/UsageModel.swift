import Foundation
import Observation
import PulseCore

/// Display-only copy of the optional usage reader. Refreshes at most once a minute, only while the window is open.
@MainActor @Observable final class UsageModel {
    private(set) var accounts: [UsageAccount] = []
    private(set) var available = false
    private(set) var failed = false
    private(set) var checkedAt: Date?
    private var task: Task<Void, Never>?
    func refreshIfDue(provider: UsageStripProvider?, now: Date = Date()) {
        guard let provider else {
            if available || !accounts.isEmpty { available = false; accounts = []; failed = false; checkedAt = nil }
            return
        }
        if !available { available = true }
        guard task == nil, checkedAt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return }
        checkedAt = now
        task = Task { [weak self] in
            let result = await provider.report()
            guard let self else { return }
            task = nil
            if let result, !result.isEmpty { accounts = result; failed = false } else { accounts = []; failed = true } // never show old percentages under a fresh timestamp
        }
    }
}
