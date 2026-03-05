import '../api/chat_storage_adapter.dart';

/// In-memory storage adapter for testing
class MemoryStorageAdapter implements ChatStorageAdapter {
  final Map<String, dynamic> _data = {};

  @override
  String? getString(String key) {
    return _data[key] as String?;
  }

  @override
  void setString(String key, String value) {
    _data[key] = value;
  }

  @override
  List<String> getStringList(String key) {
    return (_data[key] as List<String>?) ?? [];
  }

  @override
  void setStringList(String key, List<String> value) {
    _data[key] = value;
  }

  @override
  void remove(String key) {
    _data.remove(key);
  }

  @override
  void clear() {
    _data.clear();
  }
}
