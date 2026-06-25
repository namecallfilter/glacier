import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/screens/channel/video/video_timing_constants.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

part 'vod_player_store.g.dart';

class VodPlayerStore = VodPlayerStoreBase with _$VodPlayerStore;

abstract class VodPlayerStoreBase with Store {
  final String videoId;
  final String userLogin;
  final SettingsStore settingsStore;

  Timer? _overlayTimer;
  late final ReactionDisposer _disposeOverlayReaction;
  var _firstTimeSettingQuality = true;

  VodPlayerStoreBase({
    required this.videoId,
    required this.userLogin,
    required this.settingsStore,
  }) {
    videoWebViewController = WebViewController()
      ..setBackgroundColor(Colors.black)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'StreamQualities',
        onMessageReceived: (message) async {
          final data = jsonDecode(message.message) as List;
          _availableStreamQualities = data
              .map((item) => item as String)
              .toList();

          if (_firstTimeSettingQuality) {
            _firstTimeSettingQuality = false;
            if (settingsStore.defaultToHighestQuality) {
              await _setStreamQualityIndex(1);
              return;
            }

            final prefs = await SharedPreferences.getInstance();
            final lastStreamQuality = prefs.getString(
              lastStreamQualityKey(userLogin),
            );
            if (lastStreamQuality != null) {
              await setStreamQuality(lastStreamQuality);
            }
          }
        },
      )
      ..addJavaScriptChannel(
        'VodPosition',
        onMessageReceived: (message) {
          final payload = jsonDecode(message.message) as Map;
          final currentTime = payload['currentTime'];
          final duration = payload['duration'];

          if (currentTime is num) {
            _currentPosition = Duration(
              milliseconds: (currentTime * 1000).round(),
            );
          }
          if (duration is num && duration.isFinite) {
            _duration = Duration(milliseconds: (duration * 1000).round());
          }
        },
      )
      ..addJavaScriptChannel(
        'VodPlaying',
        onMessageReceived: (_) {
          _loading = false;
          _paused = false;
        },
      )
      ..addJavaScriptChannel(
        'VodPaused',
        onMessageReceived: (_) => _paused = true,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (_isCurrentVideoUrl(url)) {
              unawaited(_initVideoTracking());
            }
          },
        ),
      );

    if (videoWebViewController.platform is AndroidWebViewController) {
      (videoWebViewController.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    _scheduleOverlayHide();
    _disposeOverlayReaction = reaction((_) => settingsStore.showOverlay, (
      showOverlay,
    ) async {
      if (showOverlay) {
        await _hideDefaultOverlay();
        await updateStreamQualities();
      } else {
        _showDefaultOverlay();
      }
    });
  }

  late final WebViewController videoWebViewController;

  String get videoUrl =>
      'https://player.twitch.tv/?autoplay=true&muted=false&parent=frosty&video=v$videoId';

  @readonly
  var _currentPosition = Duration.zero;

  @readonly
  Duration? _duration;

  @readonly
  var _loading = true;

  @readonly
  var _paused = true;

  @readonly
  var _overlayVisible = true;

  @readonly
  List<String> _availableStreamQualities = [];

  @readonly
  int _streamQualityIndex = 0;

  String get streamQuality =>
      _availableStreamQualities.elementAtOrNull(_streamQualityIndex) ?? 'Auto';

  Future<void> initializePlayer() async {
    await videoWebViewController.loadRequest(Uri.parse(videoUrl));
  }

  bool _isCurrentVideoUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'player.twitch.tv') return false;
    return uri.queryParameters['video'] == 'v$videoId';
  }

  Future<void> _initVideoTracking() async {
    try {
      await videoWebViewController.runJavaScript('''
        (() => {
          if (window._frostyVodTrackerStarted) return;
          window._frostyVodTrackerStarted = true;

          window._PROMISE_QUEUE = Promise.resolve();
          window._promiseQueueLength = 0;
          window._promiseQueueGen = 0;

          window._queuePromise = (method) => {
            window._promiseQueueLength++;
            if (window._promiseQueueLength > 30) {
              window._PROMISE_QUEUE = Promise.resolve();
              window._promiseQueueLength = 1;
              window._promiseQueueGen++;
            }

            const myGen = window._promiseQueueGen;
            window._PROMISE_QUEUE = window._PROMISE_QUEUE.then(async () => {
              try {
                await method();
              } catch (e) {
                console.warn('Queue promise error:', e);
              } finally {
                if (myGen === window._promiseQueueGen) {
                  window._promiseQueueLength--;
                }
              }
            });
            return window._PROMISE_QUEUE;
          };

          window._asyncQuerySelector = (selector, timeout = 10000) => new Promise((resolve) => {
            let element = document.querySelector(selector);
            if (element) return resolve(element);

            let timeoutId;
            const observer = new MutationObserver(() => {
              element = document.querySelector(selector);
              if (element) {
                observer.disconnect();
                clearTimeout(timeoutId);
                resolve(element);
              }
            });
            observer.observe(document.body, { childList: true, subtree: true });
            timeoutId = setTimeout(() => {
              observer.disconnect();
              resolve(undefined);
            }, timeout);
          });

          const postPosition = () => {
            const video = document.querySelector("video");
            if (!video || !window.VodPosition) return;
            VodPosition.postMessage(JSON.stringify({
              currentTime: video.currentTime || 0,
              duration: Number.isFinite(video.duration) ? video.duration : 0
            }));
          };

          const forceAudiblePlayback = (video) => {
            if (!video) return;

            video.muted = false;
            video.volume = 1.0;

            if (video.textTracks && video.textTracks.length > 0) {
              video.textTracks[0].mode = "hidden";
            }

            const unmuteButton = Array.from(
              document.querySelectorAll('button, [role="button"]')
            ).find((element) => {
              const label = (element.getAttribute('aria-label') || '').toLowerCase();
              const text = (element.textContent || '').toLowerCase();
              return label.includes('unmute') || text.includes('click to unmute');
            });

            if (unmuteButton) {
              try { unmuteButton.click(); } catch (_) {}
            }
          };

          const attach = () => {
            const video = document.querySelector("video");
            if (!video) return false;

            window._vodVideoEl = video;
            forceAudiblePlayback(video);
            if (!video._frostyVodListenersAdded) {
              video._frostyVodListenersAdded = true;
              video.addEventListener("playing", () => VodPlaying.postMessage("playing"));
              video.addEventListener("playing", () => forceAudiblePlayback(video));
              video.addEventListener("pause", () => VodPaused.postMessage("pause"));
              video.addEventListener("loadedmetadata", () => forceAudiblePlayback(video));
              video.addEventListener("seeked", postPosition);
            }

            postPosition();
            setInterval(postPosition, 1000);
            let audibleAttempts = 0;
            const audibleInterval = setInterval(() => {
              forceAudiblePlayback(video);
              audibleAttempts++;
              if (audibleAttempts >= 20) {
                clearInterval(audibleInterval);
              }
            }, 250);
            try {
              forceAudiblePlayback(video);
              video.play().catch(() => {});
            } catch (_) {}
            return true;
          };

          if (!attach()) {
            const observer = new MutationObserver(() => {
              if (attach()) observer.disconnect();
            });
            observer.observe(document.body, { childList: true, subtree: true });
            setTimeout(() => observer.disconnect(), 10000);
          }
        })();
      ''');
      if (settingsStore.showOverlay) {
        await _hideDefaultOverlay();
        await updateStreamQualities();
      }
    } catch (e) {
      debugPrint('VOD tracking init failed: $e');
    }
  }

  @action
  Future<void> updateStreamQualities() async {
    try {
      await videoWebViewController.runJavaScript(r'''
        _queuePromise(async () => {
          const settingsBtn = await _asyncQuerySelector('[data-a-target="player-settings-button"]');
          if (!settingsBtn) return;

          try {
            settingsBtn.click();

            const qualityItem = await _asyncQuerySelector('[data-a-target="player-settings-menu-item-quality"]');
            if (!qualityItem) return;
            qualityItem.click();

            await _asyncQuerySelector(
              '[data-a-target="player-settings-menu"] input[name="player-settings-submenu-quality-option"] + label'
            );

            const qualities = Array.from(
              document.querySelectorAll(
                '[data-a-target="player-settings-menu"] input[name="player-settings-submenu-quality-option"] + label'
              )
            ).map(l => l.textContent.replace(/\s+/g, ' ').trim());

            StreamQualities.postMessage(JSON.stringify(qualities));
          } finally {
            settingsBtn.click();
          }
        });
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @action
  Future<void> setStreamQuality(String newStreamQuality) async {
    final indexOfStreamQuality = _availableStreamQualities.indexOf(
      newStreamQuality,
    );
    if (indexOfStreamQuality == -1) return;
    await _setStreamQualityIndex(indexOfStreamQuality);
  }

  @action
  Future<void> _setStreamQualityIndex(int newStreamQualityIndex) async {
    try {
      await videoWebViewController.runJavaScript('''
        _queuePromise(async () => {
          const settingsBtn = await _asyncQuerySelector('[data-a-target="player-settings-button"]');
          if (!settingsBtn) return;

          try {
            settingsBtn.click();

            const qualityItem = await _asyncQuerySelector('[data-a-target="player-settings-menu-item-quality"]');
            if (!qualityItem) return;
            qualityItem.click();

            await _asyncQuerySelector('[data-a-target="player-settings-submenu-quality-option"] input');
            const inputs = [...document.querySelectorAll('[data-a-target="player-settings-submenu-quality-option"] input')];
            if (inputs[$newStreamQualityIndex]) {
              inputs[$newStreamQualityIndex].click();
            }
          } finally {
            settingsBtn.click();
          }
        });
      ''');
      _streamQualityIndex = newStreamQualityIndex;
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _hideDefaultOverlay() async {
    try {
      await videoWebViewController.runJavaScript('''
        {
          if (!document.getElementById('frosty-overlay-styles')) {
            const style = document.createElement('style');
            style.id = 'frosty-overlay-styles';
            style.textContent = `
              .top-bar,
              .player-controls,
              #channel-player-disclosures,
              [data-a-target="player-overlay-preview-background"],
              [data-a-target="player-overlay-video-stats"] {
                display: none !important;
                visibility: hidden !important;
                pointer-events: none !important;
              }
            `;
            document.head.appendChild(style);
          }
        }
      ''');
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _showDefaultOverlay() {
    try {
      videoWebViewController.runJavaScript(
        "document.getElementById('frosty-overlay-styles')?.remove();",
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @action
  void handleVideoTap() {
    _overlayTimer?.cancel();

    if (_overlayVisible) {
      _overlayVisible = false;
    } else {
      _overlayVisible = true;
      _scheduleOverlayHide();
    }
  }

  @action
  void handleToggleOverlay() {
    if (!settingsStore.toggleableOverlay) return;

    settingsStore.showOverlay = !settingsStore.showOverlay;
    if (settingsStore.showOverlay) {
      _overlayVisible = true;
      _scheduleOverlayHide(VideoTimingConstants.overlayQuickHide);
    }
  }

  @action
  Future<void> handleRefresh() async {
    _paused = true;
    _loading = true;
    _firstTimeSettingQuality = true;
    _availableStreamQualities = [];
    await videoWebViewController.loadRequest(Uri.parse(videoUrl));
  }

  void handlePausePlay() {
    try {
      if (_paused) {
        videoWebViewController.runJavaScript('''
            (() => {
              const video = window._vodVideoEl || document.getElementsByTagName("video")[0];
              if (!video) return;
              video.muted = false;
              video.volume = 1.0;
              video.play();
            })();
          ''');
      } else {
        videoWebViewController.runJavaScript(
          '(window._vodVideoEl || document.getElementsByTagName("video")[0])?.pause();',
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _scheduleOverlayHide([
    Duration delay = VideoTimingConstants.overlayAutoHide,
  ]) {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(delay, () {
      runInAction(() {
        _overlayVisible = false;
      });
    });
  }

  void dispose() {
    _overlayTimer?.cancel();
    _disposeOverlayReaction();
    videoWebViewController.loadRequest(Uri.parse('about:blank'));
  }
}
