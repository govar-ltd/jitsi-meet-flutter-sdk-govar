@_exported import Foundation
public final class AVAudioSession {
    public struct PortType { public var rawValue: String = "test" }
    public struct Port { public var portType = PortType() }
    public struct Route { public var inputs: [Port] = []; public var outputs: [Port] = [] }
    public struct Category { public var rawValue = "playAndRecord" }
    public struct Mode { public var rawValue = "measurement" }
    public var category = Category(); public var mode = Mode(); public var sampleRate = 48000.0
    public var preferredSampleRate = 48000.0; public var inputNumberOfChannels = 1
    public var ioBufferDuration = 0.01; public var inputLatency = 0.01; public var currentRoute = Route()
    public static func sharedInstance() -> AVAudioSession { AVAudioSession() }
}
