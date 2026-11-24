import 'dart:convert';

import '../config/chat_logger.dart';
import '../config/chat_offline.dart';
import '../storage/api/chat_storage_adapter.dart';

/// One message the user sent while the wire was down.
///
/// [at] is when they pressed Send - that is what [ChatOffline.maxAge] is
/// measured against, not when the flush happens. [nonce] travels to
/// chat-service as `client_nonce` so a replay COULD be recognised one day;
/// it is not recognised today, which is exactly why a message already put on
/// the wire is never re-sent automatically.
class QueuedMessage {
  QueuedMessage({required this.nonce, required this.text, required this.at});

  final String nonce;
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'nonce': nonce,
        'text': text,
        'at': at.millisecondsSinceEpoch,
      };

  static QueuedMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final nonce = raw['nonce']?.toString();
    final text = raw['text']?.toString();
    final at = raw['at'];
    if (nonce == null || nonce.isEmpty || text == null || at is! int) {
      return null;
    }
    return QueuedMessage(
      nonce: nonce,
      text: text,
      at: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }
}

/// The outbox and the newest-page cache, on top of whatever
/// [ChatStorageAdapter] the host supplied.
///
/// Every key is scoped to WHO and WHICH ROOM:
/// ```text
///   vschat.q.<user_id>.<channel_id>   queued outgoing text
///   vschat.c.<user_id>.<channel_id>   the newest page, to read offline
/// ```
/// With no user id nothing is written at all: an unscoped key is how one
/// person ends up reading another's chat on a shared device.
///
/// IMPORTANT, twice over:
///  * The default [ChatStorageAdapter] is in MEMORY. A host that wants the
///    outbox to survive the app being killed must pass a persistent adapter
///    ([SharedPreferencesAdapter]); the store logs once when it notices.
///  * That adapter is usually the HOST's own store - the same one holding
///    `userData`. So nothing here ever calls [ChatStorageAdapter.clear]:
///    forgetting works off an index of the keys this feature wrote, and
///    touches nothing else.
class OfflineStore {
  OfflineStore({
    required this.storage,
    required this.settings,
    required this.logger,
    required this.userId,
    required this.channelId,
  });

  final ChatStorageAdapter storage;
  final ChatOffline settings;
  final ChatLogger logger;
  final String? userId;
  final String? channelId;

  static const _whoKey = 'vschat.who';
  static const _indexKey = 'vschat.keys';

  bool get _scoped =>
      (userId != null && userId!.isNotEmpty) &&
      (channelId != null && channelId!.isNotEmpty);

  /// The outbox is usable: the host asked for it AND there is an identity to
  /// file it under.
  bool get queueOn => settings.queue && _scoped;

  /// The cache is usable, on the same two conditions.
  bool get cacheOn => settings.cache && _scoped;

  String get _qKey => 'vschat.q.$userId.$channelId';
  String get _cKey => 'vschat.c.$userId.$channelId';

  /// Remember that this feature owns [key], so [forgetAll] can find it later.
  /// The adapter cannot enumerate, and guessing is not an option when the
  /// alternative is deleting a host's own data.
  void _own(String key) {
    final list = storage.getStringList(_indexKey);
    if (list.contains(key)) return;
    storage.setStringList(_indexKey, [...list, key]);
  }

  // ------------------------------- the outbox -------------------------------

  /// Oldest first - the order they must go out in.
  List<QueuedMessage> readQueue() {
    if (!queueOn) return const [];
    final raw = storage.getString(_qKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <QueuedMessage>[];
      for (final r in list) {
        final m = QueuedMessage.fromJson(r);
        if (m != null) out.add(m);
      }
      return out;
    } catch (e) {
      // Unreadable is the same as absent, and better forgotten than retried.
      logger.w('[offline] queue unreadable, dropping it: $e');
      storage.remove(_qKey);
      return const [];
    }
  }

  void _writeQueue(List<QueuedMessage> rows) {
    if (!queueOn) return;
    if (rows.isEmpty) {
      storage.remove(_qKey);
      return;
    }
    storage.setString(_qKey, jsonEncode([for (final r in rows) r.toJson()]));
    _own(_qKey);
  }

  /// Keep [text] for the next reconnect.
  ///
  /// Returns null when the outbox is off or already full - the caller must
  /// then TELL the user, never drop it quietly.
  QueuedMessage? enqueue(String text) {
    if (!queueOn) return null;
    final rows = readQueue().toList();
    if (rows.length >= settings.maxQueued) {
      logger.w('[offline] outbox full (${settings.maxQueued}); refusing');
      return null;
    }
    final row = QueuedMessage(
      nonce: 'n-${DateTime.now().microsecondsSinceEpoch}-${rows.length}',
      text: text,
      at: DateTime.now(),
    );
    rows.add(row);
    _writeQueue(rows);
    return row;
  }

  void drop(String nonce) => _writeQueue(
      [for (final r in readQueue()) if (r.nonce != nonce) r]);

  /// Has this row waited so long that delivering it would do harm?
  bool tooOld(QueuedMessage row) =>
      settings.maxAge > Duration.zero &&
      DateTime.now().difference(row.at) > settings.maxAge;

  // -------------------------- the newest-page cache -------------------------

  /// The saved page, or null when there is none.
  ///
  /// Only ever a stand-in: the next successful fetch replaces what is on
  /// screen, so it cannot harden into a wrong version of the history.
  List<Map<String, dynamic>>? readCache() {
    if (!cacheOn) return null;
    final raw = storage.getString(_cKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final body = jsonDecode(raw);
      final rows = body is Map ? body['rows'] : null;
      if (rows is! List || rows.isEmpty) return null;
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        if (r is Map) out.add(r.cast<String, dynamic>());
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      logger.w('[offline] saved page unreadable, dropping it: $e');
      storage.remove(_cKey);
      return null;
    }
  }

  /// Keep the newest page, and only that page: older ones are a scroll away
  /// whenever there is a wire, and are not worth holding on the device.
  void writeCache(List<Map<String, dynamic>> rows) {
    if (!cacheOn || rows.isEmpty) return;
    try {
      storage.setString(
        _cKey,
        jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'rows': rows}),
      );
      _own(_cKey);
    } catch (e) {
      // Losing the cache is survivable; throwing inside a render is not.
      logger.w('[offline] could not save the newest page: $e');
    }
  }

  // ------------------------------- forgetting -------------------------------

  /// Drop what was kept for THIS user and room.
  void forgetRoom() {
    storage.remove(_qKey);
    storage.remove(_cKey);
  }

  /// Drop everything this feature ever wrote, for every user, and nothing
  /// else. Call it on sign-out.
  static void forgetAll(ChatStorageAdapter storage) {
    for (final k in storage.getStringList(_indexKey)) {
      storage.remove(k);
    }
    storage.remove(_indexKey);
    storage.remove(_whoKey);
  }

  /// One device serves many users in turn. Call this with whoever is signing
  /// in: if that is not who was here last, everything the previous person
  /// left behind is removed first.
  static void noteIdentity(ChatStorageAdapter storage, String? userId) {
    final now = userId ?? '';
    final seen = storage.getString(_whoKey);
    if (seen != null && seen != now) forgetAll(storage);
    if (now.isEmpty) {
      storage.remove(_whoKey);
    } else {
      storage.setString(_whoKey, now);
    }
  }
}
