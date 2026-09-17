import 'package:just_audio/just_audio.dart';
import '../config/chat_config.dart';
import '../config/chat_logger.dart';

class AudioPlayerController {
  static AudioPlayerController? _instance;

  late AudioPlayer _audioPlayer;
  String? _currentMessageId;
  late final ChatLogger _logger;
  final ChatConfig? _config;

  /// Headers used when streaming audio directly from a URL.
  Map<String, String> get _httpHeaders =>
      _config?.httpAuthHeaders() ?? const {};

  factory AudioPlayerController({
    required ChatLogger logger,
    ChatConfig? config,
  }) {
    _instance ??= AudioPlayerController._internal(logger, config);
    return _instance!;
  }

  AudioPlayerController._internal(ChatLogger logger, ChatConfig? config)
    : _audioPlayer = AudioPlayer(),
      _logger = logger,
      _config = config;

  AudioPlayer get player => _audioPlayer;

  String? get currentMessageId => _currentMessageId;

  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  Future<void> setAudioSource(String messageId, String audioUrl) async {
    // Stop and reset if a different audio is being played
    if (_currentMessageId != null && _currentMessageId != messageId) {
      _logger.i(
        '[AUDIO_CONTROLLER] setAudioSource - Stopping previous audio: $_currentMessageId, loading new: $messageId',
      );
      await _audioPlayer.stop();
      await _audioPlayer.seek(Duration.zero);
    }

    _currentMessageId = messageId;
    _logger.i(
      '[AUDIO_CONTROLLER] setAudioSource - Setting URL for $messageId: $audioUrl',
    );

    try {
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(audioUrl),
          headers: _httpHeaders,
        ),
      );
      _logger.i(
        '[AUDIO_CONTROLLER] setAudioSource - Success, got duration: ${_audioPlayer.duration}',
      );
    } catch (e) {
      _logger.e('[AUDIO_CONTROLLER] setAudioSource - Error: $e', error: e);
      rethrow;
    }
  }

  Future<void> setAudioSourceFromFile(String messageId, String filePath) async {
    // Stop and reset if a different audio is being played
    if (_currentMessageId != null && _currentMessageId != messageId) {
      _logger.i(
        '[AUDIO_CONTROLLER] setAudioSourceFromFile - Stopping previous audio: $_currentMessageId, loading new: $messageId',
      );
      await _audioPlayer.stop();
      await _audioPlayer.seek(Duration.zero);
    }

    _currentMessageId = messageId;
    _logger.i(
      '[AUDIO_CONTROLLER] setAudioSourceFromFile - Setting file for $messageId: $filePath',
    );

    try {
      await _audioPlayer.setFilePath(filePath);
      _logger.i(
        '[AUDIO_CONTROLLER] setAudioSourceFromFile - Success, got duration: ${_audioPlayer.duration}',
      );
    } catch (e) {
      _logger.e(
        '[AUDIO_CONTROLLER] setAudioSourceFromFile - Error: $e',
        error: e,
      );
      rethrow;
    }
  }

  bool isAudioAtEnd(int durationMilliseconds) {
    final totalDuration = Duration(milliseconds: durationMilliseconds);
    final currentPos = _audioPlayer.position;
    final atEnd = (totalDuration - currentPos).inMilliseconds.abs() <= 100;
    _logger.i(
      '[AUDIO_CONTROLLER] isAudioAtEnd - duration: ${durationMilliseconds}ms, currentPos: ${currentPos.inMilliseconds}ms, diff: ${(totalDuration - currentPos).inMilliseconds}ms, atEnd: $atEnd',
    );
    return atEnd;
  }

  Future<void> play() async {
    try {
      _logger.i(
        '[AUDIO_CONTROLLER] play - Starting playback, currentPos: ${_audioPlayer.position.inMilliseconds}ms',
      );
      await _audioPlayer.play();
    } catch (e) {
      _logger.e('[AUDIO_CONTROLLER] play - Error: $e', error: e);
      rethrow;
    }
  }

  Future<void> pause() async {
    try {
      _logger.i(
        '[AUDIO_CONTROLLER] pause - Pausing at ${_audioPlayer.position.inMilliseconds}ms',
      );
      await _audioPlayer.pause();
    } catch (e) {
      _logger.e('[AUDIO_CONTROLLER] pause - Error: $e', error: e);
      rethrow;
    }
  }

  Future<void> seek(Duration position) async {
    try {
      _logger.i(
        '[AUDIO_CONTROLLER] seek - Seeking to ${position.inMilliseconds}ms',
      );
      await _audioPlayer.seek(position);
      _logger.i(
        '[AUDIO_CONTROLLER] seek - Now at ${_audioPlayer.position.inMilliseconds}ms',
      );
    } catch (e) {
      _logger.e('[AUDIO_CONTROLLER] seek - Error: $e', error: e);
      rethrow;
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}
