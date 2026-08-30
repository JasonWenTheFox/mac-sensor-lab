import Darwin
import Foundation

struct NetworkCounterSample: Equatable {
  let activeInterfaceCount: Int
  let receivedBytes: UInt64
  let sentBytes: UInt64
  let receivedPackets: UInt64
  let sentPackets: UInt64
  let timestamp: TimeInterval
}

struct NetworkRates: Equatable {
  let receivedBytesPerSecond: Double
  let sentBytesPerSecond: Double
  let receivedPacketsPerSecond: Double
  let sentPacketsPerSecond: Double
}

enum NetworkRateCalculator {
  static func rates(previous: NetworkCounterSample, current: NetworkCounterSample) -> NetworkRates?
  {
    let elapsed = current.timestamp - previous.timestamp
    guard elapsed.isFinite, elapsed > 0,
      current.activeInterfaceCount == previous.activeInterfaceCount,
      current.receivedBytes >= previous.receivedBytes,
      current.sentBytes >= previous.sentBytes,
      current.receivedPackets >= previous.receivedPackets,
      current.sentPackets >= previous.sentPackets
    else { return nil }

    let rates = NetworkRates(
      receivedBytesPerSecond: Double(current.receivedBytes - previous.receivedBytes) / elapsed,
      sentBytesPerSecond: Double(current.sentBytes - previous.sentBytes) / elapsed,
      receivedPacketsPerSecond: Double(current.receivedPackets - previous.receivedPackets)
        / elapsed,
      sentPacketsPerSecond: Double(current.sentPackets - previous.sentPackets) / elapsed
    )
    guard rates.receivedBytesPerSecond.isFinite,
      rates.sentBytesPerSecond.isFinite,
      rates.receivedPacketsPerSecond.isFinite,
      rates.sentPacketsPerSecond.isFinite
    else { return nil }
    return rates
  }
}

public final class NetworkThroughputProvider: SensorProvider, @unchecked Sendable {
  public let metadata = SensorProviderMetadata(
    id: "system.network_throughput",
    name: "Network Throughput",
    category: .system,
    source: "BSD ifmib aggregate counters",
    capability: .publicAPI
  )

  private let lock = NSLock()
  private var previousSample: NetworkCounterSample?

  public init() {}

  public func read() async -> SensorSnapshot {
    guard let aggregate = Self.readAggregateCounters() else {
      return SensorSnapshot(
        id: metadata.id,
        name: metadata.name,
        category: metadata.category,
        summary: "Aggregate network counters were unavailable",
        status: .unavailable,
        source: metadata.source,
        capability: metadata.capability
      )
    }

    let current = NetworkCounterSample(
      activeInterfaceCount: aggregate.activeInterfaceCount,
      receivedBytes: aggregate.receivedBytes,
      sentBytes: aggregate.sentBytes,
      receivedPackets: aggregate.receivedPackets,
      sentPackets: aggregate.sentPackets,
      timestamp: ProcessInfo.processInfo.systemUptime
    )
    let rates = lock.withLock { () -> NetworkRates? in
      defer { previousSample = current }
      guard let previousSample else { return nil }
      return NetworkRateCalculator.rates(previous: previousSample, current: current)
    }

    var channels = [
      SensorChannel(
        id: "network_active_interfaces",
        label: "Active non-loopback interfaces",
        value: Double(aggregate.activeInterfaceCount),
        formattedValue: "\(aggregate.activeInterfaceCount)"
      ),
      Self.byteChannel("network_received_total", "Received total", aggregate.receivedBytes),
      Self.byteChannel("network_sent_total", "Sent total", aggregate.sentBytes),
    ]

    if let rates {
      channels += [
        Self.rateChannel("network_receive_rate", "Receive rate", rates.receivedBytesPerSecond),
        Self.rateChannel("network_send_rate", "Send rate", rates.sentBytesPerSecond),
        SensorChannel(
          id: "network_receive_packet_rate",
          label: "Receive packet rate",
          value: rates.receivedPacketsPerSecond,
          formattedValue: SensorFormatting.decimal(
            rates.receivedPacketsPerSecond, fractionDigits: 1),
          unit: "packets/s",
          kind: .derived
        ),
        SensorChannel(
          id: "network_send_packet_rate",
          label: "Send packet rate",
          value: rates.sentPacketsPerSecond,
          formattedValue: SensorFormatting.decimal(rates.sentPacketsPerSecond, fractionDigits: 1),
          unit: "packets/s",
          kind: .derived
        ),
      ]
    }

    let summary =
      if let rates {
        "↓ \(SensorFormatting.bytesPerSecond(rates.receivedBytesPerSecond)) • ↑ \(SensorFormatting.bytesPerSecond(rates.sentBytesPerSecond))"
      } else {
        "Collecting throughput baseline • \(aggregate.activeInterfaceCount) active interfaces"
      }

    return SensorSnapshot(
      id: metadata.id,
      name: metadata.name,
      category: metadata.category,
      summary: summary,
      status: .available,
      source: metadata.source,
      capability: metadata.capability,
      channels: channels,
      notes: [
        "Rates need two samples; the first read or an active-interface count change establishes a baseline.",
        "Virtual or tunneled paths can represent the same traffic more than once.",
      ]
    )
  }

