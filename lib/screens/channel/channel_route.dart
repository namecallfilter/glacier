import 'package:flutter/material.dart';
import 'package:frosty/screens/channel/channel.dart';
import 'package:frosty/screens/channel/profile/channel_profile.dart';

MaterialPageRoute<void> videoChatRoute({
  required String userId,
  required String userName,
  required String userLogin,
}) {
  return MaterialPageRoute(
    settings: const RouteSettings(name: VideoChat.routeName),
    builder: (context) =>
        VideoChat(userId: userId, userName: userName, userLogin: userLogin),
  );
}

MaterialPageRoute<void> channelProfileRoute({
  required String userId,
  required String userName,
  required String userLogin,
}) {
  return MaterialPageRoute(
    settings: const RouteSettings(name: ChannelProfile.routeName),
    builder: (context) => ChannelProfile(
      userId: userId,
      userName: userName,
      userLogin: userLogin,
    ),
  );
}

void pushVideoChat(
  BuildContext context, {
  required String userId,
  required String userName,
  required String userLogin,
}) {
  Navigator.push(
    context,
    videoChatRoute(userId: userId, userName: userName, userLogin: userLogin),
  );
}

void pushChannelProfile(
  BuildContext context, {
  required String userId,
  required String userName,
  required String userLogin,
}) {
  Navigator.push(
    context,
    channelProfileRoute(
      userId: userId,
      userName: userName,
      userLogin: userLogin,
    ),
  );
}
