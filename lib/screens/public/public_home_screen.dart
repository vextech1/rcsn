import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/user_role.dart';
import '../../core/errors/app_failure.dart';
import '../../core/router/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/public_post.dart';
import '../../data/repositories/public_post_repository.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_error_display.dart';
import '../../widgets/common/app_loading_indicator.dart';
import '../registrar/timetables/timetable_list_screen.dart';
import 'public_post_widgets.dart';

/// The Public Space: announcements, calendar, sports, graduations,
/// performances, gallery and general school info. Open to anyone who
/// installs the app, no sign-in (reached from "Continue without login").
///
/// Signed-in staff and tutors also get a "New post" button here, and the
/// Principal and Registrar get a review queue for tutor posts.
class PublicHomeScreen extends StatefulWidget {
  const PublicHomeScreen({super.key});

  @override
  State<PublicHomeScreen> createState() => _PublicHomeScreenState();
}

class _PublicHomeScreenState extends State<PublicHomeScreen> {
  // null = "All". Calendar is the `event` category.
  static const List<(String, PublicCategory?)> _tabs = [
    ('All', null),
    ('Announcements', PublicCategory.announcement),
    ('Calendar', PublicCategory.event),
    ('Sports', PublicCategory.sports),
    ('Graduations', PublicCategory.graduation),
    ('Performances', PublicCategory.performance),
    ('Gallery', PublicCategory.gallery),
    ('Info', PublicCategory.info),
  ];

  // Bumped after a new post so every feed reloads.
  int _refreshToken = 0;

  Future<void> _newPost() async {
    final posted = await context.push<bool>(AppRoutes.publicNew);
    if (posted == true && mounted) setState(() => _refreshToken++);
  }

  Future<void> _review() async {
    await context.push(AppRoutes.publicReview);
    if (mounted) setState(() => _refreshToken++);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canPost = (auth.isUsableStaffSession &&
            auth.resolvedRole!.canPublishPublicly) ||
        auth.isUsableTutorSession;
    final canReview =
        auth.isUsableStaffSession && auth.resolvedRole!.canModeratePublic;

    return DefaultTabController(
      length: _tabs.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('RCSN Public Space'),
          actions: [
            if (canReview)
              IconButton(
                icon: const Icon(Icons.fact_check),
                tooltip: 'Review tutor posts',
                onPressed: _review,
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final t in _tabs) Tab(text: t.$1),
              const Tab(text: 'Timetables'),
            ],
          ),
        ),
        floatingActionButton: canPost
            ? FloatingActionButton.extended(
                onPressed: _newPost,
                icon: const Icon(Icons.add),
                label: const Text('New post'),
              )
            : null,
        body: TabBarView(
          children: [
            for (final t in _tabs)
              _Feed(category: t.$2, refreshToken: _refreshToken),
            const TimetableListBody(mode: TimetableListMode.everyone),
          ],
        ),
      ),
    );
  }
}

class _Feed extends StatefulWidget {
  final PublicCategory? category;
  final int refreshToken;

  const _Feed({required this.category, required this.refreshToken});

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> with AutomaticKeepAliveClientMixin {
  final _repository = PublicPostRepository();
  late Future<List<PublicPost>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _Feed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      setState(() => _future = _load());
    }
  }

  Future<List<PublicPost>> _load() {
    if (widget.category == PublicCategory.event) {
      return _repository.fetchUpcomingEvents();
    }
    return _repository.fetchPublished(
      category: widget.category,
      limit: widget.category == PublicCategory.gallery ? 40 : 20,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    try {
      await next;
    } catch (_) {
      // The FutureBuilder shows the error; do not throw into the indicator.
    }
  }

  void _open(PublicPost post) => context.push(AppRoutes.publicPost, extra: post);

  String get _emptyMessage {
    switch (widget.category) {
      case PublicCategory.event:
        return 'No upcoming events have been added yet.';
      case PublicCategory.gallery:
        return 'No gallery photos yet.';
      default:
        return 'Nothing has been posted here yet. Check back soon.';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<PublicPost>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const AppLoadingIndicator();
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                AppErrorDisplay(
                  failure: UnknownFailure(snapshot.error.toString()),
                  onRetry: _refresh,
                ),
              ],
            );
          }

          final posts = snapshot.data ?? const <PublicPost>[];
          if (posts.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                AppEmptyState(
                  icon: widget.category?.icon ?? Icons.campaign,
                  title: 'Nothing here yet',
                  message: _emptyMessage,
                ),
              ],
            );
          }

          if (widget.category == PublicCategory.gallery) {
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: posts.length,
              itemBuilder: (context, i) => _GalleryTile(
                post: posts[i],
                onTap: () => _open(posts[i]),
              ),
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            itemCount: posts.length,
            itemBuilder: (context, i) =>
                PostCard(post: posts[i], onTap: () => _open(posts[i])),
          );
        },
      ),
    );
  }
}

class _GalleryTile extends StatelessWidget {
  final PublicPost post;
  final VoidCallback onTap;

  const _GalleryTile({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (post.imageUrl != null)
              PostImage(url: post.imageUrl!)
            else
              Container(color: Colors.black12),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: AppColors.primaryDark.withAlpha(200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
