import 'package:flutter/material.dart';

import 'vs_chat.dart';

/// How a new chat is started from [VSChatWidget].
enum VSChatMode {
  /// "New chat" lists the topics the host offers this user (by role) that
  /// are about nothing specific - General, "System issue"... A topic may ask
  /// one optional question first; the answer opens the room as its first
  /// message. A chat about a THING (a parcel, a payout) starts from that
  /// thing's own chat icon ([VSChatButton]), which knows its id.
  topics,

  /// Click to chat: "New chat" opens [VSChatWidget.topic] straight away
  /// (after the Yes/No) - a support line, a helpdesk, an AI assistant.
  direct,
}

/// The whole chat entry point - drop it in a route, a tab or a drawer.
///
/// ```dart
/// const VSChatWidget();                                          // drill-down
/// const VSChatWidget(mode: VSChatMode.direct, topic: 'general'); // one tap
/// ```
///
/// With [showConversations] (the default) it lists the rooms the user is
/// in, newest first, searchable, with a "New chat" button; without it, it
/// is just the way to start one.
class VSChatWidget extends StatefulWidget {
  const VSChatWidget({
    super.key,
    this.mode = VSChatMode.topics,
    this.topic,
    this.subjectId,
    this.showConversations = true,
    this.showAppBar = true,
    this.title,
    this.presentation,
  }) : assert(mode != VSChatMode.direct || topic != null,
            'VSChatMode.direct needs a topic');

  final VSChatMode mode;

  /// The topic (and optional subject) [VSChatMode.direct] opens.
  final String? topic;
  final String? subjectId;

  final bool showConversations;
  final bool showAppBar;

  /// The app bar title; the `title` text by default.
  final String? title;

  /// Overrides [VSChatOptions.presentation] for rooms opened from here.
  final VSChatPresentation? presentation;

  @override
  State<VSChatWidget> createState() => _VSChatWidgetState();
}

class _VSChatWidgetState extends State<VSChatWidget> {
  late Future<List<Map<String, dynamic>>> _rooms = VSChat.conversations();
  String _query = '';

  Color get _primary => VSChat.options.theme.primaryColor;

  Future<void> _reload() async {
    // A block, not an arrow: an arrow returns the assigned Future, and
    // setState throws on a callback that returns a Future.
    setState(() {
      _rooms = VSChat.conversations();
    });
    await _rooms;
  }

