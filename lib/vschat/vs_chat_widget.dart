import 'package:flutter/material.dart';

import 'vs_chat.dart';

/// How a new chat is started from [VSChatWidget].
enum VSChatMode {
  /// "New chat" asks what the chat is about: the host's topics, then the
  /// topic's prompt (if any), then the matching subject, then Yes/No.
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
    setState(() => _rooms = VSChat.conversations());
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
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VSChatTopicsPage(presentation: widget.presentation),
        ),
      );
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
            hintText: VSChat.t('find'),
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
  const VSChatTopicsPage({super.key, this.presentation});

  final VSChatPresentation? presentation;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: Text(VSChat.t('newChat')),
          backgroundColor: VSChat.options.theme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: VSChatTopicsView(presentation: presentation),
      );
}

/// The host's topics for this user. A topic with a prompt asks for its
/// subject first ([VSChatSubjectPage]); one without opens straight away.
class VSChatTopicsView extends StatefulWidget {
  const VSChatTopicsView({super.key, this.presentation});

  final VSChatPresentation? presentation;

  @override
  State<VSChatTopicsView> createState() => _VSChatTopicsViewState();
}

class _VSChatTopicsViewState extends State<VSChatTopicsView> {
  late Future<List<Map<String, dynamic>>> _topics = VSChat.topics();

  @override
  Widget build(BuildContext context) {
    final primary = VSChat.options.theme.primaryColor;
    return RefreshIndicator(
      color: primary,
      onRefresh: () async {
        setState(() => _topics = VSChat.topics());
        await _topics;
      },
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _topics,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final topics = snap.data ?? const [];
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

  void _open(Map<String, dynamic> t) {
    final prompt = t['prompt'];
    if (prompt is Map) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VSChatSubjectPage(
            topic: t,
            prompt: Map<String, dynamic>.from(prompt),
            presentation: widget.presentation,
          ),
        ),
      );
    } else {
      VSChat.start(context, topic: t['topic'].toString(), presentation: widget.presentation);
    }
  }
}

/// Answers a topic's prompt and opens the chat about what it finds.
///
/// The prompt is the host's: `fields` (`{key, label, type: text|phone|date}`)
/// and `any_of` groups of field keys - each group its own block, separated
/// by "OR"; the first fully filled group is sent to find-subject.
class VSChatSubjectPage extends StatefulWidget {
  const VSChatSubjectPage({
    super.key,
    required this.topic,
    required this.prompt,
    this.presentation,
  });

  final Map<String, dynamic> topic;
  final Map<String, dynamic> prompt;
  final VSChatPresentation? presentation;

  @override
  State<VSChatSubjectPage> createState() => _VSChatSubjectPageState();
}

class _VSChatSubjectPageState extends State<VSChatSubjectPage> {
  final Map<String, TextEditingController> _ctl = {};
  late final Map<String, Map<String, dynamic>> _fields = {
    for (final f in (widget.prompt['fields'] as List? ?? const []).whereType<Map>())
      f['key'].toString(): Map<String, dynamic>.from(f),
  };
  late final List<List<String>> _groups = [
    for (final g in (widget.prompt['any_of'] as List? ?? const []).whereType<List>())
      g.map((e) => e.toString()).toList(),
  ];
  List<Map<String, dynamic>>? _matches;
  bool _busy = false;

  String get _topicCode => widget.topic['topic'].toString();
  Color get _primary => VSChat.options.theme.primaryColor;

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key) => _ctl.putIfAbsent(key, TextEditingController.new);

  void _say(String msg) =>
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));

  void _start(String subjectId) => VSChat.start(
        context,
        topic: _topicCode,
        subjectId: subjectId,
        presentation: widget.presentation,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        appBar: AppBar(
          title: Text((widget.topic['name'] ?? _topicCode).toString()),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              VSChat.t('whichOne'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < _groups.length; i++) ...[
              if (i > 0) _or(),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [for (final k in _groups[i]) _field(k)]),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _find,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(VSChat.t('find')),
              ),
            ),
            if (_matches != null && _matches!.length > 1) ...[
              const SizedBox(height: 24),
              Text(VSChat.t('pickOne'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final m in _matches!)
                _Card(
                  icon: Icons.label_outline_rounded,
                  color: _primary,
                  title: (m['label'] ?? m['subject_id']).toString(),
                  trailing: Icons.chat_bubble_outline_rounded,
                  onTap: () => _start(m['subject_id'].toString()),
                ),
            ],
          ],
        ),
      );

  Widget _or() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(VSChat.t('or'), style: const TextStyle(color: Colors.black45)),
          ),
          const Expanded(child: Divider()),
        ]),
      );

  Widget _field(String key) {
    final type = (_fields[key]?['type'] ?? 'text').toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c(key),
        readOnly: type == 'date',
        keyboardType: type == 'phone' ? TextInputType.phone : TextInputType.text,
        decoration: InputDecoration(
          labelText: VSChat.t('field_$key', _fields[key]?['label']?.toString() ?? key),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          suffixIcon: type == 'date' ? const Icon(Icons.calendar_today_outlined) : null,
        ),
        onTap: type == 'date' ? () => _pickDate(key) : null,
      ),
    );
  }

  Future<void> _pickDate(String key) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (d == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    _c(key).text = '${d.year}-${two(d.month)}-${two(d.day)}'; // ISO, as hosts expect
  }

  Future<void> _find() async {
    final group = _groups
        .where((g) => g.every((k) => _c(k).text.trim().isNotEmpty))
        .firstOrNull;
    if (group == null) return _say(VSChat.t('fillOneGroup'));

    setState(() => _busy = true);
    final found = await VSChat.findSubjects(
      _topicCode,
      {for (final k in group) k: _c(k).text.trim()},
      onError: _say,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _matches = found;
    });
    if (found == null) return;
    if (found.isEmpty) {
      _say(VSChat.t('noMatch'));
    } else if (found.length == 1) {
      _start(found.first['subject_id'].toString()); // one match: straight to Yes/No
    }
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
    this.trailing = Icons.chevron_right_rounded,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final IconData trailing;
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
                Icon(trailing, color: color),
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
