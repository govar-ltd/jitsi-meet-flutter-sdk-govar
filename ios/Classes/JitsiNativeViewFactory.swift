import UIKit
import Flutter
import JitsiMeetSDK

enum FeatureFlags: CaseIterable {
    case welcomePageEnabled
    case audioFocusDisabled
    case addPeopleEnabled
    case audioMuteButtonEnabled
    case audioOnlyButtonEnabled
    case calendarEnabled
    case callIntegrationEnabled
    case carModeEnabled
    case closeCaptionsEnabled
    case conferenceTimerEnabled
    case chatEnabled
    case filmstripEnabled
    case fullScreenEnabled
    case helpButtonEnabled
    case inviteEnabled
    case androidScreenSharingEnabled
    case speakerStatsEnabled
    case kickOutEnabled
    case liveStreamingEnabled
    case lobbyModeEnabled
    case meetingNameEnabled
    case meetingPasswordEnabled
    case notificationEnabled
    case overflowMenuEnabled
    case pipEnabled
    case pipWhileScreenSharingEnabled
    case preJoinPageEnabled
    case preJoinPageHideDisplayName
    case raiseHandEnabled
    case reactionsEnabled
    case recordingEnabled
    case replaceParticipant
    case securityOptionEnabled
    case serverUrlChangeEnabled
    case settingsEnabled
    case tileViewEnabled
    case videoMuteEnabled
    case videoShareEnabled
    case toolboxEnabled
    case resolution
    case unsafeRoomWarningEnabled
    case iosRecordingEnabled
    case iosScreenSharingEnabled
    case toolboxAlwaysVisible
    
    var value: String {
        switch self {
        case .welcomePageEnabled: return "welcomepage.enabled"
        case .audioFocusDisabled: return "audio-focus.disabled"
        case .addPeopleEnabled: return "add-people.enabled"
        case .audioMuteButtonEnabled: return "audio-mute.enabled"
        case .audioOnlyButtonEnabled: return "audio-only.enabled"
        case .calendarEnabled: return "calendar.enabled"
        case .callIntegrationEnabled: return "call-integration.enabled"
        case .carModeEnabled: return "car-mode.enabled"
        case .closeCaptionsEnabled: return "close-captions.enabled"
        case .conferenceTimerEnabled: return "conference-timer.enabled"
        case .chatEnabled: return "chat.enabled"
        case .filmstripEnabled: return "filmstrip.enabled"
        case .fullScreenEnabled: return "fullscreen.enabled"
        case .helpButtonEnabled: return "help.enabled"
        case .inviteEnabled: return "invite.enabled"
        case .androidScreenSharingEnabled: return "android.screensharing.enabled"
        case .speakerStatsEnabled: return "speakerstats.enabled"
        case .kickOutEnabled: return "kick-out.enabled"
        case .liveStreamingEnabled: return "live-streaming.enabled"
        case .lobbyModeEnabled: return "lobby-mode.enabled"
        case .meetingNameEnabled: return "meeting-name.enabled"
        case .meetingPasswordEnabled: return "meeting-password.enabled"
        case .notificationEnabled: return "notifications.enabled"
        case .overflowMenuEnabled: return "overflow-menu.enabled"
        case .pipEnabled: return "pip.enabled"
        case .pipWhileScreenSharingEnabled: return "pip-while-screen-sharing.enabled"
        case .preJoinPageEnabled: return "prejoinpage.enabled"
        case .preJoinPageHideDisplayName: return "prejoinpage.hideDisplayName"
        case .raiseHandEnabled: return "raise-hand.enabled"
        case .reactionsEnabled: return "reactions.enabled"
        case .recordingEnabled: return "recording.enabled"
        case .replaceParticipant: return "replace.participant"
        case .securityOptionEnabled: return "security-options.enabled"
        case .serverUrlChangeEnabled: return "server-url-change.enabled"
        case .settingsEnabled: return "settings.enabled"
        case .tileViewEnabled: return "tile-view.enabled"
        case .videoMuteEnabled: return "video-mute.enabled"
        case .videoShareEnabled: return "video-share.enabled"
        case .toolboxEnabled: return "toolbox.enabled"
        case .resolution: return "resolution"
        case .unsafeRoomWarningEnabled: return "unsaferoomwarning.enabled"
        case .iosRecordingEnabled: return "ios.recording.enabled"
        case .iosScreenSharingEnabled: return "ios.screensharing.enabled"
        case .toolboxAlwaysVisible: return "toolbox.alwaysVisible"
        }
    }
}

class JitsiNativeViewFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger
    private var eventSinkProvider: () -> FlutterEventSink?
    private weak var plugin: JitsiMeetPlugin?
    
    init(messenger: FlutterBinaryMessenger, eventSinkProvider: @escaping () -> FlutterEventSink?, plugin: JitsiMeetPlugin?) {
        self.messenger = messenger
        self.eventSinkProvider = eventSinkProvider
        self.plugin = plugin
        super.init()
    }
    
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let arguments = args as! [String: Any]
        let roomUrl = arguments["room"] as! String
        
        let options = try! JitsiMeetConferenceOptions.createConferenceOptions(from: roomUrl)
        
        let view = JitsiNativeView(
            options: options,
            eventSink: eventSinkProvider()
        )
        
        plugin?.jitsiNativeViewCreated(view)
        
        return view
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

extension JitsiMeetConferenceOptions {
    static func createConferenceOptions(from urlString: String) throws -> JitsiMeetConferenceOptions {
        guard
            let encodedString = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: encodedString)
        else {
            throw NSError(domain: "Invalid URL", code: -1, userInfo: nil)
        }
        
        let host = url.host ?? ""
        let domain = url.port != nil ? "\(host):\(url.port!)" : host
        let room = url.pathComponents.last(where: { !$0.isEmpty }) ?? ""
        
        if room.isEmpty {
            throw NSError(domain: "Invalid room name", code: -1, userInfo: nil)
        }

