import 'package:flutter/material.dart';
import 'package:jitsi_meet_govar_flutter_sdk/jitsi_meet_govar_flutter_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _jitsiMeetPlugin = JitsiMeet();

  final _jitsiMeetListener = JitsiMeetEventListener(
    conferenceJoined: (url) {
      debugPrint("conferenceJoined: url: $url");
    },
    conferenceTerminated: (url, error) {
      debugPrint("conferenceTerminated: url: $url, error: $error");
    },
    conferenceWillJoin: (url) {
      debugPrint("conferenceWillJoin: url: $url");
    },
    participantJoined: (email, name, role, participantId) {
      debugPrint(
        "participantJoined: email: $email, name: $name, role: $role, "
            "participantId: $participantId",
      );
    },
    participantLeft: (participantId) {
      debugPrint("participantLeft: participantId: $participantId");
    },
    audioMutedChanged: (muted) {
      debugPrint("audioMutedChanged: isMuted: $muted");
    },
    videoMutedChanged: (muted) {
      debugPrint("videoMutedChanged: isMuted: $muted");
    },
    endpointTextMessageReceived: (senderId, message) {
      debugPrint(
          "endpointTextMessageReceived: senderId: $senderId, message: $message");
    },
    screenShareToggled: (participantId, sharing) {
      debugPrint(
        "screenShareToggled: participantId: $participantId, "
            "isSharing: $sharing",
      );
    },
    chatMessageReceived: (senderId, message, isPrivate, timestamp) {
      debugPrint(
        "chatMessageReceived: senderId: $senderId, message: $message, "
            "isPrivate: $isPrivate, timestamp: $timestamp",
      );
    },
    chatToggled: (isOpen) => debugPrint("chatToggled: isOpen: $isOpen"),
    participantsInfoRetrieved: (participantsInfo) {
      debugPrint(
          "participantsInfoRetrieved: participantsInfo: $participantsInfo, ");
    },
    readyToClose: () {
      debugPrint("readyToClose");
    },
    bottomViewTapped: () {
      debugPrint("bottomViewTapped");
    },
    changeRoomTapped: () {
      debugPrint("changeRoomTapped");
    },
    saveResultsTapped: () {
      debugPrint("saveResultsTapped");
    },
    getTopicTapped: () {
      debugPrint("getTopicTapped");
    },
    customButtonPressed: (buttonId) {
      debugPrint("customButtonPressed: buttonId: $buttonId");
    },
  );

  @override
  void initState() {
    super.initState();
    _jitsiMeetPlugin.join(_jitsiMeetListener);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: const Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(
              width: double.infinity,
              height: 600,
              child: JitsiMeetWidget(room: 'https://meet.govar.online:9443/govar_speaking_club?config.toolbarButtons=["microphone","chat","raisehand","participants-pane","toggle-camera","noisesuppression","embedmeeting"]&userInfo.displayName=anton&userInfo.email=mahyk92@gmail.com&userInfo.avatar=https://firebasestorage.googleapis.com/v0/b/govar-72b4b.appspot.com/o/users%2FsS6iSKZIXjN01EI6VrjB4dAzotH2%2Fuploads%2F1738329112589358.jpg?alt=media&token=92f7158b-b6ab-46e3-b5ec-7855ad13a991&config.startWithVideoMuted=true&notificationEnabled=false'),
            ),
            SizedBox(
              width: double.infinity,
              height: 150,
              child: Text('Bottom bar'),
            )
          ],
        ),
      ),
    );
  }
}