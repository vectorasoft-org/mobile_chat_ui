/// Abstract storage adapter for the chat module
/// Apps can provide SharedPreferences, Hive, or custom implementation
abstract class ChatStorageAdapter {
  /// Get a string value by key
  String? getString(String key);

  /// Set a string value by key
  void setString(String key, String value);

  /// Get a list of strings by key
  List<String> getStringList(String key);

  /// Set a list of strings by key
  void setStringList(String key, List<String> value);

  /// Remove a key
  void remove(String key);

  /// Clear all data
  void clear();
}
