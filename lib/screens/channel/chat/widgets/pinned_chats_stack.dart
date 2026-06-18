import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/badges.dart';
import 'package:frosty/models/emotes.dart';
import 'package:frosty/models/irc.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class PinnedChatsStack extends StatefulWidget {
  static const topOffset = 5.0;
  static const collapsedHeight = 96.0;
  static const expandedHeight = 154.0;

  final List<PinnedChatMessage> pinnedChats;
  final Map<String, ChatBadge> twitchBadges;
  final Map<String, Emote> emoteToObject;
  final bool launchExternal;
  final void Function(String id) onDismiss;

  const PinnedChatsStack({
    super.key,
    required this.pinnedChats,
    this.twitchBadges = const {},
    this.emoteToObject = const {},
    required this.launchExternal,
    required this.onDismiss,
  });

  @override
  State<PinnedChatsStack> createState() => _PinnedChatsStackState();
}

class _PinnedChatsStackState extends State<PinnedChatsStack> {
  final _toggledPinIds = <String>{};

  @override
  void didUpdateWidget(PinnedChatsStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final visiblePinIds = widget.pinnedChats.map((pin) => pin.id).toSet();
    _toggledPinIds.removeWhere((id) => !visiblePinIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pinnedChats.isEmpty) return const SizedBox.shrink();

    final topPin = widget.pinnedChats.first;
    final canToggleTopPin = _canTogglePinnedChat(topPin.messageText);
    final startsMinimized = _shouldStartMinimized(topPin.messageText);
    final isToggled = _toggledPinIds.contains(topPin.id);
    final isTopPinExpanded =
        canToggleTopPin && (startsMinimized ? isToggled : !isToggled);
    final stackHeight = isTopPinExpanded
        ? PinnedChatsStack.expandedHeight
        : PinnedChatsStack.collapsedHeight;

    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      clipBehavior: Clip.none,
      child: SizedBox(
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 8,
              right: 8,
              top: 0,
              child: _PinnedChatCard(
                pin: topPin,
                twitchBadges: widget.twitchBadges,
                emoteToObject: widget.emoteToObject,
                launchExternal: widget.launchExternal,
                canToggle: canToggleTopPin,
                isExpanded: isTopPinExpanded,
                onToggle: () => _togglePinnedChat(topPin),
                onDismiss: () => widget.onDismiss(topPin.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _togglePinnedChat(PinnedChatMessage pin) {
    setState(() {
      if (_toggledPinIds.contains(pin.id)) {
        _toggledPinIds.remove(pin.id);
      } else {
        _toggledPinIds.add(pin.id);
      }
    });
  }
}

class _PinnedChatCard extends StatelessWidget {
  final PinnedChatMessage pin;
  final Map<String, ChatBadge> twitchBadges;
  final Map<String, Emote> emoteToObject;
  final bool launchExternal;
  final bool canToggle;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;

  const _PinnedChatCard({
    required this.pin,
    required this.twitchBadges,
    required this.emoteToObject,
    required this.launchExternal,
    required this.canToggle,
    required this.isExpanded,
    required this.onToggle,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final actionsWidth = canToggle ? 64.0 : 32.0;
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.86),
      fontWeight: FontWeight.w700,
    );

    return Material(
      color: _pinnedSurfaceColor(context),
      elevation: 5,
      shadowColor: Colors.black.withValues(alpha: 0.32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(right: actionsWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.push_pin_rounded,
                    size: 18,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PinnedHeaderLine(
                          pin: pin,
                          twitchBadges: twitchBadges,
                          launchExternal: launchExternal,
                          style: headerStyle,
                        ),
                        const SizedBox(height: 4),
                        _PinnedMessageText(
                          text: pin.messageText,
                          fragments: pin.fragments,
                          emoteToObject: emoteToObject,
                          launchExternal: launchExternal,
                          breakLongLinks: isExpanded,
                          maxLines: canToggle ? (isExpanded ? 5 : 1) : 2,
                          overflow: canToggle && !isExpanded
                              ? TextOverflow.ellipsis
                              : TextOverflow.clip,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            height: 1.24,
                          ),
                        ),
                        if (!canToggle || isExpanded) ...[
                          const SizedBox(height: 5),
                          _PinnedSenderLine(
                            pin: pin,
                            twitchBadges: twitchBadges,
                            launchExternal: launchExternal,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.78,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: -6,
              right: -2,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canToggle)
                    _PinnedIconButton(
                      onPressed: onToggle,
                      icon: Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                      tooltip: isExpanded
                          ? 'Collapse pinned chat'
                          : 'Expand pinned chat',
                      iconSize: 20,
                    ),
                  _PinnedIconButton(
                    onPressed: onDismiss,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Dismiss pinned chat',
                    iconSize: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final String tooltip;
  final double iconSize;

  const _PinnedIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: icon,
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      iconSize: iconSize,
    );
  }
}

class _PinnedHeaderLine extends StatelessWidget {
  final PinnedChatMessage pin;
  final Map<String, ChatBadge> twitchBadges;
  final bool launchExternal;
  final TextStyle? style;

  const _PinnedHeaderLine({
    required this.pin,
    required this.twitchBadges,
    required this.launchExternal,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final pinnedByName = pin.pinnedByDisplayName ?? 'moderator';
    final badges = _resolvedPinnedBadges(
      pin.pinnedByBadges,
      twitchBadges,
      authorityOnly: true,
    );

    if (badges.isEmpty) {
      return Text(
        'Pinned by $pinnedByName',
        overflow: TextOverflow.visible,
        softWrap: true,
        style: style,
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Pinned by ', style: style),
        _PinnedBadgeNameRun(
          badges: badges,
          name: pinnedByName,
          badgeSize: 14,
          launchExternal: launchExternal,
          style: style,
        ),
      ],
    );
  }
}

class _PinnedBadgeNameRun extends StatelessWidget {
  final List<ChatBadge> badges;
  final String name;
  final double badgeSize;
  final bool launchExternal;
  final TextStyle? style;

  const _PinnedBadgeNameRun({
    required this.badges,
    required this.name,
    required this.badgeSize,
    required this.launchExternal,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final badgeNameRun = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final badge in badges)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: _PinnedBadgeButton(
              badge: badge,
              size: badgeSize,
              launchExternal: launchExternal,
            ),
          ),
        Text(
          name,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: style,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return badgeNameRun;

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: constraints.maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: badgeNameRun,
          ),
        );
      },
    );
  }
}

class _PinnedSenderLine extends StatelessWidget {
  final PinnedChatMessage pin;
  final Map<String, ChatBadge> twitchBadges;
  final bool launchExternal;
  final TextStyle? style;

  const _PinnedSenderLine({
    required this.pin,
    required this.twitchBadges,
    required this.launchExternal,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final badges = _resolvedPinnedBadges(pin.senderBadges, twitchBadges);
    final sentAt = pin.sentAt == null
        ? null
        : DateFormat.jm().format(pin.sentAt!.toLocal());

    if (badges.isEmpty) {
      return Text(
        sentAt == null
            ? pin.senderDisplayName
            : '${pin.senderDisplayName} sent at $sentAt',
        overflow: TextOverflow.visible,
        softWrap: true,
        style: style,
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PinnedBadgeNameRun(
          badges: badges,
          name: pin.senderDisplayName,
          badgeSize: 16,
          launchExternal: launchExternal,
          style: style,
        ),
        if (sentAt != null) Text(' sent at $sentAt', style: style),
      ],
    );
  }
}

class _PinnedMessageText extends StatelessWidget {
  final String text;
  final List<PinnedChatFragment> fragments;
  final Map<String, Emote> emoteToObject;
  final bool launchExternal;
  final bool breakLongLinks;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const _PinnedMessageText({
    required this.text,
    this.fragments = const [],
    this.emoteToObject = const {},
    required this.launchExternal,
    this.breakLongLinks = false,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _buildSpans(context)),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  List<InlineSpan> _buildSpans(BuildContext context) {
    final spans = <InlineSpan>[];
    if (fragments.isNotEmpty) {
      for (final fragment in fragments) {
        final emote = fragment.emote;
        if (emote != null) {
          final resolvedEmote = emoteToObject[emote.text];
          spans.add(
            _PinnedEmoteSpan(
              text: emote.text,
              imageUrl: resolvedEmote?.url ?? emote.imageUrl,
              emote: resolvedEmote,
              launchExternal: launchExternal,
            ),
          );
        } else {
          _addLinkedTextSpans(context, spans, fragment.text);
        }
      }

      if (spans.isNotEmpty) return spans;
    }

    _addLinkedTextSpans(context, spans, text);

    if (spans.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    return spans;
  }

  void _addLinkedTextSpans(
    BuildContext context,
    List<InlineSpan> spans,
    String source,
  ) {
    final linkColor = Theme.of(context).colorScheme.primary;
    var cursor = 0;

    for (final match in regexLink.allMatches(source)) {
      final linkStart = _linkStartIncludingScheme(source, match.start);
      if (linkStart < cursor) continue;

      _addPlainSpan(
        spans,
        source.substring(cursor, linkStart),
        breakBeforeLink: breakLongLinks && (linkStart > 0 || spans.isNotEmpty),
      );
      if (breakLongLinks && linkStart == cursor && spans.isNotEmpty) {
        _addLineBreakBeforeLink(spans);
      }

      final rawLink = source.substring(linkStart, match.end);
      final trimmedLink = _trimTrailingLinkPunctuation(rawLink);
      spans.add(
        TextSpan(
          text: trimmedLink,
          style: style?.copyWith(
            color: linkColor,
            decoration: TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _launchPinnedChatLink(trimmedLink, launchExternal),
        ),
      );

      if (trimmedLink.length < rawLink.length) {
        spans.add(
          TextSpan(text: rawLink.substring(trimmedLink.length), style: style),
        );
      }

      cursor = match.end;
    }

    if (cursor < source.length) {
      _addNonLinkSpans(spans, source.substring(cursor));
    }
  }

  void _addPlainSpan(
    List<InlineSpan> spans,
    String text, {
    required bool breakBeforeLink,
  }) {
    if (text.isEmpty) return;

    if (breakBeforeLink && !text.endsWith('\n')) {
      final trimmedText = text.trimRight();
      if (trimmedText.isNotEmpty) {
        _addNonLinkSpans(spans, trimmedText);
      }
      spans.add(TextSpan(text: '\n', style: style));
      return;
    }

    _addNonLinkSpans(spans, text);
  }

  void _addNonLinkSpans(List<InlineSpan> spans, String source) {
    for (final match in RegExp(r'\s+|\S+').allMatches(source)) {
      final token = match.group(0)!;
      if (token.trim().isEmpty) {
        spans.add(TextSpan(text: token, style: style));
        continue;
      }

      final emote = emoteToObject[token];
      if (emote == null) {
        spans.add(TextSpan(text: token, style: style));
        continue;
      }

      spans.add(
        _PinnedEmoteSpan(
          text: emote.name,
          imageUrl: emote.url,
          emote: emote,
          launchExternal: launchExternal,
        ),
      );
    }
  }

  void _addLineBreakBeforeLink(List<InlineSpan> spans) {
    final lastSpan = spans.isEmpty ? null : spans.last;
    if (lastSpan is TextSpan) {
      final lastText = lastSpan.text;
      if (lastText != null) {
        if (lastText.endsWith('\n')) return;
        spans[spans.length - 1] = TextSpan(
          text: lastText.trimRight(),
          style: lastSpan.style,
          recognizer: lastSpan.recognizer,
          children: lastSpan.children,
        );
      }
    }

    spans.add(TextSpan(text: '\n', style: style));
  }
}

class _PinnedEmoteSpan extends WidgetSpan {
  _PinnedEmoteSpan({
    required String text,
    required String imageUrl,
    required Emote? emote,
    required bool launchExternal,
  }) : super(
         alignment: PlaceholderAlignment.middle,
         child: Builder(
           builder: (context) => InkWell(
             onTap: () {
               if (emote != null) {
                 IRCMessage.showEmoteDetailsBottomSheet(
                   context,
                   emote: emote,
                   launchExternal: launchExternal,
                 );
                 return;
               }

               IRCMessage.showImageAssetDetailsBottomSheet(
                 context,
                 imageUrl: imageUrl,
                 title: text,
                 subtitle: const Text('Twitch emote'),
                 launchExternal: launchExternal,
               );
             },
             child: Semantics(
               label: text,
               button: true,
               child: FrostyCachedNetworkImage(
                 imageUrl: imageUrl,
                 width: defaultEmoteSize,
                 height: defaultEmoteSize,
                 useFade: false,
                 placeholder: (context, url) =>
                     SizedBox.square(dimension: defaultEmoteSize),
               ),
             ),
           ),
         ),
       );
}

List<ChatBadge> _resolvedPinnedBadges(
  List<PinnedChatBadge> badges,
  Map<String, ChatBadge> twitchBadges, {
  bool authorityOnly = false,
}) {
  final resolvedBadges = <ChatBadge>[];

  for (final badge in badges) {
    final resolvedBadge = badge.resolve(twitchBadges);
    if (resolvedBadge == null) continue;
    if (authorityOnly && !_isPinnedByAuthorityBadge(badge, resolvedBadge)) {
      continue;
    }

    resolvedBadges.add(resolvedBadge);
  }

  return resolvedBadges;
}

bool _isPinnedByAuthorityBadge(PinnedChatBadge badge, ChatBadge resolvedBadge) {
  return [
    badge.setId,
    badge.title,
    resolvedBadge.name,
  ].map(_normalizeBadgeLabel).any(_isAuthorityBadgeLabel);
}

String _normalizeBadgeLabel(String label) {
  return label.toLowerCase().replaceAll(RegExp(r'[\s_\-/]'), '');
}

bool _isAuthorityBadgeLabel(String label) {
  return label == 'moderator' ||
      label == 'headmod' ||
      label == 'headmoderator' ||
      label == 'broadcaster';
}

class _PinnedBadgeButton extends StatelessWidget {
  final ChatBadge badge;
  final double size;
  final bool launchExternal;

  const _PinnedBadgeButton({
    required this.badge,
    required this.size,
    required this.launchExternal,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => IRCMessage.showBadgeDetailsBottomSheet(
        context,
        badge: badge,
        launchExternal: launchExternal,
      ),
      child: Semantics(
        label: badge.name,
        button: true,
        child: FrostyCachedNetworkImage(
          imageUrl: badge.url,
          width: size,
          height: size,
          useFade: false,
          placeholder: (context, url) => SizedBox(width: size, height: size),
        ),
      ),
    );
  }
}

bool _canTogglePinnedChat(String text) =>
    _shouldStartMinimized(text) || regexLink.hasMatch(text);

bool _shouldStartMinimized(String text) {
  return text.length > 92 || text.contains('\n');
}

Color _pinnedSurfaceColor(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  return theme.scaffoldBackgroundColor.a == 0
      ? colorScheme.surface
      : theme.scaffoldBackgroundColor;
}

String _trimTrailingLinkPunctuation(String link) {
  var end = link.length;
  while (end > 0 && '|.,!?;:)]}'.contains(link[end - 1])) {
    end--;
  }
  return link.substring(0, end);
}

int _linkStartIncludingScheme(String text, int matchStart) {
  for (final scheme in const ['https://', 'http://']) {
    final schemeStart = matchStart - scheme.length;
    if (schemeStart < 0) continue;
    final candidate = text.substring(schemeStart, matchStart).toLowerCase();
    if (candidate == scheme) return schemeStart;
  }

  return matchStart;
}

Uri _uriForPinnedChatLink(String link) {
  final uri = Uri.parse(link);
  if (uri.hasScheme) return uri;
  return Uri.parse('https://$link');
}

Future<void> _launchPinnedChatLink(String link, bool launchExternal) {
  return launchUrl(
    _uriForPinnedChatLink(link),
    mode: launchExternal
        ? LaunchMode.externalApplication
        : LaunchMode.inAppBrowserView,
  );
}
