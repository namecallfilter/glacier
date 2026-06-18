import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class PinnedChatsStack extends StatefulWidget {
  static const topOffset = 10.0;
  static const collapsedHeight = 96.0;
  static const expandedHeight = 154.0;

  final List<PinnedChatMessage> pinnedChats;
  final bool launchExternal;
  final void Function(String id) onDismiss;
  final void Function(Iterable<String> ids) onDismissMany;

  const PinnedChatsStack({
    super.key,
    required this.pinnedChats,
    required this.launchExternal,
    required this.onDismiss,
    required this.onDismissMany,
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

    final visibleLayerCount = widget.pinnedChats.length.clamp(1, 3);
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
      child: SizedBox(
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = visibleLayerCount - 1; i >= 1; i--)
              Positioned(
                left: 10.0 * i,
                right: 10.0 * i,
                top: 7.0 * i,
                child: _PinnedLayerCard(opacity: 1 - (i * 0.2)),
              ),
            Positioned(
              left: 8,
              right: 8,
              top: 0,
              child: _PinnedChatCard(
                pin: topPin,
                count: widget.pinnedChats.length,
                launchExternal: widget.launchExternal,
                canToggle: canToggleTopPin,
                isExpanded: isTopPinExpanded,
                onToggle: () => _togglePinnedChat(topPin),
                onOpen: () => _showPinnedChatsSheet(context),
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

  void _showPinnedChatsSheet(BuildContext context) {
    final selectedPinIds = <String>{};

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void dismissSelected() {
              if (selectedPinIds.isEmpty) return;
              widget.onDismissMany(selectedPinIds.toList());
              Navigator.pop(context);
            }

            void dismissAll() {
              widget.onDismissMany(widget.pinnedChats.map((pin) => pin.id));
              Navigator.pop(context);
            }

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.push_pin_rounded,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Pinned chats',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Close',
                        ),
                      ],
                    ),
                  ),
                  for (final pin in widget.pinnedChats)
                    CheckboxListTile(
                      value: selectedPinIds.contains(pin.id),
                      onChanged: (selected) {
                        setModalState(() {
                          if (selected ?? false) {
                            selectedPinIds.add(pin.id);
                          } else {
                            selectedPinIds.remove(pin.id);
                          }
                        });
                      },
                      title: _PinnedMessageText(
                        text: pin.messageText,
                        launchExternal: widget.launchExternal,
                        breakLongLinks: _canTogglePinnedChat(pin.messageText),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(_pinSubtitle(pin)),
                      secondary: IconButton(
                        onPressed: () {
                          widget.onDismiss(pin.id);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Dismiss pinned chat',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: selectedPinIds.isEmpty
                              ? null
                              : dismissSelected,
                          child: const Text('Dismiss selected'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: dismissAll,
                          child: const Text('Dismiss all'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _pinSubtitle(PinnedChatMessage pin) {
    final parts = <String>[
      pin.senderDisplayName,
      if (pin.sentAt != null)
        'sent at ${DateFormat.jm().format(pin.sentAt!.toLocal())}',
      if (pin.pinnedByDisplayName != null)
        'pinned by ${pin.pinnedByDisplayName}',
    ];
    return parts.join(' • ');
  }
}

class _PinnedLayerCard extends StatelessWidget {
  final double opacity;

  const _PinnedLayerCard({required this.opacity});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: opacity,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: _pinnedSurfaceColor(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinnedChatCard extends StatelessWidget {
  final PinnedChatMessage pin;
  final int count;
  final bool launchExternal;
  final bool canToggle;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const _PinnedChatCard({
    required this.pin,
    required this.count,
    required this.launchExternal,
    required this.canToggle,
    required this.isExpanded,
    required this.onToggle,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pinned by ${pin.pinnedByDisplayName ?? 'moderator'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: headerStyle,
                          ),
                        ),
                        if (count > 1) _PinnedCountChip(count: count),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _PinnedMessageText(
                      text: pin.messageText,
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
                    const SizedBox(height: 5),
                    Text(
                      _senderLine(pin),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.78,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canToggle)
                IconButton(
                  onPressed: onToggle,
                  icon: Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  tooltip: isExpanded
                      ? 'Collapse pinned chat'
                      : 'Expand pinned chat',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                )
              else if (count > 1)
                IconButton(
                  onPressed: onOpen,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  tooltip: 'Open pinned chats',
                  visualDensity: VisualDensity.compact,
                  iconSize: 20,
                ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Dismiss pinned chat',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _senderLine(PinnedChatMessage pin) {
    final sentAt = pin.sentAt == null
        ? null
        : DateFormat.jm().format(pin.sentAt!.toLocal());
    return sentAt == null
        ? pin.senderDisplayName
        : '${pin.senderDisplayName} sent at $sentAt';
  }
}

class _PinnedCountChip extends StatelessWidget {
  final int count;

  const _PinnedCountChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Text(
        '$count pinned',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _PinnedMessageText extends StatelessWidget {
  final String text;
  final bool launchExternal;
  final bool breakLongLinks;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const _PinnedMessageText({
    required this.text,
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
    final linkColor = Theme.of(context).colorScheme.primary;
    var cursor = 0;

    for (final match in regexLink.allMatches(text)) {
      final linkStart = _linkStartIncludingScheme(text, match.start);
      if (linkStart < cursor) continue;

      _addPlainSpan(
        spans,
        text.substring(cursor, linkStart),
        breakBeforeLink: breakLongLinks && linkStart > 0,
      );

      final rawLink = text.substring(linkStart, match.end);
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

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: style));
    }

    if (spans.isEmpty) {
      return [TextSpan(text: text, style: style)];
    }

    return spans;
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
        spans.add(TextSpan(text: trimmedText, style: style));
      }
      spans.add(TextSpan(text: '\n', style: style));
      return;
    }

    spans.add(TextSpan(text: text, style: style));
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
