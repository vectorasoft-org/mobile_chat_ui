import 'dart:developer' as developer;

/// Abstract logger interface for the chat module
/// Apps can provide their own implementation (KLogger, Logger, SLogger, etc.)
abstract class ChatLogger {
  void i(String message);
  void d(String message);
  void w(String message);
  void e(String message, {Object? error, StackTrace? stackTrace});
}

/// Simple console logger implementation using dart:developer
/// Use this if your app doesn't have a logger, or provide your own
class ConsoleLogger implements ChatLogger {
  @override
  void i(String message) => developer.log('[INFO] $message', level: 800);

  @override
  void d(String message) => developer.log('[DEBUG] $message', level: 0);

  @override
  void w(String message) => developer.log('[WARN] $message', level: 900);

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) {
    final formattedMsg =
        '[ERROR] $message${error != null ? '  Error: $error' : ''}';
    developer.log(
      formattedMsg,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
