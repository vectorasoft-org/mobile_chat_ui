import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../chat/chat_page.dart';
import '../chat/config/chat_config.dart';
import '../chat/config/chat_logger.dart';
import '../chat/config/chat_service_listener.dart';
import '../chat/config/chat_theme.dart';
import '../chat/models.dart';
import '../chat/services/chat_localizations.dart';
import '../chat/services/chat_reactive_adapter.dart';
import '../chat/services/chat_service.dart';
import '../chat/services/default_chat_localization_provider.dart';
import '../chat/services/real_chat_service.dart';
import '../chat/storage/api/chat_storage_adapter.dart';

/// How a room is shown.
enum VSChatPresentation {
  /// A full-screen page (the default).
  page,

  /// A draggable bottom sheet over the current screen - half height, drag
  /// up for full screen. Good for a quick chat about the row in front of you.
  sheet,
}

/// VSChat - the one-shot chat plugin, the Flutter twin of the web widget
/// (dmsdev `public/chat-widget/vschat.js`). See doc/VSChatWidget.md.
///
/// The host DECLARES its chat API and look once; everything else lives here:
/// conversation list, topic drill-down, the Yes/No before a room is opened,
/// the room, uploads, the per-reconnect token and the Members tab.
///
/// ```dart
/// VSChat.init(VSChatOptions(api: apiDio, authorization: () => auth));
/// const VSChatWidget();                                   // the Chat page
/// VSChat.start(context, topic: 'package', subjectId: id); // a chat icon
/// VSChat.reopen(context, channelId);                      // a tapped push
/// ```
///
/// A PUBLIC app with no backend of its own ("Chat with us") runs VISITOR
/// mode against chat-service directly, with the app's publishable key:
/// ```dart
/// VSChat.init(VSChatOptions.visitor(baseUrl: 'https://chat.example.com', key: 'pk_…',
///                                   storage: SharedPreferencesAdapter(prefs)));
/// const VSChatWidget();                                   // topics from chat-service
/// VSChat.identify(name: 'Dara', phone: '012 345 678');    // the app's OWN light registration, any time
/// ```
/// The widget is passive about identity: it never asks who the visitor is.
/// The visitor IS the id + secret kept in [VSChatOptions.storage]; a wiped
/// app is a new visitor. Their rooms (one per topic) are the conversation
/// list. See doc/VSChatWidget.md §12.
class VSChat {
  VSChat._();

  static VSChatOptions? _options;
  static late DefaultChatLocalizationProvider _strings;

  static VSChatOptions get options =>
      _options ?? (throw StateError('Call VSChat.init() first.'));

  /// Once at app start; again to change language, theme or anything else.
  static void init(VSChatOptions options) {
    _options = options;
    _strings = DefaultChatLocalizationProvider(
      language: options.language,
      overrides: options.strings,
    );
    ChatLocalizations.setProvider(_strings);
  }

  /// A text in the current language (keys: chat_strings.dart).
  static String t(String key, [String? fallback]) =>
      _strings.lookup(key, fallback);

  /// Open the room for [topic] about [subjectId]. A NEW room notifies every
  /// member, so it asks Yes/No first (unless [VSChatOptions.confirmStart] is
  /// off); a room the user is already in opens straight away with its history.
  static Future<void> start(
    BuildContext context, {
    required String topic,
    String? subjectId,
    String? detail,
    bool confirmed = false,
    VSChatPresentation? presentation,
  }) async {
    final o = options;
    if (o.visitor != null) return _visitorOpen(context, topic, detail, presentation);
    final body = {
      'topic': topic,
      if (subjectId != null && subjectId.isNotEmpty) 'subject_id': subjectId,
      // The topic's optional question, answered: the room's first message.
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    };
    // [confirmed]: the caller already had a deliberate "Start" (the detail sheet).
    if (o.confirmStart && !confirmed) {
      // The question guards the notification a FIRST open sends every member.
      // The host notifies only people new to the room, so a room the user is
      // already in needs no question (channel-status says which). Either way
      // the room opens through open-channel, which also re-creates it on the
      // chat engine if it went missing - so a reopen can never land in a room
      // that is only in the host's index. No route on the host = always ask.
      final s = await post(o.endpoints.channelStatus, body);
      final d = s['data'];
      final member = s['status'] == 'OK' && d is Map && d['member'] == true;
      if (!context.mounted) return;
      if (!member) {
        final ok = await (o.confirm ?? _confirm)(context, t('confirmStart'));
        if (ok != true || !context.mounted) return;
      }
    }
    await _openWith(context, o.endpoints.openChannel, body, presentation);
  }

