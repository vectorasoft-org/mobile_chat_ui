import 'dart:async';

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

  /// Ask Yes/No (unless [VSChatOptions.confirmStart] is off), then open the
  /// room for [topic] about [subjectId]. Opening notifies every member, so a
  /// careless tap must not do it.
  static Future<void> start(
    BuildContext context, {
    required String topic,
    String? subjectId,
    VSChatPresentation? presentation,
  }) async {
    final o = options;
    if (o.confirmStart) {
      final ok = await (o.confirm ?? _confirm)(context, t('confirmStart'));
      if (ok != true || !context.mounted) return;
    }
    await _openWith(
      context,
      o.endpoints.openChannel,
      {
        'topic': topic,
        if (subjectId != null && subjectId.isNotEmpty) 'subject_id': subjectId,
      },
      presentation,
    );
  }

  /// Reopen a room the user is already in. No question: nobody new is told.
  static Future<void> reopen(
    BuildContext context,
    String channelId, {
    VSChatPresentation? presentation,
  }) =>
      _openWith(
        context,
        options.endpoints.openConversation,
        {'channel_id': channelId},
        presentation,
      );

  /// The rooms the user is in, most recently opened first.
  static Future<List<Map<String, dynamic>>> conversations() async =>
      _list(await post(options.endpoints.conversations, {}));

  /// The topics this user may start a chat about.
  static Future<List<Map<String, dynamic>>> topics() async =>
      _list(await post(options.endpoints.topics, {}));

  /// The subjects matching a topic's prompt; null (and [onError]) on failure.
  static Future<List<Map<String, dynamic>>?> findSubjects(
    String topic,
    Map<String, String> fields, {
    required void Function(String message) onError,
  }) async {
    final res = await post(options.endpoints.findSubject, {
      'topic': topic,
      ...fields,
    });
    if (res['status'] != 'OK') {
      onError((res['error_message'] ?? t('openFailed')).toString());
      return null;
    }
    return _list(res);
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
      membersProvider: () async => _members(
        known is List ? known : (await post(o.endpoints.members, {'channel_id': channelId}))['data'],
      ),
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
      return _map((await dio.post(path, data: body)).data);
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
    final res = await post(options.endpoints.openConversation, {
      'channel_id': channelId,
    });
    final data = res['data'];
    return res['status'] == 'OK' && data is Map ? data['token']?.toString() : null;
  }

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
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: Icon(Icons.forum_rounded, color: options.theme.primaryColor, size: 36),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('no')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: options.theme.primaryColor),
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('yes')),
            ),
          ],
        ),
      );

  static Future<void> _notify(BuildContext context, String message) =>
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.error_outline_rounded, color: Color(0xFFD32F2F), size: 36),
          content: Text(message, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: options.theme.primaryColor),
              onPressed: () => Navigator.pop(c),
              child: Text(t('ok')),
            ),
          ],
        ),
      );

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : {'status': 'Error'};

  static List<Map<String, dynamic>> _list(Map<String, dynamic> res) =>
      res['status'] == 'OK' && res['data'] is List
          ? (res['data'] as List).whereType<Map>().map(_map).toList()
          : [];
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
  })  : theme = theme ?? ChatTheme.houExpress(),
        language = language ?? (() => 'en'),
        logger = logger ?? ConsoleLogger(),
        storage = storage ?? MemoryStorageAdapter();

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
    this.findSubject = '/chat/find-subject',
    this.openChannel = '/chat/open-channel',
    this.openConversation = '/chat/open-conversation',
    this.conversations = '/chat/conversations',
    this.members = '/chat/members',
  });

  final String topics;
  final String findSubject;
  final String openChannel;
  final String openConversation;
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
