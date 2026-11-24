import 'package:flutter_test/flutter_test.dart';
import 'package:vs_chat_flutter/chat/config/chat_logger.dart';
import 'package:vs_chat_flutter/chat/config/chat_offline.dart';
import 'package:vs_chat_flutter/chat/offline/offline_store.dart';
import 'package:vs_chat_flutter/chat/storage/impl/memory_storage_adapter.dart';

/// A logger that says nothing, so a passing test prints nothing.
class _Quiet implements ChatLogger {
  @override
  void i(String message) {}
  @override
  void d(String message) {}
  @override
  void w(String message) {}
  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) {}
  @override
  void t(String message) {}
}

void main() {
  late MemoryStorageAdapter storage;
  final logger = _Quiet();

  OfflineStore store({
    String? userId = 'userA',
    String? channelId = 'ch1',
    ChatOffline settings = const ChatOffline(queue: true, cache: true),
  }) =>
      OfflineStore(
        storage: storage,
        settings: settings,
        logger: logger,
        userId: userId,
        channelId: channelId,
      );

  setUp(() => storage = MemoryStorageAdapter());

  group('switches', () {
    test('both halves are off by default', () {
      final s = store(settings: ChatOffline.off);
      expect(s.queueOn, isFalse);
      expect(s.cacheOn, isFalse);
      expect(ChatOffline.off.enabled, isFalse);
    });

    test('an unknown user disables both, whatever the host asked for', () {
      final s = store(userId: null);
      expect(s.queueOn, isFalse, reason: 'nothing may be filed without a user');
      expect(s.cacheOn, isFalse);
      expect(s.enqueue('hello'), isNull);
      expect(storage.getString('vschat.keys'), isNull);
    });

    test('an unknown room disables both', () {
      expect(store(channelId: null).queueOn, isFalse);
      expect(store(channelId: '').cacheOn, isFalse);
    });

    test('an off outbox refuses to enqueue', () {
      expect(store(settings: const ChatOffline(cache: true)).enqueue('x'), isNull);
    });
  });

  group('the outbox', () {
    test('keeps a message and reads it back', () {
      final row = store().enqueue('hello');
      expect(row, isNotNull);
      final rows = store().readQueue();
      expect(rows, hasLength(1));
      expect(rows.single.text, 'hello');
      expect(rows.single.nonce, row!.nonce);
    });

    test('keeps order - oldest first', () {
      store().enqueue('one');
      store().enqueue('two');
      store().enqueue('three');
      expect(
        store().readQueue().map((r) => r.text).toList(),
        ['one', 'two', 'three'],
      );
    });

    test('stops at maxQueued instead of growing without bound', () {
      final s = store(settings: const ChatOffline(queue: true, maxQueued: 2));
      expect(s.enqueue('a'), isNotNull);
      expect(s.enqueue('b'), isNotNull);
      expect(s.enqueue('c'), isNull, reason: 'full, and it must say so');
      expect(s.readQueue(), hasLength(2));
    });

    test('drop removes one row and leaves the others', () {
      final a = store().enqueue('a')!;
      store().enqueue('b');
      store().drop(a.nonce);
      expect(store().readQueue().map((r) => r.text), ['b']);
    });

    test('an empty queue leaves no key behind', () {
      final a = store().enqueue('a')!;
      store().drop(a.nonce);
      expect(storage.getString('vschat.q.userA.ch1'), isNull);
    });

    test('tooOld is measured from when Send was pressed', () {
      final s = store(
        settings: const ChatOffline(queue: true, maxAge: Duration(hours: 1)),
      );
      final fresh = QueuedMessage(
        nonce: 'n1',
        text: 'fresh',
        at: DateTime.now(),
      );
      final stale = QueuedMessage(
        nonce: 'n2',
        text: 'stale',
        at: DateTime.now().subtract(const Duration(hours: 2)),
      );
      expect(s.tooOld(fresh), isFalse);
      expect(s.tooOld(stale), isTrue);
    });

    test('maxAge zero means it waits forever', () {
      final s = store(
        settings: const ChatOffline(queue: true, maxAge: Duration.zero),
      );
      final ancient = QueuedMessage(
        nonce: 'n',
        text: 'old',
        at: DateTime(2020),
      );
      expect(s.tooOld(ancient), isFalse);
    });

    test('unreadable stored JSON is dropped, not retried', () {
      storage.setString('vschat.q.userA.ch1', 'not json at all');
      expect(store().readQueue(), isEmpty);
      expect(storage.getString('vschat.q.userA.ch1'), isNull);
    });
  });

  group('scoping - one device, many users', () {
    test('another user cannot read this one\'s queue', () {
      store(userId: 'userA').enqueue('A secret');
      expect(store(userId: 'userB').readQueue(), isEmpty);
      expect(store(userId: 'userA').readQueue(), hasLength(1));
    });

    test('another room cannot read this one\'s queue', () {
      store(channelId: 'ch1').enqueue('about ch1');
      expect(store(channelId: 'ch2').readQueue(), isEmpty);
    });

    test('another user cannot read this one\'s saved page', () {
      store(userId: 'userA').writeCache([
        {'id': 'm1', 'text': 'A secret'},
      ]);
      expect(store(userId: 'userB').readCache(), isNull);
      expect(store(userId: 'userA').readCache(), hasLength(1));
    });
  });

  group('the saved page', () {
    test('round-trips the rows', () {
      store().writeCache([
        {'id': 'm1', 'text': 'first'},
        {'id': 'm2', 'text': 'second'},
      ]);
      final saved = store().readCache();
      expect(saved, hasLength(2));
      expect(saved!.first['text'], 'first');
    });

    test('an empty page is not written', () {
      store().writeCache([]);
      expect(store().readCache(), isNull);
    });

    test('is not read when the cache half is off', () {
      store().writeCache([
        {'id': 'm1'},
      ]);
      expect(store(settings: const ChatOffline(queue: true)).readCache(), isNull);
    });
  });

  group('forgetting', () {
    test('forgetRoom clears this room only', () {
      store(channelId: 'ch1').enqueue('one');
      store(channelId: 'ch2').enqueue('two');
      store(channelId: 'ch1').forgetRoom();
      expect(store(channelId: 'ch1').readQueue(), isEmpty);
      expect(store(channelId: 'ch2').readQueue(), hasLength(1));
    });

    test('forgetAll clears every user and room this feature wrote', () {
      store(userId: 'userA').enqueue('a');
      store(userId: 'userB').enqueue('b');
      store(userId: 'userA').writeCache([
        {'id': 'm'},
      ]);
      OfflineStore.forgetAll(storage);
      expect(store(userId: 'userA').readQueue(), isEmpty);
      expect(store(userId: 'userB').readQueue(), isEmpty);
      expect(store(userId: 'userA').readCache(), isNull);
    });

    /// The host usually hands over its OWN store - the same one holding the
    /// app's login. Wiping that would be a far worse bug than any this
    /// feature fixes, so forgetting must be surgical.
    test('forgetAll never touches a key this feature did not write', () {
      storage.setString('userData', '{"official_code":"userA"}');
      storage.setString('selectedTheme', 'dark');
      store().enqueue('mine');
      OfflineStore.forgetAll(storage);
      expect(storage.getString('userData'), '{"official_code":"userA"}',
          reason: 'the host login must survive');
      expect(storage.getString('selectedTheme'), 'dark');
      expect(store().readQueue(), isEmpty);
    });
  });

  group('identity changes', () {
    test('a different member signing in clears the previous one', () {
      OfflineStore.noteIdentity(storage, 'userA');
      store(userId: 'userA').enqueue('A secret');
      OfflineStore.noteIdentity(storage, 'userB');
      expect(store(userId: 'userA').readQueue(), isEmpty,
          reason: 'userB must not inherit userA\'s unsent text');
    });

    test('the same member signing in again keeps their queue', () {
      OfflineStore.noteIdentity(storage, 'userA');
      store().enqueue('still mine');
      OfflineStore.noteIdentity(storage, 'userA');
      expect(store().readQueue(), hasLength(1));
    });

    test('signing out clears what was held', () {
      OfflineStore.noteIdentity(storage, 'userA');
      store().enqueue('mine');
      OfflineStore.noteIdentity(storage, null);
      expect(store().readQueue(), isEmpty);
    });

    test('an identity change leaves the host\'s own keys alone', () {
      storage.setString('userData', 'host-owned');
      OfflineStore.noteIdentity(storage, 'userA');
      store().enqueue('mine');
      OfflineStore.noteIdentity(storage, 'userB');
      expect(storage.getString('userData'), 'host-owned');
    });
  });
}
