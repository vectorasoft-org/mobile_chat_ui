import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/chat_config.dart';
import '../config/chat_theme.dart';
import '../config/chat_theme_provider.dart';
import '../handlers/file_download_handler.dart';
import '../models.dart';
import '../resolvers/image_resolver.dart';
import '../services/chat_localizations.dart';
import '../services/chat_reactive_adapter.dart';
import '../services/chat_service.dart';
import 'video_player_page.dart';

/// Which tab [ChatSharedPage] opens on.
enum ChatSharedTab { media, files, members }

/// Everything shared in a room, Telegram style: a header with the room and
/// its size, then Media (grid), Files (list) and Members.
///
/// Media and Files are read from the room's loaded history - the same cache
/// the message list shows - so nothing is fetched twice; "Load older" pages
/// further back through the same history call the room uses.
class ChatSharedPage extends StatefulWidget {
  const ChatSharedPage({
    super.key,
    required this.channelId,
    required this.channelName,
    required this.adapter,
    required this.config,
    this.initialTab = ChatSharedTab.media,
  });

  final String channelId;
  final String channelName;
  final ChatReactiveAdapter adapter;
  final ChatConfig config;
  final ChatSharedTab initialTab;

  @override
  State<ChatSharedPage> createState() => _ChatSharedPageState();
}

class _ChatSharedPageState extends State<ChatSharedPage> {
  late final ChatService _service = widget.adapter.chatService;
  late final Future<List<ChatMember>> _members =
      widget.config.membersProvider?.call() ?? Future.value(const []);
  late final _resolver = RealImageResolver(
    chatService: _service,
    chatConfig: widget.config,
  );
  late final _downloads = FileDownloadHandler(
    logger: widget.config.logger,
    config: widget.config,
  );
  bool _loading = false;
  bool _exhausted = false;

  String _t(String key) => ChatLocalizations.text(context, key);

  Future<void> _loadOlder() async {
    final cache = _service.getMessagesCache();
    if (_loading || cache.isEmpty) return;
    setState(() => _loading = true);
    try {
      final older = await _service.getMessages(
        channelId: widget.channelId,
        limit: 50,
        getMessageOpt: GetMessageOpt.lt,
        optMessageId: cache.first.id,
      );
      _exhausted = older.isEmpty;
    } catch (e) {
      widget.config.logger.e('Loading older messages failed', error: e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.adapter.currentTheme;
    return ChatThemeProvider(
      theme: theme,
      child: DefaultTabController(
        length: 3,
        initialIndex: widget.initialTab.index,
        child: Scaffold(
          backgroundColor: const Color(0xFFF6F7F9),
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                pinned: true,
                expandedHeight: 188,
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
                flexibleSpace: FlexibleSpaceBar(
                  background: _Header(
                    name: widget.channelName,
                    theme: theme,
                    members: _members,
                  ),
                ),
                bottom: TabBar(
                  indicatorColor: Colors.white,
                  indicatorWeight: 3,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  tabs: [
                    Tab(text: _t('media')),
                    Tab(text: _t('files')),
                    Tab(text: _t('members')),
                  ],
                ),
              ),
            ],
            body: StreamBuilder<List<Message>>(
              stream: widget.adapter.messagesStream,
              initialData: widget.adapter.currentMessages,
              builder: (context, snap) {
                final shared = _Shared.of(snap.data ?? const []);
                return TabBarView(
                  children: [
                    _mediaTab(shared.media),
                    _filesTab(shared.files),
                    _membersTab(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadOlderButton() => _exhausted
      ? const SizedBox(height: 24)
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton.icon(
                    onPressed: _loadOlder,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: Text(_t('loadOlder')),
                  ),
          ),
        );

  Widget _empty(IconData icon, String key) => ListView(
        children: [
          const SizedBox(height: 72),
          Icon(icon, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          Center(
            child: Text(_t(key), style: const TextStyle(color: Colors.black45)),
          ),
          _loadOlderButton(),
        ],
      );

  Widget _mediaTab(List<_Item> items) {
    if (items.isEmpty) return _empty(Icons.photo_library_outlined, 'noMedia');
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(2),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) => _mediaTile(items[i]),
          ),
        ),
        SliverToBoxAdapter(child: _loadOlderButton()),
      ],
    );
  }

  Widget _mediaTile(_Item item) {
    final thumb = item.isVideo ? item.a['thumb_url'] as String? : item.url;
    return GestureDetector(
      onTap: () => item.isVideo
          ? Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatThemeProvider(
                  theme: widget.adapter.currentTheme,
                  child: VideoPlayerPage(
                    videoUrl: item.url,
                    thumbnailUrl: thumb,
                    title: item.name,
                    logger: widget.config.logger,
                    chatConfig: widget.config,
                  ),
                ),
              ),
            )
          : _resolver.showImageViewer(context, item.m, imageUrl: item.url),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black12),
          if (thumb != null && thumb.isNotEmpty)
            CachedNetworkImage(
              imageUrl: thumb,
              httpHeaders: widget.config.httpAuthHeaders(),
              fit: BoxFit.cover,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.black26),
            ),
          if (item.isVideo)
            const Center(
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.black45,
                child: Icon(Icons.play_arrow_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filesTab(List<_Item> items) {
    if (items.isEmpty) return _empty(Icons.folder_open_outlined, 'noFiles');
    final primary = widget.adapter.currentTheme.primaryColor;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length + 1,
      separatorBuilder: (_, i) =>
          i < items.length - 1 ? const Divider(height: 1, indent: 72) : const SizedBox.shrink(),
      itemBuilder: (context, i) {
        if (i == items.length) return _loadOlderButton();
        final item = items[i];
        return ListTile(
          tileColor: Colors.white,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: primary),
          ),
          title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [item.size, item.date].where((s) => s.isNotEmpty).join(' · '),
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
          trailing: Icon(Icons.download_rounded, color: primary),
          onTap: () => _downloads.downloadFileWithSystemFallback(
            item.m,
            item.a,
            item.a['type'] as String? ?? 'file',
          ),
        );
      },
    );
  }

