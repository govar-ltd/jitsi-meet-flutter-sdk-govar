@_exported import Foundation
public typealias FlutterResult = (Any?) -> Void
public final class FlutterError: Error {
    public let code: String
    public init(code: String, message: String?, details: Any?) { self.code = code }
}
