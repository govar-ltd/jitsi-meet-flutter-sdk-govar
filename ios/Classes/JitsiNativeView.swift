import UIKit
import Flutter
import JitsiMeetSDK

class JitsiNativeView: UIView, FlutterPlatformView {
    func view() -> UIView { self }
    
    var jitsiMeetView: JitsiMeetView?
    fileprivate var pipViewCoordinator: PiPViewCoordinator?
    fileprivate var wrapperJitsiMeetView: UIView?
    fileprivate let options: JitsiMeetConferenceOptions
    fileprivate let eventSink: FlutterEventSink?
    
    init(options: JitsiMeetConferenceOptions, eventSink: FlutterEventSink?) {
        self.options = options
        self.eventSink = eventSink
        super.init(frame: .zero)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = CGRect(origin: .zero, size: bounds.size)
        pipViewCoordinator?.resetBounds(bounds: rect)
    }
    
    private func setupView() {
        openJitsiMeet()
    }
    
    private func openJitsiMeet() {
        cleanUp()
        
        jitsiMeetView = JitsiMeetView()
        jitsiMeetView?.frame = bounds
        let wrapperJitsiMeetView = WrapperView()
        wrapperJitsiMeetView.backgroundColor = .black
        wrapperJitsiMeetView.frame = bounds
        self.wrapperJitsiMeetView = wrapperJitsiMeetView
        
        addSubview(wrapperJitsiMeetView)
        self.wrapperJitsiMeetView?.addSubview(jitsiMeetView!)
        
        jitsiMeetView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        jitsiMeetView?.delegate = self
        jitsiMeetView?.join(options)
        
        pipViewCoordinator = PiPViewCoordinator(withView: wrapperJitsiMeetView)
        pipViewCoordinator?.configureAsStickyView(withParentView: self)
        pipViewCoordinator?.show()
    }
    
    private func cleanUp() {
        jitsiMeetView?.removeFromSuperview()
        wrapperJitsiMeetView?.removeFromSuperview()
        jitsiMeetView = nil
        wrapperJitsiMeetView = nil
        pipViewCoordinator = nil
    }
}

extension JitsiNativeView: JitsiMeetViewDelegate {
    func conferenceJoined(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "conferenceJoined", "data": data])
    }
    
    func conferenceTerminated(_ data: [AnyHashable: Any]) {
        eventSink?(["event": "conferenceTerminated", "data": data])
    }
    
    func conferenceWillJoin(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "conferenceWillJoin", "data": data])
    }
    
    func participantJoined(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "participantJoined", "data": data])
    }
    
    func participantLeft(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "participantLeft", "data": data])
    }
    
    func audioMutedChanged(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "audioMutedChanged", "data": data])
    }
    
    func videoMutedChanged(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "videoMutedChanged", "data": data])
    }
    
    func endpointTextMessageReceived(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "endpointTextMessageReceived", "data": data])
    }
    
    func screenShareToggled(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "screenShareToggled", "data": data])
    }
    
    func chatMessageReceived(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "chatMessageReceived", "data": data])
    }
    
    func chatToggled(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "chatToggled", "data": data])
    }
    
    func participantsInfoRetrieved(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "participantsInfoRetrieved", "data": data])
    }
    
    func customButtonPressed(_ data: [AnyHashable : Any]) {
        eventSink?(["event": "customButtonPressed", "data": data])
    }
    
    func ready(toClose data: [AnyHashable : Any]) {
        eventSink?(["event": "readyToClose"])
        DispatchQueue.main.async { [weak self] in
            self?.cleanUp()
        }
    }
    
    func enterPicture(inPicture data: [AnyHashable : Any]!) {
        DispatchQueue.main.async { [weak self] in
            self?.pipViewCoordinator?.enterPictureInPicture()
        }
    }
}

class WrapperView: UIView {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    }
}