  /// Reopen a room the user is already in. No question: nobody new is told.
  static Future<void> reopen(
    BuildContext context,
    String channelId, {
    VSChatPresentation? presentation,
  }) =>
      options.visitor != null
          ? _visitorOpen(context, _visitorTopicOf(channelId), null, presentation)
          : _openWith(
              context,
              options.endpoints.openConversation,
              {'channel_id': channelId},
              presentation,
            );

  /// The rooms the user is in, most recently opened first.
  static Future<List<Map<String, dynamic>>> conversations() async {
    if (options.visitor != null) return _visitorRooms();
    return _list(await post(options.endpoints.conversations, {}));
  }

  /// The topics this user may start a chat about.
  static Future<List<Map<String, dynamic>>> topics() async {
    if (options.visitor != null) return _visitorTopics();
    return _list(await post(options.endpoints.topics, {}));
  }

  /// Show the room for a session the host API returned
  /// (`{base_url, api_key, channel_id, user_id, token, members?}`).
  static Future<void> open(
    BuildContext context,
    Map<String, dynamic> session, {
    VSChatPresentation? presentation,
  }) async {
    final o = options;
    final dio = await o.api();
    final channelId = session['channel_id'].toString();
    final known = session['members'];
    final config = ChatConfig(
      // Uploads and file bytes go through the host (/chat/resource).
      baseUrl: dio.options.baseUrl.replaceAll(RegExp(r'/+$'), ''),
      // The host's headers (app version, ...) plus its current token.
      requestHeaders: () => {
        for (final e in dio.options.headers.entries)
          if (e.value is String) e.key: e.value as String,
        if (o.authorization?.call() case final String auth) 'Authorization': auth,
      },
      // Messages go to chat-service over its socket, as this member.
      socketBaseUrl: session['base_url'].toString(),
      apiKey: session['api_key'].toString(),
      session: ChatSession(
        channelId: channelId,
        userId: session['user_id'].toString(),
        token: session['token'].toString(),
      ),
      tokenProvider: () => _freshToken(channelId),
      // chat-service lists no members to end users; a visitor has no host to ask.
      membersProvider: () async => o.visitor != null
          ? const []
          : _members(known is List ? known : (await post(o.endpoints.members, {'channel_id': channelId}))['data']),
      // No host to upload through: a visitor's composer is text only.
      attachmentsEnabled: o.visitor == null,
      theme: o.theme,
      logger: o.logger,
      storage: o.storage,
    );
    if (!context.mounted) return;

    final room = _Room(config: config);
    if ((presentation ?? o.presentation) == VSChatPresentation.sheet) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        enableDrag: false, // the frame's handle does it, without fighting the list
        builder: (_) => _SheetFrame(initial: o.sheetInitialSize, child: room),
      );
    } else {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => room));
    }
  }

  /// One POST to the host API. Chat is never queued offline: a room opened
  /// later, when nobody is looking, is worse than a clear error now.
  static Future<Map<String, dynamic>> post(String path, Object body) async {
    try {
      final dio = await options.api();
      // Visitor mode: every chat-service call carries the publishable key.
      final v = options.visitor;
      final data = v != null && body is Map ? {...body, 'key': v.key} : body;
      return _map((await dio.post(path, data: data)).data);
    } on DioException catch (e) {
      final data = e.response?.data;
      return data is Map
          ? _map(data)
          : {'status': 'Error', 'error_message': t('openFailed')};
    }
  }

  static Future<void> _openWith(
    BuildContext context,
    String path,
    Map<String, dynamic> body,
    VSChatPresentation? presentation,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
    final res = await post(path, body);
    nav.pop();
    if (!context.mounted) return;

    if (res['status'] == 'OK' && res['data'] is Map) {
      await open(context, _map(res['data']), presentation: presentation);
    } else {
      final msg = (res['error_message'] ?? t('openFailed')).toString();
      await (options.notify ?? _notify)(context, msg);
    }
  }

  static Future<String?> _freshToken(String channelId) async {
    final creds = _visitorCreds();
    final res = options.visitor != null
        ? (creds == null
            ? <String, dynamic>{'status': 'Error'}
            : await post('/visitor/resume', {..._visitorAuth(creds), 'topic': _visitorTopicOf(channelId)}))
        : await post(options.endpoints.openConversation, {'channel_id': channelId});
    final data = res['data'];
    return res['status'] == 'OK' && data is Map ? data['token']?.toString() : null;
  }

  /* ---- visitor mode: a public app, no backend --------------------------
   * chat-service says what to offer (GET /visitor/config) and tells the host
   * who wrote (its webhook), so the host seats its own responders. The
   * visitor is the id + secret in [VSChatOptions.storage]. Nothing here asks
   * who they are: the app's own code may, and calls [identify]. */

  /// The app's light registration: set or change the visitor's name / phone /
  /// email, at any time. Before any chat it is kept and sent with the first
  /// start. Labels the responders see, never identity.
  static Future<Map<String, dynamic>?> identify({String? name, String? phone, String? email}) async {
    final who = {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    final creds = _visitorCreds();
    if (creds == null) {
      _pendingWho.addAll(who);
      return null;
    }
    final res = await post('/visitor/identify', {..._visitorAuth(creds), ...who});
    final data = res['data'];
    if (res['status'] != 'OK' || data is! Map) {
      throw StateError((res['error_message'] ?? t('openFailed')).toString());
    }
    return _map(data['labels']);
  }

  /// This app's visitor id, or null before their first chat.
  static String? get visitorId => _visitorCreds()?.id;

  /// Forget the visitor: the next chat starts as a new one.
  static void forgetVisitor() => options.storage.remove(_visitorKey);

  static final Map<String, String> _pendingWho = {};
  static String get _visitorKey => 'vschat_visitor:${options.visitor?.key ?? ''}';

  static ({String id, String secret})? _visitorCreds() {
    final raw = options.storage.getString(_visitorKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map;
      return (id: m['id'].toString(), secret: m['secret'].toString());
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _visitorAuth(({String id, String secret}) c) =>
      {'visitor_id': c.id, 'visitor_secret': c.secret};

  /// A start answers with the secret ONCE; keep it.
  static void _rememberVisitor(Map<String, dynamic> session) {
    final secret = session['visitor_secret'];
    if (secret != null) {
      options.storage.setString(
        _visitorKey,
        jsonEncode({'id': session['user_id'].toString(), 'secret': secret.toString()}),
      );
      _pendingWho.clear();
    }
  }

  /// `visitor_<id>_<topic>`: the id holds no underscore, the topic may.
  static String _visitorTopicOf(String channelId) =>
      channelId.replaceFirst(RegExp(r'^visitor_[^_]+_'), '');

  /// The room for [topic] (created on first use), as a session to [open].
  /// A visitor chat-service no longer knows (401) starts over as a new one.
  static Future<void> _visitorOpen(
    BuildContext context,
    String topic,
    String? message,
    VSChatPresentation? presentation,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    _busy(context);
    Map<String, dynamic> body(({String id, String secret})? c) => {
          'topic': topic,
          if (message != null && message.isNotEmpty) 'message': message,
          if (c != null) ..._visitorAuth(c) else ..._pendingWho,
        };
    var creds = _visitorCreds();
    var res = await post(creds != null ? '/visitor/resume' : '/visitor/start', body(creds));
    if (creds != null && res['status_code'] == 401) {
      forgetVisitor();
      creds = null;
      res = await post('/visitor/start', body(null));
    }
    nav.pop();
    if (!context.mounted) return;

    if (res['status'] == 'OK' && res['data'] is Map) {
      final session = _map(res['data']);
      _rememberVisitor(session);
      await open(context, session, presentation: presentation);
    } else {
      await (options.notify ?? _notify)(context, (res['error_message'] ?? t('openFailed')).toString());
    }
  }

  /// The visitor's rooms, one per topic they have opened (none before their first chat).
  static Future<List<Map<String, dynamic>>> _visitorRooms() async {
    final creds = _visitorCreds();
    if (creds == null) return [];
    final res = await post('/visitor/resume', _visitorAuth(creds));
    if (res['status_code'] == 401) forgetVisitor();
    final data = res['data'];
    final rooms = res['status'] == 'OK' && data is Map ? data['rooms'] : null;
    return [
      for (final r in (rooms is List ? rooms : const []).whereType<Map>())
        {'channel_id': r['channel_id'], 'name': r['name'], 'channel_type': r['topic'], 'last_opened_at': r['created_at']},
    ];
  }

  /// What the app's admin configured: its topic buttons, or just the default
  /// topic. Each carries the one question ("How can we help?") whose answer
  /// is the visitor's first message - the deliberate start.
  static Future<List<Map<String, dynamic>>> _visitorTopics() async {
    final v = options.visitor!;
    Map<String, dynamic> cfg;
    try {
      final dio = await options.api();
      final res = _map((await dio.get('/visitor/config', queryParameters: {'key': v.key})).data);
      if (res['status'] != 'OK' || res['data'] is! Map) return [];
      cfg = _map(res['data']);
    } on DioException {
      return [];
    }
    final shown = cfg['show_topics'] == true ? cfg['topics'] : null;
    final topics = shown is List && shown.isNotEmpty
        ? shown.whereType<Map>().map((x) => {'topic': x['code'], 'name': x['name']}).toList()
        : [
            {'topic': cfg['default_topic'], 'name': null}
          ];
    return [
      for (final x in topics) {...x, 'detail_prompt': t('howCanWeHelp')},
    ];
  }

  static void _busy(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );

  static List<ChatMember> _members(Object? rows) => [
        for (final r in (rows is List ? rows : const []).whereType<Map>())
          ChatMember(
            id: (r['official_code'] ?? r['user_code'] ?? '').toString(),
            name: r['name']?.toString(),
            role: (r['role'] ?? r['user_class'])?.toString(),
          ),
      ];

  static Future<bool?> _confirm(BuildContext context, String message) =>
      showDialog<bool>(
        context: context,
        builder: (c) => _Dialog(
          icon: Icons.forum_rounded,
          message: message,
          buttons: [
            _DialogButton(label: t('no'), onTap: () => Navigator.pop(c, false)),
            _DialogButton(label: t('yes'), filled: true, onTap: () => Navigator.pop(c, true)),
          ],
        ),
      );

  static Future<void> _notify(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (c) => _Dialog(
          icon: Icons.error_outline_rounded,
          message: message,
          buttons: [_DialogButton(label: t('ok'), filled: true, onTap: () => Navigator.pop(c))],
        ),
      );

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : {'status': 'Error'};

  static List<Map<String, dynamic>> _list(Map<String, dynamic> res) =>
      res['status'] == 'OK' && res['data'] is List
          ? (res['data'] as List).whereType<Map>().map(_map).toList()
          : [];
}

/// A public app with no backend: chat-service's address and the app's
/// PUBLISHABLE key (safe to ship in an app; it opens only the visitor routes).
class VSChatVisitor {
  const VSChatVisitor({required this.baseUrl, required this.key});

  final String baseUrl;
  final String key;
}

/// Everything a host declares. Only [api] is required.
class VSChatOptions {
  VSChatOptions({
    required this.api,
    this.authorization,
    this.endpoints = const VSChatEndpoints(),
    ChatTheme? theme,
    String Function()? language,
    this.strings = const {},
    ChatLogger? logger,
    ChatStorageAdapter? storage,
    this.presentation = VSChatPresentation.page,
    this.sheetInitialSize = 0.6,
    this.confirmStart = true,
    this.confirm,
    this.notify,
  })  : visitor = null,
        theme = theme ?? ChatTheme.houExpress(),
        language = language ?? (() => 'en'),
        logger = logger ?? ConsoleLogger(),
        storage = storage ?? MemoryStorageAdapter();

  /// VISITOR mode: a public app with no backend of its own. Give it a
  /// persistent [storage] (SharedPreferencesAdapter): that is where the
  /// visitor's id + secret live, and a memory store makes every launch a new
  /// visitor. There is no Yes/No: the first message is the deliberate start.
  VSChatOptions.visitor({
    required String baseUrl,
    required String key,
    ChatTheme? theme,
    String Function()? language,
    this.strings = const {},
    ChatLogger? logger,
    ChatStorageAdapter? storage,
    this.presentation = VSChatPresentation.page,
    this.sheetInitialSize = 0.6,
    this.notify,
  })  : visitor = VSChatVisitor(baseUrl: baseUrl.replaceAll(RegExp(r'/+$'), ''), key: key),
        api = _visitorApi(baseUrl.replaceAll(RegExp(r'/+$'), '')),
        authorization = null,
        endpoints = const VSChatEndpoints(),
        confirmStart = false,
        confirm = null,
        theme = theme ?? ChatTheme.houExpress(),
        language = language ?? (() => 'en'),
        logger = logger ?? ConsoleLogger(),
        storage = storage ?? MemoryStorageAdapter();

  static Future<Dio> Function() _visitorApi(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: const {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ));
    return () async => dio;
  }

  /// Set in visitor mode; null for a signed-in host.
  final VSChatVisitor? visitor;

  /// The host's authenticated client for its chat API: base URL
  /// (`{host}/api/driver/v2`) and bearer token. Reused, never rebuilt.
  final Future<Dio> Function() api;

  /// The current `Authorization` header value, for file bytes the room
  /// loads outside [api] (images, voice notes, downloads).
  final String? Function()? authorization;

  final VSChatEndpoints endpoints;
  final ChatTheme theme;

  /// The current language code ('en', 'km'); read on every text.
  final String Function() language;

  /// Per-language text overrides: `{'km': {'title': '...'}}`.
  final Map<String, Map<String, String>> strings;
  final ChatLogger logger;

  /// Where the room keeps its theme choice (in memory by default).
  final ChatStorageAdapter storage;

  /// How [VSChat.start] and [VSChat.reopen] show a room by default.
  final VSChatPresentation presentation;

  /// The sheet's resting height, as a fraction of the screen.
  final double sheetInitialSize;

  /// Ask Yes/No before [VSChat.start] opens a room.
  final bool confirmStart;

  /// The host's own Yes/No dialog; resolves true for Yes.
  final Future<bool?> Function(BuildContext context, String message)? confirm;

  /// The host's own error dialog/snackbar.
  final Future<void> Function(BuildContext context, String message)? notify;
}

/// The host API's routes, relative to [VSChatOptions.api]'s base URL.
class VSChatEndpoints {
  const VSChatEndpoints({
    this.topics = '/chat/topics',
    this.openChannel = '/chat/open-channel',
    this.openConversation = '/chat/open-conversation',
    this.channelStatus = '/chat/channel-status',
    this.conversations = '/chat/conversations',
    this.members = '/chat/members',
  });

  final String topics;
  final String openChannel;
  final String openConversation;

  /// `{topic, subject_id?}` -> `{channel_id, member}`: is the user already in
  /// the room [start] would open? Decides whether Yes/No is asked at all.
  final String channelStatus;
  final String conversations;
  final String members;
}

/// Keeps values for the life of the app.
class MemoryStorageAdapter implements ChatStorageAdapter {
  final Map<String, Object> _m = {};

  @override
  String? getString(String key) => _m[key] as String?;

  @override
  void setString(String key, String value) => _m[key] = value;

  @override
  List<String> getStringList(String key) => (_m[key] as List<String>?) ?? const [];

  @override
  void setStringList(String key, List<String> value) => _m[key] = value;

  @override
  void remove(String key) => _m.remove(key);

  @override
  void clear() => _m.clear();
}

/// A bottom sheet with a grab handle: rests at [initial] of the screen,
/// snaps to full height when dragged up and closes when dragged well down.
class _SheetFrame extends StatefulWidget {
  const _SheetFrame({required this.initial, required this.child});

  final double initial;
  final Widget child;

  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame> {
  late double _size = widget.initial;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return AnimatedContainer(
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: h * _size,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(blurRadius: 24, color: Colors.black26)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => setState(() => _dragging = true),
          onVerticalDragUpdate: (d) => setState(
            () => _size = (_size - d.delta.dy / h).clamp(0.2, 1.0),
          ),
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (_size < widget.initial * 0.7 || v > 1200) {
              Navigator.of(context).pop();
              return;
            }
            setState(() {
              _dragging = false;
              _size = (v < -300 || _size > (widget.initial + 1) / 2) ? 1.0 : widget.initial;
            });
          },
          child: SizedBox(
            height: 22,
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
      ]),
    );
  }
}

