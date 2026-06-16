import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/screens/settings/stores/settings_store.dart';
import 'package:frosty/screens/settings/widgets/settings_list_select.dart';
import 'package:frosty/screens/settings/widgets/settings_list_switch.dart';
import 'package:frosty/screens/settings/widgets/settings_string_list_editor.dart';
import 'package:frosty/services/stream_proxy_config.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/settings_page_layout.dart';

class VideoSettings extends StatelessWidget {
  final SettingsStore settingsStore;

  const VideoSettings({super.key, required this.settingsStore});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => SettingsPageLayout(
        children: [
          const SectionHeader('Player', isFirst: true),
          SettingsListSwitch(
            title: 'Show video player',
            value: settingsStore.showVideo,
            onChanged: (newValue) => settingsStore.showVideo = newValue,
          ),
          SettingsListSwitch(
            title: 'Default to highest quality',
            value: settingsStore.defaultToHighestQuality,
            onChanged: (newValue) =>
                settingsStore.defaultToHighestQuality = newValue,
          ),
          SettingsListSwitch(
            title: 'Use fast video rendering',
            subtitle: const Text(
              'Uses a faster WebView rendering method. Disable if you experience crashes while watching streams.',
            ),
            value: settingsStore.useTextureRendering,
            onChanged: (newValue) =>
                settingsStore.useTextureRendering = newValue,
          ),
          SettingsListSelect(
            title: 'Stream proxy mode',
            selectedOption:
                streamProxyModeNames[settingsStore.streamProxyMode.index],
            options: streamProxyModeNames,
            onChanged: (selectedOption) {
              final selectedIndex = streamProxyModeNames.indexOf(
                selectedOption,
              );
              if (selectedIndex == -1) return;

              settingsStore.streamProxyMode =
                  StreamProxyMode.values[selectedIndex];
            },
          ),
          if (settingsStore.streamProxyMode == StreamProxyMode.ttvLolPro) ...[
            SettingsStringListEditor(
              title: 'Proxy URLs',
              subtitle: 'Used for eligible livestream playback requests.',
              emptyMessage: 'No proxy URLs',
              hintText: 'proxy.example.com:3128',
              values: settingsStore.streamProxyUrls,
              validator: validateStreamProxyUrl,
              onChanged: (values) {
                settingsStore.streamProxyUrls = values
                    .map((value) => value.trim())
                    .where((value) => value.isNotEmpty)
                    .toList();
              },
            ),
            SettingsStringListEditor(
              title: 'Whitelisted channels',
              subtitle: 'Channels that should always load direct.',
              emptyMessage: 'No whitelisted channels',
              hintText: 'streamer_name123',
              values: settingsStore.streamProxyWhitelistedChannels,
              validator: validateStreamProxyChannelLogin,
              normalizeValue: (value) => value.trim().toLowerCase(),
              onChanged: (values) {
                settingsStore.streamProxyWhitelistedChannels = values
                    .map((value) => value.trim().toLowerCase())
                    .where((value) => value.isNotEmpty)
                    .toList();
              },
            ),
          ],
          const SectionHeader('Casting'),
          _CastModeSetting(settingsStore: settingsStore),
          if (settingsStore.castMode == CastMode.lowLatency && kDebugMode) ...[
            const SectionHeader('Advanced / Debug'),
            _SettingsTextFieldTile(
              title: 'External WebRTC Gateway URL override',
              subtitle:
                  'Optional MediaMTX base URL for external gateway testing.',
              value: settingsStore.webRtcGatewayUrl,
              hintText: 'https://media.example.com',
              validator: validateOptionalWebRtcUrl,
              onChanged: (value) =>
                  settingsStore.webRtcGatewayUrl = value.trim(),
            ),
            _SettingsTextFieldTile(
              title: 'WHEP URL override',
              subtitle: 'Optional full WHEP URL for this stream.',
              value: settingsStore.whepUrlOverride,
              hintText: 'https://media.example.com/channel/whep',
              validator: validateOptionalWebRtcUrl,
              onChanged: (value) =>
                  settingsStore.whepUrlOverride = value.trim(),
            ),
            SettingsListSwitch(
              title: 'Auto fallback to Stable HLS',
              subtitle: const Text(
                'Switches this cast to Stable HLS if the phone WebRTC gateway fails to start.',
              ),
              value: settingsStore.webRtcAutoFallback,
              onChanged: (newValue) =>
                  settingsStore.webRtcAutoFallback = newValue,
            ),
          ],
          const SectionHeader('Overlay'),
          SettingsListSwitch(
            title: 'Use custom video overlay',
            subtitle: const Text(
              'Replaces Twitch\'s default web overlay with a mobile-friendly version.',
            ),
            value: settingsStore.showOverlay,
            onChanged: (newValue) => settingsStore.showOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Toggle overlay on long-press',
            subtitle: const Text(
              'Switch between Twitch\'s overlay and the custom overlay.',
            ),
            value: settingsStore.toggleableOverlay,
            onChanged: (newValue) => settingsStore.toggleableOverlay = newValue,
          ),
          SettingsListSwitch(
            title: 'Show latency',
            subtitle: const Text(
              'Displays the stream latency in the video overlay.',
            ),
            value: settingsStore.showLatency,
            onChanged: (newValue) => settingsStore.showLatency = newValue,
          ),
        ],
      ),
    );
  }
}

class _CastModeSetting extends StatelessWidget {
  final SettingsStore settingsStore;

  const _CastModeSetting({required this.settingsStore});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListTile(title: Text('Cast Mode')),
        const ListTile(
          title: Text('Stable HLS'),
          subtitle: Text(
            'Most reliable. Higher latency, lowest chance of buffering.',
          ),
        ),
        SettingsListSwitch(
          title: 'Low Latency',
          subtitle: const Text(
            'WebRTC-based. Runs a local gateway on this phone for lower latency. Uses significantly more battery and may make the phone warm. Keep your phone plugged in for long casts.',
          ),
          value: settingsStore.castMode == CastMode.lowLatency,
          onChanged: (enabled) {
            settingsStore.castMode = enabled
                ? CastMode.lowLatency
                : CastMode.stableHls;
          },
        ),
      ],
    );
  }
}

class _SettingsTextFieldTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final String hintText;
  final ValueChanged<String> onChanged;
  final String? Function(String value) validator;

  const _SettingsTextFieldTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.hintText,
    required this.onChanged,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim();

    return ListTile(
      leading: const Icon(Icons.link_rounded),
      trailing: const Icon(Icons.edit),
      title: Text(title),
      subtitle: Text(displayValue.isEmpty ? subtitle : displayValue),
      onTap: () => _showEditor(context),
    );
  }

  Future<void> _showEditor(BuildContext context) async {
    final controller = TextEditingController(text: value);
    String? errorText;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void save() {
            final error = validator(controller.text);
            if (error != null) {
              setState(() => errorText = error);
              return;
            }

            onChanged(controller.text);
            Navigator.of(context).pop();
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                hintText: hintText,
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) {
                  setState(() => errorText = null);
                }
              },
              onSubmitted: (_) => save(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(onPressed: save, child: const Text('Save')),
            ],
          );
        },
      ),
    );

    controller.dispose();
  }
}