        let builder = JitsiMeetConferenceOptions.fromBuilder { (builder) in
            builder.serverURL = URL(string: "https://\(domain)")
            builder.room = room
            
            var displayName: String? = nil
            var email: String? = nil
            var avatar: URL? = nil
            
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems {
                
                for item in queryItems {
                    let key = item.name
                    let value = item.value ?? ""
                    
                    if key.starts(with: "token") {
                        switch key {
                        case "token":
                            builder.token = value
                        default:
                            break
                        }
                    } else if key.starts(with: "userInfo.") {
                        // 🔹 User Info
                        switch key {
                            case "userInfo.displayName":
                                displayName = value
                            case "userInfo.email":
                                email = value
                            case "userInfo.avatar":
                                avatar = URL(string: value)
                        default:
                            break
                        }
                    } else if key.starts(with: "config.") {
                        switch key {
                        // 🔹 Audio & video
                        case "config.startWithAudioMuted":
                            builder.setAudioMuted(value == "true")
                            builder.setConfigOverride("startWithAudioMuted", withBoolean: (value == "true"))
                        case "config.startWithVideoMuted":
                            builder.setVideoMuted(value == "true")
                            builder.setConfigOverride("startWithVideoMuted", withBoolean: (value == "true"))
                        case "config.audioOnly":
                            builder.setAudioOnly(value == "true")
                        // 🔹 Toolbar Buttons
                        case "config.toolbarButtons":
                            let webButtons = value
                                .decodeJSONString()
                                .replacingOccurrences(of: "[", with: "")
                                .replacingOccurrences(of: "]", with: "")
                                .split(separator: ",")
                                .map { String($0).trimmingCharacters(in: .whitespaces) }
                            
                            let featureFlags: [String: String] = [
                                "microphone": "audio-mute.enabled",
                                "camera": "video-mute.enabled",
                                "desktop": "ios.screensharing.enabled",
                                "chat": "chat.enabled",
                                "raisehand": "raise-hand.enabled",
                                "participants-pane": "participants.enabled",
                                "tileview": "tile-view.enabled",
                                "toggle-camera": "toggle-camera-button.enabled",
                                "invite": "invite.enabled",
                                "fullscreen": "fullscreen.enabled",
                                "security": "security-options.enabled",
                                "closedcaptions": "close-captions.enabled",
                                "recording": "ios.recording.enabled",
                                "highlight": "reactions.enabled",
                                "livestreaming": "live-streaming.enabled",
                                "sharedvideo": "video-share.enabled",
                                "shareaudio": "audio-only.enabled",
                                "noisesuppression": "audio-device-button.enabled",
                                "whiteboard": "etherpad.enabled",
                                "etherpad": "etherpad.enabled",
                                "undock-iframe": "pip.enabled",
                                "dock-iframe": "pip.enabled",
                                "settings": "settings.enabled",
                                "stats": "speakerstats.enabled",
                                "shortcuts": "shortcuts.enabled",
                                "embedmeeting": "embedmeeting.enabled",
                                "feedback": "feedback.enabled",
                                "download": "download.enabled",
                                "help": "help.enabled",
                                "filmstrip": "filmstrip.enabled",
                                "carmode": "car-mode.enabled",
                                "breakout-rooms": "breakout-rooms.enabled"
                            ]
                            
                            featureFlags.forEach { button, flag in
                                builder.setFeatureFlag(flag, withValue: webButtons.contains(button))
                            }
                            
                            let supportedButtons = [
                                "microphone",
                                "camera",
                                "chat",
                                "hangup",
                                "profile",
                                "raisehand",
                                "tile-view",
                                "security",
                                "closedcaptions"
                            ]
                            
                            let iosButtons = webButtons
                                .filter { supportedButtons.contains($0) }
                                .map { $0 == "toggle-camera" ? "camera" : $0 }
                            
                            builder.setConfigOverride("toolbarButtons", withValue: iosButtons)
                        // 🔹 setFeatureFlag
                        case "config.prejoinPageEnabled":
                            builder.setFeatureFlag("prejoinPageEnabled", withValue: (value == "true"))
                        case "config.disableInviteFunctions":
                            builder.setFeatureFlag("invite.enabled", withValue: !(value == "true"))
                        case "config.chatEnabled":
                            builder.setFeatureFlag("chat.enabled", withValue: (value == "true"))
                        case "config.lobbyModeEnabled":
                            builder.setFeatureFlag("lobby.enabled", withValue: (value == "true"))
                        case "config.raiseHandEnabled":
                            builder.setFeatureFlag("raise-hand.enabled", withValue: (value == "true"))
                        case "config.tileViewEnabled":
                            builder.setFeatureFlag("tile-view.enabled", withValue: (value == "true"))
                        case "config.videoShareButtonEnabled":
                            builder.setFeatureFlag("video-share.enabled", withValue: (value == "true"))
                        // 🔹 setConfigOverride
                        case "config.disableTileView":
                            builder.setConfigOverride("disableTileView", withBoolean: (value == "true"))
                        case "config.enableNoAudioDetection":
                            builder.setConfigOverride("enableNoAudioDetection", withBoolean: (value == "true"))
                        case "config.enableNoisyMicDetection":
                            builder.setConfigOverride("enableNoisyMicDetection", withBoolean: (value == "true"))
                        case "config.enableClosePage":
                            builder.setConfigOverride("enableClosePage", withBoolean: (value == "true"))
                        case "config.disableRemoteMute":
                            builder.setConfigOverride("disableRemoteMute", withBoolean: (value == "true"))
                        case "config.disableSelfView":
                            builder.setConfigOverride("disableSelfView", withBoolean: (value == "true"))
                        case "config.defaultLanguage":
                            builder.setConfigOverride("defaultLanguage", withValue: value)
                        default:
                            break
                        }
                    } else if key.starts(with: "interfaceConfigOverwrite.") {
                        switch key {
                            // 🔹 InterfaceConfigOverwrite
                            case "interfaceConfigOverwrite.TOOLBAR_ALWAYS_VISIBLE":
                                builder.setConfigOverride("toolbarAlwaysVisible", withValue: value == "true")
                            case "interfaceConfigOverwrite.DISABLE_JOIN_LEAVE_NOTIFICATIONS":
                                builder.setConfigOverride("disableJoinLeaveNotifications", withValue: value == "true")
                            case "interfaceConfigOverwrite.SHOW_JITSI_WATERMARK":
                                builder.setConfigOverride("showJitsiWatermark", withBoolean: value == "true")
                            case "interfaceConfigOverwrite.SHOW_WATERMARK_FOR_GUESTS":
                                builder.setConfigOverride("showWatermarkForGuests", withBoolean: value == "true")
                        default:
                            break
                        }
                    } else {
                        if let featureFlag = FeatureFlags.allCases.first(where: { "\($0)" == key }) {
                            if value == "true" || value == "false" {
                                    builder.setFeatureFlag(featureFlag.value, withValue: value == "true")
                                    print(value == "true")
                                } else {
                                    builder.setFeatureFlag(featureFlag.value, withValue: value)
                                }
                        } else {
                            builder.setFeatureFlag(key, withValue: value == "true")
                        }
                    }
                }
            }
            
            let userInfo = JitsiMeetUserInfo(
                displayName: displayName,
                andEmail: email,
                andAvatar: avatar
            )
            builder.userInfo = userInfo
        }
        
        return builder
    }

}

extension String {
    
    func decodeJSONString() -> String {
        let percentDecoded = self.removingPercentEncoding ?? self
        let result = percentDecoded.replacingOccurrences(of: "\"", with: "")
        return result
    }

}
