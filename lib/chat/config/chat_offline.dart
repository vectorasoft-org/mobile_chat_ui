/// How much of a room survives a dead network.
///
/// Both switches are OFF, so a host that says nothing keeps exactly today's
/// behaviour: a send needs the socket, a room needs the network. Turn one on
/// for the surfaces whose users lose signal - a driver in a basement, a
/// merchant on 4G at the edge of a village.
///
/// The same option names and defaults exist in the web widget
/// (`vschat.js`, `cfg.offline`), so one rule describes both surfaces.
class ChatOffline {
  const ChatOffline({
    this.queue = false,
    this.cache = false,
    this.maxAge = const Duration(days: 1),
    this.maxQueued = 50,
    this.banner = true,
  });

  /// Everything off - the default, and what a host gets by saying nothing.
  static const ChatOffline off = ChatOffline();

  /// An outbox for the room ALREADY on screen: the composer keeps working
  /// with the socket down, and each message flushes IN ORDER on reconnect.
  ///
  /// Opening a NEW room still fails fast. A room that appears later, when
  /// nobody is looking, is worse than a clear error now - the same rule
  /// `VSChat.post` has always stated.
  ///
  /// Text only. An attachment's bytes need an upload, so one composed with no
  /// network is refused outright rather than silently lost.
  final bool queue;

  /// Keep the newest page of each room so it opens READABLE with no network.
  ///
  /// The cache is never the truth, only something to read meanwhile: the next
  /// fetch that succeeds replaces what is on screen.
  final bool cache;

  /// How long a queued message may wait before it is dropped instead of
  /// delivered. Hours-old text landing in a conversation that has moved on,
  /// notifying every member, is its own bug. [Duration.zero] waits forever.
  final Duration maxAge;

  /// Most messages held per room.
  final int maxQueued;

  /// Show the "no connection" strip above the composer.
  final bool banner;

  /// Is either half on?
  bool get enabled => queue || cache;

  ChatOffline copyWith({
    bool? queue,
    bool? cache,
    Duration? maxAge,
    int? maxQueued,
    bool? banner,
  }) =>
      ChatOffline(
        queue: queue ?? this.queue,
        cache: cache ?? this.cache,
        maxAge: maxAge ?? this.maxAge,
        maxQueued: maxQueued ?? this.maxQueued,
        banner: banner ?? this.banner,
      );

  @override
  String toString() =>
      'ChatOffline(queue: $queue, cache: $cache, maxAge: $maxAge, '
      'maxQueued: $maxQueued, banner: $banner)';
}