  Widget _membersTab() {
    final primary = widget.adapter.currentTheme.primaryColor;
    final me = _service.getCachedUserCode();
    return FutureBuilder<List<ChatMember>>(
      future: _members,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _empty(Icons.group_outlined, 'noMembers');
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, i) {
            final m = list[i];
            final label = (m.name?.isNotEmpty ?? false) ? m.name! : m.id;
            return ListTile(
              tileColor: Colors.white,
              leading: _Avatar(label: label, color: primary),
              title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: m.role == null
                  ? null
                  : Text(m.role!, style: const TextStyle(fontSize: 12)),
              trailing: m.id == me
                  ? Chip(
                      label: Text(_t('you')),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide.none,
                      backgroundColor: primary.withValues(alpha: 0.1),
                      labelStyle: TextStyle(color: primary, fontSize: 12),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.theme, required this.members});

  final String name;
  final ChatTheme theme;
  final Future<List<ChatMember>> members;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor,
              Color.lerp(theme.primaryColor, Colors.black, 0.25)!,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 56),
        child: Row(
          children: [
            _Avatar(label: name, color: Colors.white, size: 60, onPrimary: theme.primaryColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FutureBuilder<List<ChatMember>>(
                    future: members,
                    builder: (context, snap) => Text(
                      snap.hasData && snap.data!.isNotEmpty
                          ? '${snap.data!.length} ${ChatLocalizations.text(context, 'members').toLowerCase()}'
                          : '',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Initials in a tinted circle.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.label,
    required this.color,
    this.size = 44,
    this.onPrimary,
  });

  final String label;
  final Color color;
  final double size;
  final Color? onPrimary;

  @override
  Widget build(BuildContext context) {
    final words = label.trim().split(RegExp(r'[\s_-]+')).where((w) => w.isNotEmpty);
    final initials = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: onPrimary == null ? color.withValues(alpha: 0.12) : color,
      child: Text(
        initials.isEmpty ? '#' : initials,
        style: TextStyle(
          color: onPrimary ?? color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// One shared attachment and the message it came with.
class _Item {
  _Item(this.m, this.a);

  final Message m;
  final Map<String, dynamic> a;

  String get _type => (a['type'] as String? ?? '').toLowerCase();
  String get _mime => (a['mime_type'] as String? ?? '').toLowerCase();

  bool get isVideo => _type == 'video' || _mime.startsWith('video/');
  bool get isMedia =>
      isVideo || _type == 'image' || _mime.startsWith('image/');
  bool get isFile =>
      !isMedia && (a['asset_url'] ?? a['image_url']) != null;

  String get url => (a['image_url'] ?? a['asset_url'] ?? '') as String;
  String get name => (a['title'] ?? a['fallback'] ?? 'File').toString();

  IconData get icon {
    if (_type == 'voicerecording' || _type == 'audio' || _mime.startsWith('audio/')) {
      return Icons.mic_rounded;
    }
    if (_mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (_mime.contains('sheet') || _mime.contains('excel') || _mime.contains('csv')) {
      return Icons.table_chart_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String get size {
    final b = int.tryParse('${a['file_size'] ?? ''}');
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  String get date {
    final d = DateTime.tryParse(m.createdAt ?? '')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

/// A room's attachments split into media and files, newest first.
class _Shared {
  _Shared(this.media, this.files);

  final List<_Item> media;
  final List<_Item> files;

  factory _Shared.of(List<Message> messages) {
    final media = <_Item>[], files = <_Item>[];
    for (final m in messages.reversed) {
      if (m.isDeleted || m.isSending) continue;
      for (final a in m.attachments ?? const <Map<String, dynamic>>[]) {
        final item = _Item(m, a);
        if (item.isMedia) {
          media.add(item);
        } else if (item.isFile) {
          files.add(item);
        }
      }
    }
    return _Shared(media, files);
  }
}