  private struct AggregateCounters {
    let activeInterfaceCount: Int
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let receivedPackets: UInt64
    let sentPackets: UInt64
  }

  private static func readAggregateCounters() -> AggregateCounters? {
    var interfaceCount: Int32 = 0
    var countSize = MemoryLayout<Int32>.size
    var countMIB = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_SYSTEM, IFMIB_IFCOUNT]
    guard sysctl(&countMIB, UInt32(countMIB.count), &interfaceCount, &countSize, nil, 0) == 0
    else { return nil }

    var activeCount = 0
    var receivedBytes: UInt64 = 0
    var sentBytes: UInt64 = 0
    var receivedPackets: UInt64 = 0
    var sentPackets: UInt64 = 0

    for index in 1..<max(Int(interfaceCount) + 1, 1) {
      var data = ifmibdata()
      var dataSize = MemoryLayout<ifmibdata>.size
      var interfaceMIB = [
        CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL,
      ]
      guard sysctl(&interfaceMIB, UInt32(interfaceMIB.count), &data, &dataSize, nil, 0) == 0
      else { continue }
      let flags = Int32(bitPattern: data.ifmd_flags)
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

      guard
        let nextReceivedBytes = SensorNumericSafety.sum(
          receivedBytes, data.ifmd_data.ifi_ibytes),
        let nextSentBytes = SensorNumericSafety.sum(sentBytes, data.ifmd_data.ifi_obytes),
        let nextReceivedPackets = SensorNumericSafety.sum(
          receivedPackets, data.ifmd_data.ifi_ipackets),
        let nextSentPackets = SensorNumericSafety.sum(sentPackets, data.ifmd_data.ifi_opackets)
      else { return nil }
      activeCount += 1
      receivedBytes = nextReceivedBytes
      sentBytes = nextSentBytes
      receivedPackets = nextReceivedPackets
      sentPackets = nextSentPackets
    }

    return AggregateCounters(
      activeInterfaceCount: activeCount,
      receivedBytes: receivedBytes,
      sentBytes: sentBytes,
      receivedPackets: receivedPackets,
      sentPackets: sentPackets
    )
  }

  private static func byteChannel(_ id: String, _ label: String, _ value: UInt64) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: Double(value),
      formattedValue: SensorFormatting.bytes(value),
      unit: "bytes"
    )
  }

  private static func rateChannel(_ id: String, _ label: String, _ value: Double) -> SensorChannel {
    SensorChannel(
      id: id,
      label: label,
      value: value,
      formattedValue: SensorFormatting.bytesPerSecond(value),
      unit: "bytes/s",
      kind: .derived
    )
  }
}