/// One open room. ChatPage owns (and disposes) the service; this owns the
/// streams it reads.
class _Room extends StatefulWidget {
  const _Room({required this.config});

  final ChatConfig config;

  @override
  State<_Room> createState() => _RoomState();
}

class _RoomState extends State<_Room> {
  late final _streams = ChatStreams(RealChatService(config: widget.config));

  @override
  void dispose() {
    _streams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChatPage(
        channelType: widget.config.channelType,
        rxdartAdapter: _streams,
      );
}

/// A service's listener callbacks as the streams ChatPage reads - no
/// reactive library needed. Every consumer passes the current value as
/// initialData, so broadcast streams need no replay.
class ChatStreams extends NoOpChatServiceListener implements ChatReactiveAdapter {
  ChatStreams(this.chatService)
      : currentMessages = chatService.getMessagesCache(),
        currentTheme = chatService.getSelectedTheme() {
    chatService.addListener(this);
  }

  @override
  final ChatService chatService;
  @override
  List<Message> currentMessages;
  @override
  ChatTheme currentTheme;

  final _messages = StreamController<List<Message>>.broadcast();
  final _theme = StreamController<ChatTheme>.broadcast();

  @override
  Stream<List<Message>> get messagesStream => _messages.stream;
  @override
  Stream<ChatTheme> get themeStream => _theme.stream;

