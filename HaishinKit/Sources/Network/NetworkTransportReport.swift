import Foundation

/// A structure that represents a network transport bitRate statics.
package struct NetworkTransportReport: Sendable {
    /// The statistics of outgoing queue bytes per second.
    package let queueBytesOut: Int
    /// The statistics of incoming bytes per second.
    package let totalBytesIn: Int
    /// The statistics of outgoing bytes per second.
    package let totalBytesOut: Int
    /// TVC fork (link evidence): unique data packets sent since connect (0 = transport cannot say).
    package let totalPacketsSent: Int
    /// TVC fork (link evidence): packets the RECEIVER reported lost (NAKs) since connect.
    package let totalPacketsLost: Int
    /// TVC fork (link evidence): the transport's smoothed round-trip time in ms (0 = unknown).
    package let rttMs: Double

    /// Creates a new instance.
    package init(queueBytesOut: Int, totalBytesIn: Int, totalBytesOut: Int,
                 totalPacketsSent: Int = 0, totalPacketsLost: Int = 0, rttMs: Double = 0) {
        self.queueBytesOut = queueBytesOut
        self.totalBytesIn = totalBytesIn
        self.totalBytesOut = totalBytesOut
        self.totalPacketsSent = totalPacketsSent
        self.totalPacketsLost = totalPacketsLost
        self.rttMs = rttMs
    }
}