  Future<void> _newChat() async {
    if (widget.mode == VSChatMode.direct) {
      await VSChat.start(
        context,
        topic: widget.topic!,
        subjectId: widget.subjectId,
        presentation: widget.presentation,
      );
    } else {
      /* The host offers this user's topics - always the one everyone has
         (General), plus any configured for their role. ONE topic is not a
         choice, so it opens directly; a list appears only when there are two
         or more to choose between. */
      final topics = await VSChat.topics();
      if (!mounted) return;
      if (topics.length == 1) {
        await VSChatTopicsView.open(context, topics.first, presentation: widget.presentation);
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VSChatTopicsPage(presentation: widget.presentation, topics: topics),
          ),
        );
      }
    }
    if (mounted && widget.showConversations) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final body = !widget.showConversations
        ? (widget.mode == VSChatMode.topics
            ? VSChatTopicsView(presentation: widget.presentation)
            : _StartCard(onStart: _newChat, color: _primary))
        : _conversations();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(widget.title ?? VSChat.t('title')),
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              elevation: 0,
            )
          : null,
      floatingActionButton: widget.showConversations
          ? FloatingActionButton.extended(
              onPressed: _newChat,
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.edit_square),
              label: Text(VSChat.t('newChat')),
            )
          : null,
      body: body,
    );
  }

  Widget _conversations() => RefreshIndicator(
        color: _primary,
        onRefresh: _reload,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _rooms,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final q = _query.toLowerCase();
            final all = snap.data ?? const [];
            final rooms = q.isEmpty
                ? all
                : all.where((r) => _searchText(r).contains(q)).toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (all.length > 6) _search(),
                if (all.isEmpty)
                  _Empty(
                    icon: Icons.forum_outlined,
                    text: VSChat.t('noConversations'),
                    action: VSChat.t('newChat'),
                    onAction: _newChat,
                    color: _primary,
                  ),
                for (final r in rooms) _roomTile(r),
              ],
            );
          },
        ),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: TextField(
          onChanged: (v) => setState(() => _query = v.trim()),
          decoration: InputDecoration(
            hintText: VSChat.t('search'),
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  Widget _roomTile(Map<String, dynamic> r) {
    final name = (r['name'] ?? r['channel_id']).toString();
    final sub = _contextLine(r['context']);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () async {
          await VSChat.reopen(
            context,
            r['channel_id'].toString(),
            presentation: widget.presentation,
          );
          if (mounted) _reload();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              VSChatAvatar(label: name, color: _primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _when(r['last_opened_at']?.toString()),
                style: const TextStyle(color: Colors.black45, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _contextLine(Object? ctx) => ctx is Map
      ? ctx.values
          .where((v) => v != null && '$v'.isNotEmpty && v is! Map && v is! List)
          .take(3)
          .join(' · ')
      : '';

  static String _searchText(Map<String, dynamic> r) =>
      '${r['name'] ?? ''} ${r['channel_id']} ${_contextLine(r['context'])}'.toLowerCase();

  /// Today: 14:05. This year: 09-24. Older: 2025-12-31.
  static String _when(String? at) {
    final d = DateTime.tryParse(at ?? '')?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${two(d.hour)}:${two(d.minute)}';
    }
    return d.year == now.year ? '${two(d.month)}-${two(d.day)}' : '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

/// A chat icon for a row (a parcel, an order, an invoice): one tap asks
/// Yes/No and opens the room about [subjectId].
class VSChatButton extends StatelessWidget {
  const VSChatButton({
    super.key,
    required this.topic,
    this.subjectId,
    this.icon = Icons.chat_bubble_outline_rounded,
    this.size = 20,
    this.color,
    this.alert = false,
    this.presentation,
  });

  final String topic;
  final String? subjectId;
  final IconData icon;
  final double size;
  final Color? color;

  /// Draw attention (e.g. a problem parcel): a filled, red-dotted icon.
  final bool alert;
  final VSChatPresentation? presentation;

  @override
  Widget build(BuildContext context) {
    final c = color ?? VSChat.options.theme.primaryColor;
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: VSChat.t('title'),
      onPressed: () => VSChat.start(
        context,
        topic: topic,
        subjectId: subjectId,
        presentation: presentation,
      ),
      icon: Badge(
        isLabelVisible: alert,
        smallSize: 8,
        child: Icon(alert ? Icons.chat_bubble_rounded : icon, size: size, color: c),
      ),
    );
  }
}

/// "What is your chat about?" as a page.
class VSChatTopicsPage extends StatelessWidget {
  const VSChatTopicsPage({super.key, this.presentation, this.topics});

  final VSChatPresentation? presentation;

  /// Already fetched (by "New chat"), so the page does not ask twice.
  final List<Map<String, dynamic>>? topics;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: Text(VSChat.t('newChat')),
          backgroundColor: VSChat.options.theme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: VSChatTopicsView(presentation: presentation, topics: topics),
      );
}

/// The host's topics for this user. One with a question asks it first
/// ([VSChatDetailSheet], answer optional); one without opens straight away.
class VSChatTopicsView extends StatefulWidget {
  const VSChatTopicsView({super.key, this.presentation, this.topics});

  final VSChatPresentation? presentation;
  final List<Map<String, dynamic>>? topics;

  /// Open one of the host's topics: straight away, or after its one optional
  /// question ([VSChatDetailSheet]). Shared by the list and by "New chat" when
  /// there is only one topic to open.
  static Future<void> open(
    BuildContext context,
    Map<String, dynamic> t, {
    VSChatPresentation? presentation,
  }) async {
    final topic = t['topic'].toString();
    final question = (t['detail_prompt'] ?? '').toString().trim();
    if (question.isEmpty) {
      return VSChat.start(context, topic: topic, presentation: presentation);
    }
    final detail = await VSChatDetailSheet.show(
      context,
      title: (t['name'] ?? topic).toString(),
      question: question,
    );
    if (detail == null || !context.mounted) return; // dismissed
    await VSChat.start(
      context,
      topic: topic,
      detail: detail,
      confirmed: true, // the sheet's "Start chat" was the deliberate tap
      presentation: presentation,
    );
  }

  @override
  State<VSChatTopicsView> createState() => _VSChatTopicsViewState();
}

class _VSChatTopicsViewState extends State<VSChatTopicsView> {
  late Future<List<Map<String, dynamic>>> _topics =
      widget.topics != null ? Future.value(widget.topics!) : VSChat.topics();

  @override
  Widget build(BuildContext context) {
    final primary = VSChat.options.theme.primaryColor;
    return RefreshIndicator(
      color: primary,
      onRefresh: () async {
        setState(() {
          _topics = VSChat.topics(); // a block: an arrow would return the Future
        });
        await _topics;
      },
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _topics,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final topics = snap.data ?? const [];
          if (topics.length == 1) {
            // One topic is not a choice (see VSChatWidget._newChat).
            return _StartCard(onStart: () => _open(topics.first), color: primary);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                VSChat.t('chooseTopic'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              if (topics.isEmpty)
                _Empty(icon: Icons.topic_outlined, text: VSChat.t('noTopics')),
              for (final t in topics)
                _Card(
                  icon: Icons.forum_outlined,
                  color: primary,
                  title: (t['name'] ?? t['topic']).toString(),
                  subtitle: t['description']?.toString(),
                  onTap: () => _open(t),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> t) =>
      VSChatTopicsView.open(context, t, presentation: widget.presentation);
}

/// The one optional question a topic may ask before its room opens - the
/// host's text ("What happened?"). Resolves to the answer ('' when left
/// blank), or null when dismissed.
class VSChatDetailSheet extends StatefulWidget {
  const VSChatDetailSheet({super.key, required this.title, required this.question});

  final String title;
  final String question;

  static Future<String?> show(BuildContext context, {required String title, required String question}) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => VSChatDetailSheet(title: title, question: question),
      );

  @override
  State<VSChatDetailSheet> createState() => _VSChatDetailSheetState();
}

class _VSChatDetailSheetState extends State<VSChatDetailSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = VSChat.options.theme.primaryColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFD1D5DB), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
          const SizedBox(height: 6),
          Text(widget.question, style: const TextStyle(fontSize: 15, height: 1.4, color: Color(0xFF4B5563))),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: VSChat.t('detailOptional'),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              counterText: '',
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(VSChat.t('notifyNote'), style: const TextStyle(fontSize: 12.5, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, _text.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: Text(VSChat.t('startChat')),
          ),
        ],
      ),
    );
  }
}

/// Initials in a tinted circle.
class VSChatAvatar extends StatelessWidget {
  const VSChatAvatar({super.key, required this.label, required this.color, this.size = 48});

  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials = label
        .trim()
        .split(RegExp(r'[\s_-]+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Text(
        initials.isEmpty ? '#' : initials,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.36),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: color),
              ]),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action, this.onAction, this.color});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 96),
        child: Column(children: [
          Icon(icon, size: 64, color: Colors.black26),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.black54, fontSize: 15)),
          if (action != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: onAction,
              child: Text(action!),
            ),
          ],
        ]),
      );
}

class _StartCard extends StatelessWidget {
  const _StartCard({required this.onStart, required this.color});

  final VoidCallback onStart;
  final Color color;

  @override
  Widget build(BuildContext context) => _Empty(
        icon: Icons.forum_rounded,
        text: VSChat.t('confirmStart'),
        action: VSChat.t('newChat'),
        onAction: onStart,
        color: color,
      );
}
