import 'package:flutter/material.dart';
import 'package:frosty/models/pinned_chat.dart';
import 'package:intl/intl.dart';

class PinnedChatsStack extends StatelessWidget {
  static const collapsedHeight = 108.0;

  final List<PinnedChatMessage> pinnedChats;
  final void Function(String id) onDismiss;
  final void Function(Iterable<String> ids) onDismissMany;

  const PinnedChatsStack({
    super.key,
    required this.pinnedChats,
    required this.onDismiss,
    required this.onDismissMany,
  });

  @override
  Widget build(BuildContext context) {
    if (pinnedChats.isEmpty) return const SizedBox.shrink();

    final visibleLayerCount = pinnedChats.length.clamp(1, 3);
    final topPin = pinnedChats.first;

    return SizedBox(
      height: collapsedHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = visibleLayerCount - 1; i >= 1; i--)
            Positioned(
              left: 12.0 * i,
              right: 12.0 * i,
              top: 8.0 * i,
              child: _PinnedLayerCard(opacity: 1 - (i * 0.18)),
            ),
          Positioned(
            left: 8,
            right: 8,
            top: 0,
            child: _PinnedChatCard(
              pin: topPin,
              count: pinnedChats.length,
              onTap: () => _showPinnedChatsSheet(context),
              onDismiss: () => onDismiss(topPin.id),
            ),
          ),
        ],
      ),
    );
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
              onDismissMany(selectedPinIds.toList());
              Navigator.pop(context);
            }

            void dismissAll() {
              onDismissMany(pinnedChats.map((pin) => pin.id).toList());
              Navigator.pop(context);
            }

            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.push_pin_rounded,
                          color: Theme.of(context).colorScheme.primary,
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
                  for (final pin in pinnedChats)
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
                      title: Text(
                        pin.messageText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(_pinSubtitle(pin)),
                      secondary: IconButton(
                        onPressed: () {
                          onDismiss(pin.id);
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Dismiss pinned chat',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
        height: 78,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
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
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _PinnedChatCard({
    required this.pin,
    required this.count,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final headerStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );

    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.push_pin_rounded,
                size: 18,
                color: colorScheme.primary,
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
                        if (count > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$count pinned',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pin.messageText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _senderLine(pin),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
