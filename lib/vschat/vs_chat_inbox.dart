import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'vs_chat.dart';

/// One arriving message, as the inbox socket reported it. Emitted on
/// [VSChatInbox.lastAlert] so a host can render its own alert instead of (or
/// beside) the built-in banner.
class VSChatIncoming {
  const VSChatIncoming({
    required this.channelId,
    this.author,
    this.preview,
    this.messageId,
    this.at,
  });

  final String channelId;

  /// Who sent it, already resolved to a display name by the engine.
  final String? author;

  /// The first ~120 characters, or `[attachment]`.
  final String? preview;
  final String? messageId;
  final String? at;
}

/// Live unread counts - the Flutter twin of the web widget's inbox socket.
///
/// One lightweight socket per signed-in app, opened once (after sign-in) and
/// joined to NO channel: chat-service seats every socket in its user's own
/// room, where `unread-changed` arrives for every one of the user's channels.
/// The counters here only increment on events; `unread-summary` on every
/// (re)connect is the source of truth, so a missed event heals itself. A read
/// in ANY of the user's sessions (this phone, the portal) zeroes here too.
///
/// ```dart
/// VSChat.init(...);
/// VSChatInbox.start();                                   // after sign-in
/// VSChatUnreadBadge(child: Icon(Icons.chat_bubble));     // any chat icon
/// VSChatInbox.stop();                                    // on sign-out
/// ```
class VSChatInbox {
  VSChatInbox._();

  /// The badge: every unread message in every channel, live.
  static final ValueNotifier<int> total = ValueNotifier<int>(0);

  /// Per-channel unread, for conversation rows. Changes with [total].
  static final ValueNotifier<Map<String, int>> counts =
      ValueNotifier<Map<String, int>>(const {});

  /// The most recent arrival, for hosts that want to draw their own attention
  /// (a custom banner, a local notification). Fires only when the count MOVES -
  /// never on the reconnect resync, never for the room on screen.
  static final ValueNotifier<VSChatIncoming?> lastAlert =
      ValueNotifier<VSChatIncoming?>(null);

  static io.Socket? _socket;
  static bool _starting = false;
  static String? _watching; // the room on screen reads itself

  static int countOf(String channelId) => counts.value[channelId] ?? 0;

  /// Idempotent. Quietly a no-op for a visitor app, and while the user has
  /// no chat identity on the engine yet (their first chat creates it) - call
  /// again after sign-in or from the Chat page.
  static Future<void> start() async {
    if (_socket != null || _starting || VSChat.options.visitor != null) return;
    _starting = true;
    try {
      final first = await _session();
      if (first == null) return;
      var firstToken = first['token']?.toString();
      final s = io.io(
        first['base_url'].toString(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            // Tokens are single-use: the first connect uses the one just
            // minted, every reconnect mints again.
            .setAuthFn((callback) {
              final t = firstToken;
              firstToken = null;
              (t != null
                      ? Future.value(t)
                      : _session().then((x) => x?['token']?.toString()))
                  .then((tok) => callback(
                      {'api_key': first['api_key'].toString(), 'token': tok}))
                  .catchError((Object e) {
                VSChat.options.logger.e('[inbox] token refresh failed', error: e);
              });
            })
            .enableForceNew()
            .build(),
      );
      _socket = s;
      s.onConnect((_) => _pullSummary());
      s.on('unread-changed', _onChanged);
      s.connect();
    } finally {
      _starting = false;
    }
  }

  /// On sign-out: drop the socket and the counters.
  static void stop() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    total.value = 0;
    counts.value = const {};
  }

  /// The room being LOOKED at (set by [VSChat.open], cleared when it closes):
  /// its events mark read instead of counting.
  static void watching(String? channelId) {
    _watching = channelId;
    if (channelId != null) markRead(channelId);
  }

