import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../config/chat_theme_provider.dart';
import '../controllers/recording_controller.dart';
import '../config/chat_logger.dart';
import '../services/chat_localizations.dart';

typedef RecordingCompleteCallback =
    Future<void> Function(
      String filePath,
      int durationMilliseconds,
    );

class RecordButtonV2 extends StatefulWidget {
  final RecordingController recordingController;
  final RecordingCompleteCallback onRecordingComplete;
  final VoidCallback onRecordingStart;
  final VoidCallback onRecordingCancel;
  final Future<bool> Function() requestPermission;
  final Future<bool> Function() hasPermission;
  final ChatLogger logger;
  final int maxDurationSeconds;
  final double deleteZoneThreshold;

  const RecordButtonV2({
    super.key,
    required this.recordingController,
    required this.onRecordingComplete,
    required this.onRecordingStart,
    required this.onRecordingCancel,
    required this.requestPermission,
    required this.hasPermission,
    required this.logger,
    this.maxDurationSeconds = 180,
    this.deleteZoneThreshold = 32.0,
  });

  @override
  State<RecordButtonV2> createState() => _RecordButtonV2State();
}

class _RecordButtonV2State extends State<RecordButtonV2> {
  late final AudioRecorder _audioRecorder;
  late Offset _buttonCenter;
  bool _inDeleteZone = false;
  bool _isRecording = false;
  bool _isStopping = false; // Flag to prevent multiple stop calls
  bool _isStartingRecording =
      false; // Lock to prevent concurrent start attempts
  DateTime? _recordingStartTime;
  String? _currentFilePath;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateButtonPosition();
    });
    widget.recordingController.addListener(_onControllerStateChanged);
  }

  void _updateButtonPosition() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final topLeft = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      _buttonCenter = topLeft + Offset(size.width / 2, size.height / 2);
    }
  }

  bool _isNearButton(Offset position) {
    final distance = (position - _buttonCenter).distance;
    return distance <= widget.deleteZoneThreshold;
  }

  void _onControllerStateChanged() {
    if (mounted) {
      setState(() {});

      // Check if send was requested in tap mode
      if (widget.recordingController.sendRequested &&
          _isRecording &&
          !_isStopping) {
        // Stop recording and send (set flag to prevent multiple calls)
        _isStopping = true;
        _stopRecording(shouldSend: true);
      }
    }
  }

  Future<void> _startRecording() async {
    // Prevent concurrent recording start attempts (race condition guard)
    if (_isStartingRecording) {
      widget.logger.d(
        '_startRecording: Already starting, ignoring concurrent call',
      );
      return;
    }

    _isStartingRecording = true;

    try {
      // Call onPointerDown() which handles two separate flows:
      //
      // FLOW 1 (Permission Not Granted): Permission-only flow
      //   - Shows permisison dialog
      //   - Blocks until user grants or denies
      //   - NO state transitions, NO timers
      //   - Returns false (permission acquired but recording not started)
      //   - User must tap again to actually record
      //
      // FLOW 2 (Permission Already Granted): Recording flow
      //   - Transitions to tapMode state
      //   - Starts 500ms hold timer + 100ms duration timer
      //   - Returns true (ready to record, proceed with audio setup)
      final permissionGranted = await widget.recordingController.onPointerDown(
        hasPermission: widget.hasPermission,
        requestPermission: widget.requestPermission,
      );

      if (!permissionGranted) {
        // Flow 1: Permission request completed (or denied)
        // Controller is in notRecording state, no timers running
        // User must tap again to start recording after granting permission
        widget.logger.d('Recording not started (permission flow or denied)');
        return;
      }

      // Flow 2: Permission already granted, state transitions completed
      // Now safe to start audio recording
      // Create temp file path
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = (DateTime.now().microsecond % 10000).toString();
      _currentFilePath =
          '${tempDir.path}/voice_recording_${timestamp}_$random.ogg';

      // Store path in controller
      widget.recordingController.setRecordingPath(_currentFilePath!);

      // Start recording with Opus codec (OGG format)
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 128000,
          sampleRate: 48000,
        ),
        path: _currentFilePath!,
      );

      // Listen to amplitude changes and feed to controller
      _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            // Use logarithmic scale for better audio visualization
            // dBFS: -160 (silence) to 0 (max)
            // Map -40 dBFS as reference (typical speaking level)
            final dbfs = amplitude.current;
            final normalized = _normalizeAmplitudeLog(dbfs);
            widget.recordingController.updateAmplitude(normalized);
          });

      _recordingStartTime = DateTime.now();
      _isRecording = true;

      setState(() {});
      widget.onRecordingStart();
    } catch (e) {
      widget.recordingController.cancel();
      widget.logger.e('Error during recording start: $e');
    } finally {
      _isStartingRecording = false;
    }
  }

  /// Normalize dBFS amplitude to 0.0-1.0 using logarithmic scale
  /// for better perceptual representation of audio levels
  double _normalizeAmplitudeLog(double dbfs) {
    // dBFS ranges from -160 (silence) to 0 (max)
    // Use -50 dBFS as noise floor and 0 as ceiling
    const double minDb = -50.0;
    const double maxDb = 0.0;

    // Clamp to range
    final clamped = dbfs.clamp(minDb, maxDb);

    // Convert to 0.0-1.0 range with exponential curve
    // This gives more sensitivity to lower levels
    final linear = (clamped - minDb) / (maxDb - minDb);
    return (linear * linear).clamp(0.0, 1.0); // Square for exponential feel
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    try {
      await _audioRecorder.stop();

      // Delete temp file
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      widget.recordingController.cancel();

      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
          _isStopping = false; // Reset the flag
        });
      }

      widget.onRecordingCancel();
    } catch (e) {
      widget.recordingController.cancel();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
          _isStopping = false; // Reset the flag
        });
      }
    }
  }

  Future<void> _stopRecording({required bool shouldSend}) async {
    if (!_isRecording) return;

    try {
      final recordedPath = await _audioRecorder.stop();

      if (recordedPath != null) {
        _currentFilePath = recordedPath;
      }

      if (!mounted) return;

      // Calculate duration from recording start and stop time
      final recordingDuration = DateTime.now().difference(_recordingStartTime!);
      final durationMilliseconds = recordingDuration.inMilliseconds;

      // Update state to stop recording
      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
          _isStopping = false; // Reset the flag
        });
      }

      if (shouldSend) {
        // Send recording with duration in milliseconds
        await widget.onRecordingComplete(
          _currentFilePath!,
          durationMilliseconds,
        );
        // Complete recording in controller (goes to notRecording state)
        widget.logger.d('Recording completed, resetting controller');
        widget.recordingController.completeRecording();
      } else {
        // Cancel recording - no toast notification
        // Delete temp file
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        widget.recordingController.cancel();
        widget.onRecordingCancel();
      }
    } catch (e) {
      widget.recordingController.cancel();
      // Ensure we stop recording even on error
      if (mounted) {
        setState(() {
          _isRecording = false;
          _inDeleteZone = false;
          _isStopping = false; // Reset the flag
        });
      }
    }
  }

  @override
  void dispose() {
    widget.recordingController.removeListener(_onControllerStateChanged);
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatThemeProvider.of(context);
    return Padding(
      padding: EdgeInsets.all(8.w),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) async {
          _updateButtonPosition();
          if (widget.recordingController.isNotRecording) {
            // Start new recording - _startRecording() awaits permission check
            await _startRecording();
          } else if (widget.recordingController.isTapMode) {
            // Tap again in tap mode = cancel
            await _cancelRecording();
          }
        },
        onTapUp: (details) async {
          // Only process pointer up if recording actually started (permission was granted and state transition happened)
          if (!_isRecording) {
            // Permission was denied or recording never started - nothing to do
            return;
          }

          final nearButton = _isNearButton(details.globalPosition);
          widget.logger.d(
            'onTapUp: nearButton=$nearButton, isHoldMode=${widget.recordingController.isHoldMode}, isRecording=$_isRecording',
          );

          if (!_isStopping) {
            widget.recordingController.onPointerUp(nearButton: nearButton);
          }
          // Note: If in hold mode, controller will set sendRequested flag
          // which will be picked up by _onControllerStateChanged listener
        },
        onVerticalDragStart: (details) async {
          if (!_isRecording) {
            _updateButtonPosition();
            // _startRecording() awaits permission check in onPointerDown().
            // If permission denied, _isRecording stays false, so drag operations below won't run.
            await _startRecording();
          }
        },
        onVerticalDragUpdate: (details) {
          // Safe: only runs if _isRecording=true, which means permission was granted
          if (_isRecording && mounted) {
            final inDeleteZone = !_isNearButton(details.globalPosition);
            if (inDeleteZone != _inDeleteZone) {
              setState(() {
                _inDeleteZone = inDeleteZone;
              });

              if (inDeleteZone) {
                HapticFeedback.mediumImpact();
              }
            }
          }
        },
        onVerticalDragEnd: (details) async {
          widget.logger.d(
            'onVerticalDragEnd: isRecording=$_isRecording, isHoldMode=${widget.recordingController.isHoldMode}, inDeleteZone=$_inDeleteZone',
          );
          // Safe: only runs if _isRecording=true, which means permission was granted in onVerticalDragStart
          if (_isRecording && mounted) {
            if (widget.recordingController.isHoldMode) {
              // In hold mode, directly stop/cancel based on position
              if (_inDeleteZone) {
                // Far from button - cancel
                await _cancelRecording();
              } else {
                // Near button - send
                widget.recordingController.onPointerUp(nearButton: true);
              }
            } else {
              // In tap mode, use standard logic
              await _stopRecording(shouldSend: !_inDeleteZone);
            }
          }
        },
        onVerticalDragCancel: () {
          // Do nothing - onVerticalDragEnd and onTapUp handle all cases
          // This callback fires when the drag gesture is canceled (e.g., when pointer is released)
          // but we don't want to cancel here because onTapUp will handle the release properly
        },
        child: SizedBox(
          width: 50.w,
          height: 50.h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  widget.recordingController.isTapMode
                      ? Icons.delete
                      : Icons.mic,
                  size: 24.sp,
                  color: theme.recordButtonIconColor,
                ),
              ),
              if (widget.recordingController.isHoldMode)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.recordButtonIconColor,
                        width: 2.w,
                      ),
                      borderRadius: BorderRadius.circular(50.r),
                    ),
                  ),
                ),
              // Label: "Slide to cancel" when near button in hold mode
              if (!_inDeleteZone && widget.recordingController.isHoldMode)
                Positioned(
                  top: -30.h,
                  left: -100.w,
                  right: -100.w,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: theme.recordMeterBackground,
                        borderRadius: BorderRadius.circular(3.r),
                      ),
                      child: Text(
                        ChatLocalizations.slideToCancel(context),
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: theme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              // Label: "Release to cancel" when far from button in hold mode
              if (_inDeleteZone && widget.recordingController.isHoldMode)
                Positioned(
                  top: -30.h,
                  left: -100.w,
                  right: -100.w,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: theme.recordDeleteZoneIcon,
                        borderRadius: BorderRadius.circular(3.r),
                      ),
                      child: Text(
                        ChatLocalizations.releaseToCancel(context),
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
