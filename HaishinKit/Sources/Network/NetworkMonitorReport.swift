import Foundation

/// The struct represents a network statistics.
public struct NetworkMonitorReport: Sendable {
    /// The statistics of total incoming bytes.
    public let totalBytesIn: Int
    /// The statistics of total outgoing bytes.
    public let totalBytesOut: Int
    /// The statistics of outgoing queue bytes per second.
    public let currentQueueBytesOut: Int
    /// The statistics of incoming bytes per second.
    public let currentBytesInPerSecond: Int
    /// The statistics of outgoing bytes per second.
    public let currentBytesOutPerSecond: Int
    /// TVC fork (link evidence): unique data packets sent since connect (0 = transport cannot say —
    /// RTMP). With `totalPacketsLost` it gives the loss the RECEIVER sees, which the send queue never
    /// shows when the bottleneck is further along the path than the phone's own socket.
    public var totalPacketsSent: Int = 0
    /// TVC fork (link evidence): packets reported lost by the receiver (SRT NAKs) since connect.
    public var totalPacketsLost: Int = 0
    /// TVC fork (link evidence): smoothed round-trip time in ms (0 = unknown).
    public var rttMs: Double = 0
}