  /// The member has seen [channelId] up to now. Zeroes locally at once; the
  /// engine echoes a read sync to the user's other sessions.
  static void markRead(String channelId) {
    _zero(channelId);
    final s = _socket;
    if (s != null && s.connected) {
      // With an ack: the server's handler always answers one.
      s.emitWithAck('mark-read', [
        {'channel_id': channelId},
      ], ack: (dynamic _) {});
    }
  }

  static Future<Map<String, dynamic>?> _session() async {
    try {
      final res = await VSChat.post(VSChat.options.endpoints.token, {});
      final d = res['data'];
      if (res['status'] == 'OK' && d is Map && d['token'] != null) {
        return Map<String, dynamic>.from(d);
      }
    } catch (e) {
      VSChat.options.logger.w('[inbox] no session: $e');
    }
    return null;
  }

  static void _pullSummary() {
    _socket?.emitWithAck('unread-summary', [], ack: (dynamic res) {
      final d = res is Map ? res['data'] : null;
      if (d is! Map) return;
      final next = <String, int>{};
      for (final c in (d['channels'] is List ? d['channels'] as List : const [])) {
        if (c is Map) {
          next[c['channel_id'].toString()] =
              int.tryParse(c['unread'].toString()) ?? 0;
        }
      }
      counts.value = next;
      total.value = int.tryParse(d['total'].toString()) ?? 0;
    });
  }

  static void _onChanged(dynamic ev) {
    if (ev is! Map) return;
    final channelId = ev['channel_id']?.toString();
    if (channelId == null) return;
    if (ev['read'] == true) return _zero(channelId); // read in any session
    if (channelId == _watching) return markRead(channelId); // on screen now
    final next = Map<String, int>.from(counts.value);
    next[channelId] = (next[channelId] ?? 0) + 1;
    counts.value = next;
    total.value = total.value + 1;
    _announce(VSChatIncoming(
      channelId: channelId,
      author: ev['author']?.toString(),
      preview: ev['preview']?.toString(),
      messageId: ev['message_id']?.toString(),
      at: ev['at']?.toString(),
    ));
  }

  /// Draw the user's attention, quietest layer first. The badge pulse rides on
  /// [total] inside [VSChatUnreadBadge]; everything else happens here.
  static void _announce(VSChatIncoming ev) {
    lastAlert.value = ev;
    // An alert must never cost the user their unread count: the count is
    // already committed by here, so anything below fails on its own.
    try {
      final a = VSChat.options.alerts;
      if (a.haptic) {
        // Never let a device without a vibrator break the alert.
        HapticFeedback.mediumImpact().catchError((Object _) {});
      }
      if (a.sound) {
        SystemSound.play(SystemSoundType.alert).catchError((Object _) {});
      }
      if (a.toast) _showBanner(ev);
    } catch (e) {
      VSChat.options.logger.w('[inbox] alert skipped: $e');
    }
  }

  /// The overlay to hang the banner on, whichever kind of context the host
  /// handed us.
  ///
  /// `Get.overlayContext` is the Overlay's OWN context, and `Overlay.maybeOf`
  /// only ever walks ANCESTORS - so it cannot see that overlay and returns
  /// null. Read the state off the element first, then fall back to the normal
  /// lookups for a host that passes an ordinary page context instead.
  static OverlayState? _overlayFrom(BuildContext ctx) {
    if (ctx is StatefulElement && ctx.state is OverlayState) {
      return ctx.state as OverlayState;
    }
    return Overlay.maybeOf(ctx, rootOverlay: true) ??
        Overlay.maybeOf(ctx) ??
        Navigator.maybeOf(ctx)?.overlay;
  }

