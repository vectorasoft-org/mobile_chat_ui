import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/chat_logger.dart';

enum RecordingState {
  notRecording, // Idle, not recording
  tapMode, // Recording in tap mode (< 500ms or pointer released before timer)
  holdMode, // Recording in hold mode (>= 500ms, pointer still down)
}

class RecordingController extends ChangeNotifier {
  final ChatLogger logger;
  RecordingState _state = RecordingState.notRecording;
  Timer? _holdDurationTimer;
  Timer? _recordingDurationTimer;
  int _recordingDurationMs = 0;
  String? _currentRecordingPath;
  bool _pointerReleased =
      false; // Flag to track if user released pointer before 500ms
  bool _sendRequested = false; // Flag to indicate send button was pressed

  // Amplitude/volume stream
  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  RecordingController({required this.logger});

  RecordingState get state => _state;
  int get recordingDurationMs => _recordingDurationMs;
  String? get recordingPath => _currentRecordingPath;
  bool get sendRequested => _sendRequested;
  bool get isNotRecording => _state == RecordingState.notRecording;
  bool get isTapMode => _state == RecordingState.tapMode;
  bool get isHoldMode => _state == RecordingState.holdMode;
  bool get isRecording =>
      _state == RecordingState.tapMode || _state == RecordingState.holdMode;

  /// Update amplitude value (called by RecordButton from AudioRecorder callback)
  void updateAmplitude(double amplitude) {
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(amplitude);
    }
  }

  /// Called when user presses down on the record button
  void onPointerDown() {
    if (_state == RecordingState.notRecording) {
      // Transition to tap mode and start recording
      _state = RecordingState.tapMode;
      _recordingDurationMs = 0;
      _pointerReleased = false; // Reset flag
      notifyListeners();

      // Start 500ms timer to check if we should transition to hold mode
      _holdDurationTimer = Timer(const Duration(milliseconds: 500), () {
        // Check if pointer was released before timer expired
        if (!_pointerReleased && _state == RecordingState.tapMode) {
          // User still holding after 500ms, transition to hold mode
          _state = RecordingState.holdMode;
          notifyListeners();
        }
        // If _pointerReleased is true, stay in tap mode
      });

      _startRecordingTimer();
    } else if (_state == RecordingState.tapMode) {
      // Tap again while in tap mode = cancel and discard
      cancel();
    }
  }

  /// Called when user releases the pointer
  void onPointerUp({required bool nearButton}) {
    logger.d(
      'onPointerUp: state=$_state, nearButton=$nearButton',
    );
    if (_state == RecordingState.tapMode) {
      // Just set the flag, don't stop recording
      // Let timer expire or user press send button
      _pointerReleased = true;
      _holdDurationTimer?.cancel();
      _holdDurationTimer = null;
      logger.d(
        'Released in TAP MODE - setting pointerReleased flag',
      );
      notifyListeners();
    } else if (_state == RecordingState.holdMode) {
      // In hold mode, release determines send or cancel
      if (nearButton) {
        // Release near button = send immediately
        logger.d(
          'Released NEAR BUTTON in HOLD MODE - SENDING MESSAGE',
        );
        _sendRequested = true;
        notifyListeners();
      } else {
        // Release far from button = discard
        logger.d(
          'Released FAR from button in HOLD MODE - CANCELING',
        );
        cancel();
        return;
      }
    }
  }

  /// Called when send button is pressed (only valid in tap mode)
  void onSendButtonPressed() {
    logger.d('onSendButtonPressed: state=$_state');
    if (_state == RecordingState.tapMode) {
      // Set flag to indicate send was requested
      logger.d(
        'SEND BUTTON pressed in TAP MODE - setting sendRequested flag',
      );
      _sendRequested = true;
      notifyListeners();
      // State will transition to notRecording after recording is actually stopped
    }
  }

  /// Start the recording duration timer
  void _startRecordingTimer() {
    _recordingDurationTimer?.cancel();
    _recordingDurationTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_state != RecordingState.notRecording) {
          _recordingDurationMs += 100;
          notifyListeners();
        }
      },
    );
  }

  void setRecordingPath(String path) {
    _currentRecordingPath = path;
  }

  /// Complete recording (called after successfully sending)
  void completeRecording() {
    logger.d('completeRecording called, resetting state');
    _cleanupTimers();
    _resetState();
    notifyListeners();
  }

  /// Cancel the recording (from any state)
  void cancel() {
    logger.d('cancel called, resetting state');
    _cleanupTimers();
    _resetState();
    notifyListeners();
  }

  void _cleanupTimers() {
    _holdDurationTimer?.cancel();
    _holdDurationTimer = null;
    _recordingDurationTimer?.cancel();
    _recordingDurationTimer = null;
  }

  void _resetState() {
    _state = RecordingState.notRecording;
    _recordingDurationMs = 0;
    _currentRecordingPath = null;
    _pointerReleased = false;
    _sendRequested = false;
  }

  @override
  void dispose() {
    _cleanupTimers();
    super.dispose();
  }
}
