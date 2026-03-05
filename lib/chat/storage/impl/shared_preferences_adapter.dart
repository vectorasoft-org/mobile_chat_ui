import '../api/chat_storage_adapter.dart';

/// SharedPreferences adapter implementation
/// Import this in your app if using SharedPreferences
class SharedPreferencesAdapter implements ChatStorageAdapter {
  final dynamic _prefs; // SharedPreferences instance

  SharedPreferencesAdapter(this._prefs);

  @override
  String? getString(String key) {
    return _prefs.getString(key);
  }

  @override
  void setString(String key, String value) {
    _prefs.setString(key, value);
  }

  @override
  List<String> getStringList(String key) {
    return _prefs.getStringList(key) ?? [];
  }

  @override
  void setStringList(String key, List<String> value) {
    _prefs.setStringList(key, value);
  }

  @override
  void remove(String key) {
    _prefs.remove(key);
  }

  @override
  void clear() {
    _prefs.clear();
  }
}
