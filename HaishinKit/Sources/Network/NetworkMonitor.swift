import Foundation

/// An objec thatt provides the RTMPConnection, SRTConnection's monitoring events.
package final actor NetworkMonitor {
    /// The error domain codes.
    public enum Error: Swift.Error {
        /// An invalid internal stare.
        case invalidState
    }

    /// An asynchronous sequence for network monitoring  event.
    public var event: AsyncStream<NetworkMonitorEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    public private(set) var isRunning = false
    private var timer: Task<Void, Never>? {
        didSet {
            oldValue?.cancel()
        }
    }
    private var measureInterval = 3
    private var currentBytesInPerSecond = 0
    private var currentBytesOutPerSecond = 0
    private var previousTotalBytesIn = 0
    private var previousTotalBytesOut = 0
    private var previousQueueBytesOut: [Int] = []
    // TVC fork (trigger 2): consecutive-increase run tracking — see collect(). The run can be
    // longer than the 3-sample window above, so it needs its own anchor.
    private var lastQueueBytesOut: Int?
    private var runStartQueueBytesOut: Int?
    private var continuation: AsyncStream<NetworkMonitorEvent>.Continuation? {
        didSet {
            oldValue?.finish()
        }
    }
    private weak var reporter: (any NetworkTransportReporter)?

    /// Creates a new instance.
    package init(_ reporter: some NetworkTransportReporter) {
        self.reporter = reporter
    }

    private func collect() async throws -> NetworkMonitorEvent {
        guard let report = await reporter?.makeNetworkTransportReport() else {
            throw Error.invalidState
        }
        let totalBytesIn = report.totalBytesIn
        let totalBytesOut = report.totalBytesOut
        let queueBytesOut = report.queueBytesOut
        currentBytesInPerSecond = totalBytesIn - previousTotalBytesIn
        currentBytesOutPerSecond = totalBytesOut - previousTotalBytesOut
        previousTotalBytesIn = totalBytesIn
        previousTotalBytesOut = totalBytesOut
        previousQueueBytesOut.append(queueBytesOut)
        let eventReport = NetworkMonitorReport(
            totalBytesIn: totalBytesIn,
            totalBytesOut: totalBytesOut,
            currentQueueBytesOut: queueBytesOut,
            currentBytesInPerSecond: currentBytesInPerSecond,
            currentBytesOutPerSecond: currentBytesOutPerSecond
        )
        // TVC fork: direction alone is not congestion — magnitude is. Two triggers, each blind
        // where the other sees:
        //
        // 1. WINDOWED — the 3-sample window (spanning TWO 1s intervals) must be strictly
        //    increasing AND have grown by max(egress/8, 16KB) across the window. Because the
        //    window is two seconds wide, that is an effective per-second threshold of egress/16
        //    (an earlier comment called it "an eighth of a second's egress", which was 2x looser
        //    than the arithmetic — the /8 floor is cleared by a per-second deficit of egress/16).
        //    With a 1s GOP sampled at this monitor's 1 Hz cadence the send queue is a sawtooth
        //    whose sampled value can walk upward in tiny strictly-increasing steps for many
        //    consecutive samples (clock drift slides the sample phase along the sawtooth), which
        //    used to read here as sustained congestion on links with proven headroom. Real
        //    congestion accumulates backlog at the capacity-deficit rate and clears this floor
        //    within the window; keyframe-phase ripple never does.
        //
        // 2. RUN-CUMULATIVE — trigger 1 is blind to slow creep: a steady capacity deficit under
        //    ~egress/16 per second keeps the queue strictly increasing yet never clears the
        //    per-window floor, and with no other congestion signal on this platform (no loss/RTT
        //    visibility, ratio classifier not wired) the SRT buffer eventually overflows into
        //    TLPKTDROP with no ABR response. So track the consecutive-increase RUN across
        //    collect() calls: once the queue has grown monotonically since the run began by
        //    max(egress/4, 64KB) in total, report congestion no matter how small each step was.
        //    Keyframe-phase sawtooth walks cannot reach this floor — a walk's total rise is
        //    bounded by one I-frame (~15-25% of a second's bits at a 1s GOP), so a cumulative
        //    floor worth 250ms of egress stays out of their reach, while true creep accumulates
        //    without bound and crosses it in ~0.25/deficit seconds. The run resets whenever a
        //    sample fails to increase.
        if let last = lastQueueBytesOut, queueBytesOut > last {
            if runStartQueueBytesOut == nil {
                runStartQueueBytesOut = last
            }
        } else {
            runStartQueueBytesOut = nil
        }
        lastQueueBytesOut = queueBytesOut
        var congested = false
        if measureInterval <= previousQueueBytesOut.count {
            defer {
                previousQueueBytesOut.removeFirst()
            }
            var total = 0
            for i in 0..<previousQueueBytesOut.count - 1 where previousQueueBytesOut[i] < previousQueueBytesOut[i + 1] {
                total += 1
            }
            if total == measureInterval - 1 {
                let growth = (previousQueueBytesOut.last ?? 0) - (previousQueueBytesOut.first ?? 0)
                let windowFloor = max(currentBytesOutPerSecond / 8, 16_384)
                congested = growth >= windowFloor
            }
        }
        if !congested, let runStart = runStartQueueBytesOut {
            let cumulativeFloor = max(currentBytesOutPerSecond / 4, 65_536)
            congested = queueBytesOut - runStart >= cumulativeFloor
        }
        if congested {
            return .publishInsufficientBWOccured(report: eventReport)
        }
        return .status(report: eventReport)
    }
}

extension NetworkMonitor: AsyncRunner {
    // MARK: AsyncRunner
    package func startRunning() {
        guard !isRunning else {
            return
        }
        isRunning = true
        timer = Task {
            let timer = AsyncStream {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            for await _ in timer {
                do {
                    let event = try await collect()
                    continuation?.yield(event)
                } catch {
                    continuation?.finish()
                }
            }
        }
    }

    package func stopRunning() {
        guard isRunning else {
            return
        }
        isRunning = false
        timer = nil
        continuation = nil
        // TVC fork: a run must not span two publish sessions — a stale anchor from the previous
        // session's queue level would make the first samples of the next one look like growth.
        lastQueueBytesOut = nil
        runStartQueueBytesOut = nil
    }
}
