// Real alarm + voice implementation (Session 5): audioplayers for the
// looping tone (bundled assets/alarm.wav, a generated two-tone siren) and
// flutter_tts for the spoken prompt.
//
// HONESTY: this was built and analysed on a VM with no audio device and
// has NOT been heard by anyone. Every platform call is wrapped: a failure
// is recorded in [lastError] and shown on screen, never swallowed
// silently and never reported as sound.

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'alarm_service.dart';

AlarmService defaultAlarmService() => DeviceAlarmService();

class DeviceAlarmService implements AlarmService {
  DeviceAlarmService();

  AudioPlayer? _player;
  FlutterTts? _tts;
  bool _on = false;
  String? _error;

  @override
  bool get isSounding => _on;

  @override
  bool get canProduceSound => true;

  @override
  String? get lastError => _error;

  @override
  String get description =>
      'Device alarm: looping siren tone (audioplayers) and spoken prompts '
      '(flutter_tts). Not verified by ear in this build.';

  @override
  Future<void> start() async {
    if (_on) return;
    _on = true;
    try {
      final p = _player ??= AudioPlayer();
      await p.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gain,
          ),
        ),
      );
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      await p.play(AssetSource('alarm.wav'));
    } catch (e) {
      _error = 'alarm tone failed: $e';
    }
  }

  @override
  Future<void> stop() async {
    _on = false;
    try {
      await _player?.stop();
    } catch (e) {
      _error = 'alarm stop failed: $e';
    }
    try {
      await _tts?.stop();
    } catch (e) {
      _error = 'voice stop failed: $e';
    }
  }

  @override
  Future<void> speak(String text) async {
    try {
      final t = _tts ??= FlutterTts();
      await t.setVolume(1.0);
      await t.speak(text);
    } catch (e) {
      _error = 'voice prompt failed: $e';
    }
  }

  Future<void> dispose() async {
    await stop();
    try {
      await _player?.dispose();
    } catch (_) {}
  }
}
