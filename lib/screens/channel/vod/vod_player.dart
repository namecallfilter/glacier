import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/emotes.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/models/vod_comment.dart';
import 'package:frosty/screens/channel/chat/stores/chat_assets_store.dart';
import 'package:frosty/screens/channel/video/cast_aware_pointer_blocker.dart';
import 'package:frosty/screens/channel/video/cast_button.dart';
import 'package:frosty/screens/channel/vod/stores/vod_chat_replay_store.dart';
import 'package:frosty/screens/channel/vod/stores/vod_player_store.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/services/cast_state.dart';
import 'package:frosty/services/stream_proxy_bridge.dart';
import 'package:frosty/theme.dart';
import 'package:frosty/utils.dart' as utils;
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/utils/modal_bottom_sheet.dart';
import 'package:frosty/widgets/draggable_divider.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/frosty_scrollbar.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:intl/intl.dart';
import 'package:mobx/mobx.dart';
import 'package:native_device_orientation/native_device_orientation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class VodPlayer extends StatefulWidget {
  static const routeName = 'VodPlayer';

  final TwitchVideo video;

  const VodPlayer({super.key, required this.video});

  @override
  State<VodPlayer> createState() => _VodPlayerState();
}

class _VodPlayerState extends State<VodPlayer> {
  late final VodPlayerStore _playerStore = VodPlayerStore(
    videoId: widget.video.id,
    userLogin: widget.video.userLogin,
    settingsStore: context.settingsStore,
  );
  late final VodChatReplayStore _chatReplayStore = VodChatReplayStore(
    twitchGqlApi: context.twitchGqlApi,
    videoId: widget.video.id,
  );
  late final ChatAssetsStore _chatAssetsStore = ChatAssetsStore(
    twitchApi: context.twitchApi,
    bttvApi: context.bttvApi,
    ffzApi: context.ffzApi,
    sevenTVApi: context.sevenTVApi,
    globalAssetsStore: context.globalAssetsStore,
  );

