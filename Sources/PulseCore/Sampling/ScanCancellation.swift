import CSensors

/// One atomic flag crosses Swift Task cancellation and the serial/native scan loops.
final class ScanCancellation: @unchecked Sendable {
    let pointer = pulse_cancel_create()!
    var cancelled: Bool { pulse_cancelled(pointer) != 0 }
    func cancel() { pulse_cancel_set(pointer) }
    deinit { pulse_cancel_destroy(pointer) }
}
