import Foundation
import Flutter
final class LegacyWavCapture {
    var callback: FlutterResult?
    func start(path: String, result: @escaping FlutterResult) { callback = result }
    func stop() { let c = callback; callback = nil; c?(FlutterError(code:"cancelled",message:nil,details:nil)) }
    func status() -> [String:Any] { ["recording":false] }
}
final class GovarUnifiedAudio {
    static var selected = true, custom = true, deferStops = false
    static var starts: [(NSError?) -> Void] = []
    static var stops: [() -> Void] = []
    static func diagnostics() -> [String:Any] {
        ["factorySelected":selected,"customDevice":custom,"deviceInitialized":true,"recording":true]
    }
    static func startRecording(path: String, completion: @escaping (NSError?) -> Void) { starts.append(completion) }
    static func stopRecording(completion: @escaping () -> Void) {
        if deferStops { stops.append(completion) } else { completion() }
    }
    static func clear() { starts=[];stops=[];selected=true;custom=true;deferStops=false }
}
let directory=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
func path(_ name: String) -> String { directory+"/"+name+".wav" }
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until:Date().addingTimeInterval(seconds)) }
// Stop while native start is still pending must complete the Flutter call once.
GovarUnifiedAudio.clear()
do {
    let capture=NativeWavCapture();var results=0;var stopped=false
    capture.start(path:path("cancel")) { value in results += 1; assert(value is FlutterError) }
    assert(GovarUnifiedAudio.starts.count==1)
    capture.stop { stopped=true }
    assert(stopped && results==1)
    GovarUnifiedAudio.starts[0](nil)
    assert(results==1)
}
print("PASS: cancelled custom start completes once; stale success ignored")
// An older asynchronous stop/start cannot overwrite a newer pending request.
GovarUnifiedAudio.clear()
do {
    let capture=NativeWavCapture();var initial=0;var a=0;var b=0
    capture.start(path:path("initial")) { _ in initial += 1 }
    GovarUnifiedAudio.starts.removeFirst()(nil);assert(initial==1)
    GovarUnifiedAudio.deferStops=true
    capture.start(path:path("a")) { value in a += 1;assert(value is FlutterError) }
    assert(GovarUnifiedAudio.stops.count==1)
    capture.start(path:path("b")) { value in b += 1;assert(!(value is FlutterError)) }
    GovarUnifiedAudio.stops.removeFirst()()
    assert(a==1 && b==0)
    GovarUnifiedAudio.starts.removeFirst()(nil)
    assert(a==1 && b==1)
    GovarUnifiedAudio.deferStops=false;capture.stop()
}
print("PASS: rapid stop/restart keeps latest capture and completes superseded request")
// Selection must settle before deciding to use the independent legacy recorder.
GovarUnifiedAudio.clear()
do {
    let capture=NativeWavCapture();var calls=0
    GovarUnifiedAudio.selected=false
    capture.start(path:path("wait")) { _ in calls += 1 }
    assert(GovarUnifiedAudio.starts.isEmpty)
    GovarUnifiedAudio.selected=true;pump(0.15)
    assert(GovarUnifiedAudio.starts.count==1)
    GovarUnifiedAudio.starts.removeFirst()(nil);assert(calls==1);capture.stop()
}
print("PASS: waits for factory selection; no parallel recorder before custom device")
// Legacy cancellation must reach Dart despite the wrapper's generation change.
GovarUnifiedAudio.clear()
do {
    GovarUnifiedAudio.custom=false
    let capture=NativeWavCapture();var calls=0
    capture.start(path:path("fallback")) { value in calls += 1;assert(value is FlutterError) }
    capture.stop();assert(calls==1)
}
print("PASS: stock fallback cancellation still completes Flutter result")