  ReactionDisposer? _positionReaction;
  var _hasLoadedInitialReplay = false;
  var _lastPosition = Duration.zero;
  var _isDividerDragging = false;
  var _chatAssetsInitialized = false;
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_playerStore.initializePlayer());
    unawaited(_initChatAssets());
  }

  Future<void> _initChatAssets() async {
    final authHeaders = context.authStore.headersTwitch;
    final settingsStore = context.settingsStore;

    await _chatAssetsStore.init();
    _chatAssetsInitialized = true;
    if (_disposed) {
      _chatAssetsStore.dispose();
      return;
    }

    List<Emote> onEmoteError(dynamic error) {
      debugPrint(error.toString());
      return <Emote>[];
    }

    List<ChatBadge> onBadgeError(dynamic error) {
      debugPrint(error.toString());
      return <ChatBadge>[];
    }

    await _chatAssetsStore.assetsFuture(
      channelId: widget.video.userId,
      headers: authHeaders,
      onEmoteError: onEmoteError,
      onBadgeError: onBadgeError,
      showTwitchEmotes: settingsStore.showTwitchEmotes,
      showTwitchBadges: settingsStore.showTwitchBadges,
      show7TVEmotes: settingsStore.show7TVEmotes,
      showBTTVEmotes: settingsStore.showBTTVEmotes,
      showBTTVBadges: settingsStore.showBTTVBadges,
      showFFZEmotes: settingsStore.showFFZEmotes,
      showFFZBadges: settingsStore.showFFZBadges,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _positionReaction ??= reaction((_) => _playerStore.currentPosition, (
      position,
    ) {
      unawaited(_syncReplay(position));
    });
  }

  Future<void> _syncReplay(Duration position) async {
    if (!_hasLoadedInitialReplay) {
      _hasLoadedInitialReplay = true;
      _lastPosition = position;
      await _chatReplayStore.loadAt(position);
      return;
    }

    final jump = (position.inSeconds - _lastPosition.inSeconds).abs();
    _lastPosition = position;

    if (jump > 15) {
      await _chatReplayStore.handleSeek(position);
      return;
    }

    final comments = _chatReplayStore.comments;
    if (comments.isEmpty || !_chatReplayStore.hasMoreComments) return;

    final lastBufferedOffset = comments.last.contentOffsetSeconds;
    if (lastBufferedOffset - position.inSeconds <= 30) {
      await _chatReplayStore.loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsStore = context.settingsStore;
    final player = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _playerStore.handleToggleOverlay,
      child: CastAwarePointerBlocker(
        child: VodVideo(
          playerStore: _playerStore,
          settingsStore: settingsStore,
        ),
      ),
    );

    final overlay = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _playerStore.handleToggleOverlay,
      onDoubleTap: context.isLandscape
          ? () => settingsStore.fullScreen = !settingsStore.fullScreen
          : null,
      onTap: _playerStore.handleVideoTap,
      child: Observer(
        builder: (_) {
          final videoOverlay = VodVideoOverlay(
            video: widget.video,
            playerStore: _playerStore,
            settingsStore: settingsStore,
          );

          if (_playerStore.paused || _playerStore.loading) {
            return ColoredBox(color: Colors.transparent, child: videoOverlay);
          }

          return AnimatedOpacity(
            opacity: _playerStore.overlayVisible ? 1.0 : 0.0,
            curve: Curves.ease,
            duration: const Duration(milliseconds: 200),
            child: ColoredBox(
              color: Colors.transparent,
              child: IgnorePointer(
                ignoring: !_playerStore.overlayVisible,
                child: videoOverlay,
              ),
            ),
          );
        },
      ),
    );

    final video = Stack(
      children: [
        Positioned.fill(child: player),
        Observer(
          builder: (context) => _playerStore.loading
              ? const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: Colors.white38,
                      strokeWidth: 2,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Observer(
          builder: (_) => settingsStore.showOverlay
              ? Positioned.fill(child: overlay)
              : const SizedBox.shrink(),
        ),
      ],
    );

    final chat = Observer(
      builder: (context) => VodReplayChat(
        store: _chatReplayStore,
        currentPosition: _playerStore.currentPosition,
        assetsStore: _chatAssetsStore,
      ),
    );

    return Scaffold(
      backgroundColor: settingsStore.showVideo
          ? Colors.black
          : context.scaffoldColor,
      body: Observer(
        builder: (context) {
          if (context.isLandscape &&
              !settingsStore.landscapeForceVerticalChat) {
            return _buildLandscapeLayout(
              settingsStore: settingsStore,
              video: video,
              chat: chat,
            );
          }

          return SafeArea(
            top: settingsStore.showVideo,
            bottom: false,
            child: settingsStore.showVideo
                ? Stack(
                    children: [
                      Column(
                        children: [
                          AspectRatio(aspectRatio: 16 / 9, child: Container()),
                          Expanded(
                            child: ColoredBox(
                              color: context.scaffoldColor,
                              child: chat,
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: AspectRatio(aspectRatio: 16 / 9, child: video),
                      ),
                    ],
                  )
                : chat,
          );
        },
      ),
    );
  }

  Widget _buildLandscapeLayout({
    required SettingsStore settingsStore,
    required Widget video,
    required Widget chat,
  }) {
    if (!settingsStore.showVideo) {
      return SafeArea(child: chat);
    }

    if (settingsStore.fullScreen) {
      final overlayChat = Visibility(
        visible: settingsStore.fullScreenChatOverlay,
        maintainState: true,
        child: Theme(
          data: FrostyThemes(
            colorSchemeSeed: Color(settingsStore.accentColor),
          ).dark,
          child: DefaultTextStyle(
            style: context.defaultTextStyle.copyWith(
              color: context.frostyColors.overlayOnSurface,
            ),
            child: Align(
              alignment: settingsStore.landscapeChatLeftSide
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: SizedBox(
                width: context.screenWidth * settingsStore.chatWidth,
                child: ColoredBox(
                  color: Colors.black.withValues(
                    alpha: settingsStore.fullScreenChatOverlayOpacity,
                  ),
                  child: chat,
                ),
              ),
            ),
          ),
        ),
      );

      return ColoredBox(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(child: video),
            Positioned.fill(child: overlayChat),
          ],
        ),
      );
    }

    return SafeArea(
      bottom: false,
      left:
          settingsStore.landscapeCutout != LandscapeCutoutType.left &&
          settingsStore.landscapeCutout != LandscapeCutoutType.both,
      right:
          settingsStore.landscapeCutout != LandscapeCutoutType.right &&
          settingsStore.landscapeCutout != LandscapeCutoutType.both,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final chatWidth = settingsStore.chatWidth;
          final chatContainer = AnimatedContainer(
            curve: Curves.ease,
            duration: _isDividerDragging
                ? Duration.zero
                : const Duration(milliseconds: 200),
            width: availableWidth * chatWidth,
            color: context.scaffoldColor,
            child: chat,
          );

          final draggableDivider = DraggableDivider(
            currentWidth: chatWidth,
            maxWidth: 0.6,
            isResizableOnLeft: settingsStore.landscapeChatLeftSide,
            showHandle: _playerStore.overlayVisible,
            onDragStart: () {
              setState(() {
                _isDividerDragging = true;
              });
            },
            onDrag: (newWidth) => settingsStore.chatWidth = newWidth,
            onDragEnd: () {
              setState(() {
                _isDividerDragging = false;
              });
            },
          );

          return Stack(
            children: [
              Row(
                children: settingsStore.landscapeChatLeftSide
                    ? [chatContainer, Expanded(child: video)]
                    : [Expanded(child: video), chatContainer],
              ),
              Positioned(
                top: 0,
                bottom: 0,
                left: settingsStore.landscapeChatLeftSide
                    ? (availableWidth * chatWidth) - 12
                    : null,
                right: !settingsStore.landscapeChatLeftSide
                    ? (availableWidth * chatWidth) - 12
                    : null,
                child: draggableDivider,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _positionReaction?.call();
    _playerStore.dispose();
    if (_chatAssetsInitialized) {
      _chatAssetsStore.dispose();
    }
    super.dispose();
  }
}

class VodVideo extends StatelessWidget {
  final VodPlayerStore playerStore;
  final SettingsStore settingsStore;

  const VodVideo({
    super.key,
    required this.playerStore,
    required this.settingsStore,
  });

  @override
  Widget build(BuildContext context) {
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      return WebViewWidget.fromPlatformCreationParams(
        params: AndroidWebViewWidgetCreationParams(
          controller: playerStore.videoWebViewController.platform,
          displayWithHybridComposition: !settingsStore.useTextureRendering,
        ),
      );
    }

    return WebViewWidget(controller: playerStore.videoWebViewController);
  }
}

class VodVideoOverlay extends StatelessWidget {
  final TwitchVideo video;
  final VodPlayerStore playerStore;
  final SettingsStore settingsStore;

  const VodVideoOverlay({
    super.key,
    required this.video,
    required this.playerStore,
    required this.settingsStore,
  });

  static BoxDecoration _overlayGradient({required bool fromTop}) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
          end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
          colors: const [
            Colors.black,
            Color.fromRGBO(0, 0, 0, 0.78),
            Color.fromRGBO(0, 0, 0, 0.48),
            Color.fromRGBO(0, 0, 0, 0.12),
            Colors.transparent,
          ],
          stops: const [0.0, 0.25, 0.5, 0.8, 1.0],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final surfaceColor = context.frostyColors.overlayOnSurface;

    final backButton = IconButton(
      tooltip: 'Back',
      icon: Icon(
        Icons.adaptive.arrow_back_rounded,
        color: surfaceColor,
        shadows: kOverlayShadow,
      ),
      onPressed: Navigator.of(context).pop,
    );

    final qualityButton = IconButton(
      tooltip: 'Quality',
      icon: Icon(Icons.settings, color: surfaceColor, shadows: kOverlayShadow),
      onPressed: () {
        playerStore.updateStreamQualities();
        showModalBottomSheetWithProperFocus(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                'Quality',
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                isFirst: true,
              ),
              Flexible(
                child: Observer(
                  builder: (_) => ListView(
                    shrinkWrap: true,
                    primary: false,
                    children: playerStore.availableStreamQualities
                        .map(
                          (quality) => ListTile(
                            trailing: playerStore.streamQuality == quality
                                ? const Icon(Icons.check_rounded)
                                : null,
                            title: Text(quality),
                            onTap: () {
                              playerStore.setStreamQuality(quality);
                              SharedPreferences.getInstance().then(
                                (prefs) => prefs.setString(
                                  lastStreamQualityKey(video.userLogin),
                                  quality,
                                ),
                              );
                              Navigator.pop(context);
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    final chatOverlayButton = Observer(
      builder: (_) => IconButton(
        tooltip: settingsStore.fullScreenChatOverlay
            ? 'Hide chat overlay'
            : 'Show chat overlay',
        onPressed: () => settingsStore.fullScreenChatOverlay =
            !settingsStore.fullScreenChatOverlay,
        icon: settingsStore.fullScreenChatOverlay
            ? Icon(Icons.chat_rounded, shadows: kOverlayShadow)
            : Icon(Icons.chat_outlined, shadows: kOverlayShadow),
        color: surfaceColor,
      ),
    );

    final refreshButton = ValueListenableBuilder<CastState>(
      valueListenable: StreamProxyBridge.castState,
      builder: (context, castState, _) => Tooltip(
        message: castState.isCasting ? 'Casting' : 'Refresh',
        preferBelow: false,
        child: IconButton(
          icon: Icon(
            Icons.refresh_rounded,
            color: castState.isCasting
                ? surfaceColor.withValues(alpha: 0.4)
                : surfaceColor,
            shadows: kOverlayShadow,
          ),
          onPressed: castState.isCasting ? null : playerStore.handleRefresh,
        ),
      ),
    );

    final fullScreenButton = IconButton(
      tooltip: settingsStore.fullScreen
          ? 'Exit fullscreen mode'
          : 'Enter fullscreen mode',
      icon: Icon(
        settingsStore.fullScreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        color: surfaceColor,
        shadows: kOverlayShadow,
      ),
      onPressed: () => settingsStore.fullScreen = !settingsStore.fullScreen,
    );

    final rotateButton = IconButton(
      tooltip: context.isPortrait
          ? 'Enter landscape mode'
          : 'Exit landscape mode',
      icon: Icon(
        Icons.screen_rotation_rounded,
        color: surfaceColor,
        shadows: kOverlayShadow,
      ),
      onPressed: () async {
        if (context.isPortrait) {
          final physicalOrientation =
              await NativeDeviceOrientationCommunicator().orientation(
                useSensor: true,
              );

          if (physicalOrientation == NativeDeviceOrientation.landscapeLeft) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
            ]);
          } else if (physicalOrientation ==
              NativeDeviceOrientation.landscapeRight) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeRight,
            ]);
          } else {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          }
        } else {
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          SystemChrome.setPreferredOrientations([]);
        }
      },
    );

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 100,
          child: Container(decoration: _overlayGradient(fromTop: true)),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(decoration: _overlayGradient(fromTop: false)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    backButton,
                    Flexible(
                      child: _VodInfoBar(video: video, textColor: surfaceColor),
                    ),
                  ],
                ),
              ),
            ),
            if (settingsStore.fullScreen && context.isLandscape)
              chatOverlayButton,
            CastButton(color: surfaceColor, shadows: kOverlayShadow),
            qualityButton,
          ],
        ),
        Center(
          child: ValueListenableBuilder<CastState>(
            valueListenable: StreamProxyBridge.castState,
            builder: (context, castState, _) {
              if (castState.isCasting) {
                return CastStatusButton(
                  castState: castState,
                  color: surfaceColor,
                  shadows: [
                    Shadow(
                      offset: const Offset(0, 3),
                      blurRadius: 8,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ],
                );
              }

              return Observer(
                builder: (_) => IconButton(
                  tooltip: playerStore.paused ? 'Play' : 'Pause',
                  iconSize: 56,
                  icon: Icon(
                    playerStore.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: surfaceColor,
                    shadows: [
                      Shadow(
                        offset: const Offset(0, 3),
                        blurRadius: 8,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                  onPressed: playerStore.handlePausePlay,
                ),
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    spacing: 10,
                    children: [
                      Flexible(
                        child: Observer(
                          builder: (_) => Text(
                            _formatPosition(
                              playerStore.currentPosition,
                              playerStore.duration,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: surfaceColor,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              shadows: kOverlayShadow,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        spacing: 4,
                        children: [
                          Icon(
                            Icons.visibility,
                            size: 14,
                            color: surfaceColor,
                            shadows: kOverlayShadow,
                          ),
                          Text(
                            NumberFormat().format(video.viewCount),
                            style: TextStyle(
                              color: surfaceColor,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              shadows: kOverlayShadow,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                refreshButton,
                rotateButton,
                if (context.isLandscape) fullScreenButton,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VodInfoBar extends StatelessWidget {
  final TwitchVideo video;
  final Color textColor;

  const _VodInfoBar({required this.video, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final secondaryColor = textColor.withValues(alpha: 0.7);

    return Row(
      spacing: 8,
      children: [
        ProfilePicture(userLogin: video.userLogin, radius: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: 4,
                children: [
                  Tooltip(
                    message: video.userName,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Text(
                      video.userName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        shadows: kOverlayShadow,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Tooltip(
                      message: video.title,
                      triggerMode: TooltipTriggerMode.tap,
                      child: Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: secondaryColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          shadows: kOverlayShadow,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(
                    Icons.movie_rounded,
                    size: 14,
                    color: secondaryColor,
                    shadows: kOverlayShadow,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Past broadcast',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondaryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        shadows: kOverlayShadow,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VodReplayChat extends StatefulWidget {
  final VodChatReplayStore store;
  final Duration currentPosition;
  final ChatAssetsStore assetsStore;

  const VodReplayChat({
    super.key,
    required this.store,
    required this.currentPosition,
    required this.assetsStore,
  });

  @override
  State<VodReplayChat> createState() => _VodReplayChatState();
}

class _VodReplayChatState extends State<VodReplayChat> {
  final _scrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final settingsStore = context.settingsStore;
    final visibleComments = widget.store.comments
        .where(
          (comment) =>
              comment.contentOffsetSeconds <=
              widget.currentPosition.inSeconds + 1,
        )
        .where((comment) => !_isMuted(comment.message.body, settingsStore))
        .toList();

    if (visibleComments.isEmpty) {
      final message =
          widget.store.error ??
          (widget.store.hasLoadedReplay
              ? widget.store.comments.isEmpty
                    ? 'No chat replay available'
                    : 'No chat yet'
              : 'Loading chat replay...');
      return Center(
        child: Text(message, style: TextStyle(color: context.bodySmallColor)),
      );
    }

    return MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: settingsStore.messageScale.textScaler),
      child: DefaultTextStyle(
        style: context.defaultTextStyle.copyWith(
          fontSize: settingsStore.fontSize,
        ),
        child: FrostyScrollbar(
          controller: _scrollController,
          child: ListView.builder(
            reverse: true,
            controller: _scrollController,
            padding: EdgeInsets.only(
              top: 8 + MediaQuery.of(context).padding.top,
              bottom: 8 + MediaQuery.of(context).padding.bottom,
            ),
            itemCount: visibleComments.length,
            itemBuilder: (context, index) {
              final comment =
                  visibleComments[visibleComments.length - 1 - index];
              return VodCommentTile(
                comment: comment,
                assetsStore: widget.assetsStore,
              );
            },
          ),
        ),
      ),
    );
  }

  bool _isMuted(String message, SettingsStore settingsStore) {
    final normalizedMutedWords = settingsStore.mutedWords
        .map((word) => word.trim().toLowerCase())
        .where((word) => word.isNotEmpty);
    if (normalizedMutedWords.isEmpty) return false;

    final normalizedMessage = message.toLowerCase();
    final words = settingsStore.matchWholeWord
        ? normalizedMessage.split(' ')
        : null;

    return normalizedMutedWords.any(
      (word) => words != null
          ? words.contains(word)
          : normalizedMessage.contains(word),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

class VodCommentTile extends StatelessWidget {
  static const _twitchEmoteBaseUrl =
      'https://static-cdn.jtvnw.net/emoticons/v2';
  static const _emoteModeSuffix = '/default/dark/3.0';

  final VodComment comment;
  final ChatAssetsStore? assetsStore;

  const VodCommentTile({super.key, required this.comment, this.assetsStore});

  @override
  Widget build(BuildContext context) {
    final settingsStore = context.settingsStore;
    final commenter = comment.commenter;
    final displayName = commenter?.displayName ?? 'Unknown';
    final textColor = _parseColor(context, comment.message.userColor);
    final nameColor = textColor ?? context.colorScheme.primary;
    final showTimestamp =
        settingsStore.timestampType != TimestampType.disabled ||
        settingsStore.showHistoricalTimestamps;

    final message = Padding(
      padding: EdgeInsets.only(
        top: settingsStore.messageSpacing / 2,
        bottom: settingsStore.messageSpacing / 2,
        left: 12,
        right: 12,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (showTimestamp)
              TextSpan(
                text: '${_formatOffset(comment.contentOffsetSeconds)} ',
                style: TextStyle(
                  color: context.bodySmallColor?.withValues(alpha: 0.55),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ..._buildBadges(context, settingsStore),
            TextSpan(
              text: displayName,
              style: TextStyle(color: nameColor, fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ': '),
            ..._buildFragments(context, settingsStore),
          ],
        ),
      ),
    );

    final content = settingsStore.showChatMessageDividers
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [message, const Divider()],
          )
        : message;

    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: comment.message.body));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Message copied')));
      },
      child: content,
    );
  }

  List<InlineSpan> _buildBadges(
    BuildContext context,
    SettingsStore settingsStore,
  ) {
    final assetsStore = this.assetsStore;
    if (!settingsStore.showTwitchBadges || assetsStore == null) {
      return const [];
    }

    final badgeSize = defaultBadgeSize * settingsStore.badgeScale;
    final spans = <InlineSpan>[];

    for (final badge in comment.message.userBadges) {
      final resolvedBadge =
          assetsStore.twitchBadgesToObject['${badge.setId}/${badge.version}'];
      if (resolvedBadge == null) continue;

      spans
        ..add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FrostyCachedNetworkImage(
              imageUrl: resolvedBadge.url,
              height: badgeSize,
              width: badgeSize,
              useFade: false,
            ),
          ),
        )
        ..add(const TextSpan(text: ' '));
    }

    return spans;
  }

  List<InlineSpan> _buildFragments(
    BuildContext context,
    SettingsStore settingsStore,
  ) {
    if (comment.message.fragments.isEmpty) {
      return _buildTextWithThirdPartyEmotes(
        context,
        comment.message.body,
        settingsStore,
      );
    }

    return comment.message.fragments.expand<InlineSpan>((fragment) {
      final emoteId = fragment.emoteId;
      if (emoteId == null || !settingsStore.showTwitchEmotes) {
        return _buildTextWithThirdPartyEmotes(
          context,
          fragment.text,
          settingsStore,
        );
      }

      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Image.network(
              '$_twitchEmoteBaseUrl/$emoteId$_emoteModeSuffix',
              height: defaultEmoteSize * settingsStore.emoteScale,
              errorBuilder: (context, error, stackTrace) => Text(fragment.text),
            ),
          ),
        ),
      ];
    }).toList();
  }

  List<InlineSpan> _buildTextWithThirdPartyEmotes(
    BuildContext context,
    String text,
    SettingsStore settingsStore,
  ) {
    final assetsStore = this.assetsStore;
    if (assetsStore == null || text.isEmpty) return [TextSpan(text: text)];

    final spans = <InlineSpan>[];
    final parts = text.split(' ');
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final emote = assetsStore.emoteToObject[part];

      if (emote != null && _shouldShowEmote(emote, settingsStore)) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: FrostyCachedNetworkImage(
              imageUrl: emote.url,
              height:
                  (emote.height ?? defaultEmoteSize) * settingsStore.emoteScale,
              width: emote.width == null
                  ? null
                  : emote.width! * settingsStore.emoteScale,
              useFade: false,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: part,
            style: part.startsWith('@')
                ? const TextStyle(fontWeight: FontWeight.bold)
                : null,
          ),
        );
      }

      if (i != parts.length - 1) {
        spans.add(const TextSpan(text: ' '));
      }
    }

    return spans;
  }

  bool _shouldShowEmote(Emote emote, SettingsStore settingsStore) {
    return switch (emote.type) {
      EmoteType.twitchGlobal ||
      EmoteType.twitchSub ||
      EmoteType.twitchUnlocked ||
      EmoteType.twitchBits ||
      EmoteType.twitchFollower ||
      EmoteType.twitchChannel => settingsStore.showTwitchEmotes,
      EmoteType.bttvGlobal ||
      EmoteType.bttvChannel ||
      EmoteType.bttvShared => settingsStore.showBTTVEmotes,
      EmoteType.ffzGlobal ||
      EmoteType.ffzChannel => settingsStore.showFFZEmotes,
      EmoteType.sevenTVGlobal ||
      EmoteType.sevenTVChannel => settingsStore.show7TVEmotes,
    };
  }

  Color? _parseColor(BuildContext context, String value) {
    if (!value.startsWith('#') || value.length != 7) return null;
    final parsed = int.tryParse(value.replaceFirst('#', '0xFF'));
    if (parsed == null) return null;
    return utils.adjustChatNameColor(context, Color(parsed));
  }

  String _formatOffset(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }
}

String _formatPosition(Duration position, Duration? duration) {
  String format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  if (duration == null || duration == Duration.zero) {
    return format(position);
  }

  return '${format(position)} / ${format(duration)}';
}

MaterialPageRoute<void> vodPlayerRoute(TwitchVideo video) {
  return MaterialPageRoute(
    settings: const RouteSettings(name: VodPlayer.routeName),
    builder: (context) => VodPlayer(video: video),
  );
}
