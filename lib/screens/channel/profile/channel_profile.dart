import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:frosty/constants.dart';
import 'package:frosty/models/twitch_video.dart';
import 'package:frosty/screens/channel/channel.dart';
import 'package:frosty/screens/channel/profile/stores/channel_profile_store.dart';
import 'package:frosty/screens/channel/vod/vod_player.dart';
import 'package:frosty/utils/context_extensions.dart';
import 'package:frosty/widgets/alert_message.dart';
import 'package:frosty/widgets/frosty_app_bar.dart';
import 'package:frosty/widgets/frosty_cached_network_image.dart';
import 'package:frosty/widgets/live_indicator.dart';
import 'package:frosty/widgets/profile_picture.dart';
import 'package:frosty/widgets/section_header.dart';
import 'package:frosty/widgets/skeleton_loader.dart';
import 'package:intl/intl.dart';

class ChannelProfile extends StatefulWidget {
  static const routeName = 'ChannelProfile';

  final String userId;
  final String userName;
  final String userLogin;

  const ChannelProfile({
    super.key,
    required this.userId,
    required this.userName,
    required this.userLogin,
  });

  @override
  State<ChannelProfile> createState() => _ChannelProfileState();
}

class _ChannelProfileState extends State<ChannelProfile> {
  late final ChannelProfileStore _store = ChannelProfileStore(
    twitchApi: context.twitchApi,
    userId: widget.userId,
    userLogin: widget.userLogin,
    displayName: widget.userName,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_store.init());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: FrostyAppBar(title: Text(widget.userName)),
      body: RefreshIndicator.adaptive(
        onRefresh: _store.refresh,
        child: Observer(
          builder: (context) {
            if (_store.isLoading && _store.videos.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: const [
                  _ChannelHeaderSkeleton(),
                  SectionHeader('Videos', isFirst: true),
                  _VodCardSkeleton(),
                  _VodCardSkeleton(),
                  _VodCardSkeleton(),
                ],
              );
            }

            if (_store.error != null && _store.videos.isEmpty) {
              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverFillRemaining(
                    child: AlertMessage(message: _store.error!, vertical: true),
                  ),
                ],
              );
            }

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _ChannelHeader(store: _store)),
                const SliverToBoxAdapter(
                  child: SectionHeader('Videos', isFirst: true),
                ),
                SliverToBoxAdapter(child: _VideoTypeSelector(store: _store)),
                if (_store.videos.isEmpty && !_store.isVideosLoading)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: AlertMessage(
                        message:
                            'No ${_selectedVideoTypeLabel(_store.selectedVideoType).toLowerCase()}',
                        vertical: true,
                      ),
                    ),
                  )
                else
                  SliverList.builder(
                    itemCount:
                        _store.videos.length +
                        (_store.isVideosLoading && _store.videos.isNotEmpty
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index >= _store.videos.length) {
                        return const _VodCardSkeleton();
                      }

                      if (index > _store.videos.length - 5 &&
                          _store.hasMoreVideos) {
                        unawaited(_store.loadMoreVideos());
                      }

                      return _VodCard(video: _store.videos[index]);
                    },
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ChannelHeader extends StatelessWidget {
  final ChannelProfileStore store;

  const _ChannelHeader({required this.store});

  @override
  Widget build(BuildContext context) {
    final user = store.user;
    final channel = store.channelInfo;
    final stream = store.streamInfo;
    final displayName = user?.displayName ?? store.displayName;
    final description = user?.description.trim() ?? '';
    final title = stream?.title.trim() ?? channel?.title.trim() ?? '';
    final category = stream?.gameName ?? channel?.gameName ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + MediaQuery.of(context).padding.left,
        16,
        16 + MediaQuery.of(context).padding.right,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          Row(
            spacing: 14,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ProfilePicture(userLogin: store.userLogin, radius: 36),
                  if (store.isLive)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: context.scaffoldColor,
                            width: 2,
                          ),
                        ),
                        child: const Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.textTheme.titleLarge,
                          ),
                        ),
                        if (store.isLive) ...[
                          const SizedBox(width: 8),
                          const LiveIndicator(size: 7),
                        ],
                      ],
                    ),
                    Text(
                      '@${store.userLogin}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.bodySmallColor?.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    settings: const RouteSettings(name: VideoChat.routeName),
                    builder: (context) => VideoChat(
                      userId: store.userId,
                      userName: displayName,
                      userLogin: store.userLogin,
                    ),
                  ),
                ),
                icon: Icon(
                  store.isLive
                      ? Icons.play_arrow_rounded
                      : Icons.chat_bubble_rounded,
                ),
                label: Text(store.primaryActionLabel),
              ),
            ],
          ),
          if (title.isNotEmpty || category.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (category.isNotEmpty)
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.bodySmallColor?.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          if (description.isNotEmpty)
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.bodySmallColor?.withValues(alpha: 0.85),
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoTypeSelector extends StatelessWidget {
  final ChannelProfileStore store;

  const _VideoTypeSelector({required this.store});

  @override
  Widget build(BuildContext context) {
    const types = [
      TwitchVideoType.archive,
      TwitchVideoType.highlight,
      TwitchVideoType.upload,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(
        16 + MediaQuery.of(context).padding.left,
        0,
        16 + MediaQuery.of(context).padding.right,
        8,
      ),
      child: Row(
        spacing: 8,
        children: types
            .map(
              (type) => ChoiceChip(
                label: Text(_selectedVideoTypeLabel(type)),
                selected: store.selectedVideoType == type,
                onSelected: (_) => unawaited(store.selectVideoType(type)),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _VodCard extends StatelessWidget {
  final TwitchVideo video;

  const _VodCard({required this.video});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(context, vodPlayerRoute(video)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16 + MediaQuery.of(context).padding.left,
          8,
          16 + MediaQuery.of(context).padding.right,
          8,
        ),
        child: Row(
          spacing: 12,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 128,
              child: ClipRRect(
                borderRadius: kCardBorderRadius,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FrostyCachedNetworkImage(
                        imageUrl: video.thumbnailUrlForSize(
                          width: 320,
                          height: 180,
                        ),
                        placeholder: (context, url) => const SkeletonLoader(
                          borderRadius: kCardBorderRadius,
                        ),
                        fit: BoxFit.cover,
                      ),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            video.duration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  Text(
                    [
                      DateFormat.yMMMd().format(video.publishedAt.toLocal()),
                      '${NumberFormat.compact().format(video.viewCount)} views',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.bodySmallColor?.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
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

class _ChannelHeaderSkeleton extends StatelessWidget {
  const _ChannelHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + MediaQuery.of(context).padding.left,
        16,
        16 + MediaQuery.of(context).padding.right,
        24,
      ),
      child: Row(
        spacing: 14,
        children: [
          const SkeletonLoader(
            width: 72,
            height: 72,
            borderRadius: BorderRadius.all(Radius.circular(36)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: const [
                SkeletonLoader(width: 140, height: 18),
                SkeletonLoader(width: 96, height: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VodCardSkeleton extends StatelessWidget {
  const _VodCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16 + MediaQuery.of(context).padding.left,
        8,
        16 + MediaQuery.of(context).padding.right,
        8,
      ),
      child: Row(
        spacing: 12,
        children: const [
          SizedBox(
            width: 128,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: SkeletonLoader(borderRadius: kCardBorderRadius),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                SkeletonLoader(width: double.infinity, height: 16),
                SkeletonLoader(width: 140, height: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _selectedVideoTypeLabel(TwitchVideoType type) {
  return switch (type) {
    TwitchVideoType.archive => 'Past broadcasts',
    TwitchVideoType.highlight => 'Highlights',
    TwitchVideoType.upload => 'Uploads',
    TwitchVideoType.all => 'Videos',
  };
}