  /// The built-in banner. Silently skipped when the host gave no
  /// [VSChatOptions.overlayContext] - [lastAlert] is still there to build on.
  static void _showBanner(VSChatIncoming ev) {
    final ctx = VSChat.options.overlayContext?.call();
    if (ctx == null) {
      VSChat.options.logger.w(
          '[inbox] banner skipped: no overlayContext. Pass '
          'overlayContext: () => Get.overlayContext to VSChatOptions, and make '
          'sure this is a hot RESTART - options are built once, at startup.');
      return;
    }
    final overlay = _overlayFrom(ctx);
    if (overlay == null) {
      VSChat.options.logger.w(
          '[inbox] banner skipped: no Overlay reachable from that context.');
      return;
    }
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _VSChatAlertBanner(
        event: ev,
        duration: VSChat.options.alerts.toastDuration,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
        onTap: () {
          if (entry.mounted) entry.remove();
          final c = VSChat.options.overlayContext?.call();
          if (c != null) VSChat.reopen(c, ev.channelId);
        },
      ),
    );
    overlay.insert(entry);
  }

  static void _zero(String channelId) {
    final had = counts.value[channelId] ?? 0;
    if (had == 0) return;
    final next = Map<String, int>.from(counts.value)..remove(channelId);
    counts.value = next;
    total.value = (total.value - had).clamp(0, 1 << 31);
  }
}

/// Wrap any chat icon: a live unread count rides on it.
///
/// ```dart
/// VSChatUnreadBadge(child: Icon(Icons.chat_bubble_outline))
/// ```
class VSChatUnreadBadge extends StatefulWidget {
  const VSChatUnreadBadge({super.key, required this.child, this.color});

  final Widget child;

  /// The pill's color; the theme's primary by default.
  final Color? color;

  @override
  State<VSChatUnreadBadge> createState() => _VSChatUnreadBadgeState();
}

class _VSChatUnreadBadgeState extends State<VSChatUnreadBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 1.45, end: 0.92), weight: 35),
    TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0), weight: 30),
  ]).animate(CurvedAnimation(parent: _c, curve: Curves.easeOut));

  int _last = VSChatInbox.total.value;

  @override
  void initState() {
    super.initState();
    VSChatInbox.total.addListener(_onTotal);
  }

  /// Pop only when the count GOES UP: reading elsewhere drops it, and that
  /// should never draw the eye back.
  void _onTotal() {
    final n = VSChatInbox.total.value;
    final rose = n > _last;
    _last = n;
    if (rose && VSChat.options.alerts.pulse && mounted) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    VSChatInbox.total.removeListener(_onTotal);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: VSChatInbox.total,
        builder: (_, n, child) => Badge(
          isLabelVisible: n > 0,
          backgroundColor: widget.color ?? VSChat.options.theme.primaryColor,
          label: ScaleTransition(
            scale: _scale,
            child: Text(n > 99 ? '99+' : '$n'),
          ),
          child: child,
        ),
        child: widget.child,
      );
}

/// The in-app banner: slides down from the top, taps through to the room, and
/// leaves on its own. Built by [VSChatInbox] as an overlay entry, so it rides
/// over whatever screen the user is on.
class _VSChatAlertBanner extends StatefulWidget {
  const _VSChatAlertBanner({
    required this.event,
    required this.duration,
    required this.onDismiss,
    required this.onTap,
  });

  final VSChatIncoming event;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  State<_VSChatAlertBanner> createState() => _VSChatAlertBannerState();
}

class _VSChatAlertBannerState extends State<_VSChatAlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.duration, _leave);
  }

  Future<void> _leave() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    await _c.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = VSChat.options.theme.primaryColor;
    final who = widget.event.author?.trim();
    final title = (who == null || who.isEmpty) ? 'New message' : who;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, -0.35), end: Offset.zero)
            .animate(curve),
        child: FadeTransition(
          opacity: curve,
          child: Material(
            color: Colors.transparent,
            child: Dismissible(
              key: ValueKey(widget.event.messageId ?? widget.event.channelId),
              direction: DismissDirection.up,
              onDismissed: (_) => widget.onDismiss(),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(14),
                child: Ink(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border(left: BorderSide(color: primary, width: 4)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: primary,
                        child: Text(
                          title.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            if ((widget.event.preview ?? '').isNotEmpty)
                              Text(
                                widget.event.preview!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.color,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                        onPressed: _leave,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