  @override
  void onMessagesChanged(List<Message> messages) =>
      _messages.add(currentMessages = messages);

  @override
  void onThemeChanged(ChatTheme theme) => _theme.add(currentTheme = theme);

  void dispose() {
    chatService.removeListener(this);
    _messages.close();
    _theme.close();
  }
}

/// The package's one dialog (Yes/No and notices): white card, the theme's
/// accent, grey secondary. Buttons share one row equally, so a long label
/// (Khmer runs wide) shrinks inside its own button instead of wrapping the
/// other onto a second line.
class _Dialog extends StatelessWidget {
  const _Dialog({required this.icon, required this.message, required this.buttons});

  final IconData icon;
  final String message;
  final List<_DialogButton> buttons;

  @override
  Widget build(BuildContext context) {
    final accent = VSChat.options.theme.primaryColor;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: accent.withValues(alpha: .08), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 30),
            ),
            const SizedBox(height: 18),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.45, color: Color(0xFF1F2937)),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: buttons[i]),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final accent = VSChat.options.theme.primaryColor;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final text = FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1));
    const size = Size.fromHeight(50);
    const style = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    return filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.white,
              minimumSize: size, shape: shape, elevation: 0, textStyle: style,
            ),
            child: text,
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF4B5563), backgroundColor: Colors.white,
              minimumSize: size, shape: shape, textStyle: style,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
            ),
            child: text,
          );
  }
}
