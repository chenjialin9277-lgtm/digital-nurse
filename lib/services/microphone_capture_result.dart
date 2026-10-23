import 'dart:typed_data';

class MicrophoneCaptureResult {
  const MicrophoneCaptureResult({
    required this.pcmByteCount,
    required this.encodedFrameCount,
    required this.voicedFrameCount,
    required this.peakAmplitude,
    required this.streamFailed,
  });

  static const int minimumEncodedFrames = 5;
  static const int minimumVoicedFrames = 2;
  static const int voicedPeakThreshold = 256;

  final int pcmByteCount;
  final int encodedFrameCount;
  final int voicedFrameCount;
  final int peakAmplitude;
  final bool streamFailed;

  bool get hasValidSpeech =>
      !streamFailed &&
      encodedFrameCount >= minimumEncodedFrames &&
      voicedFrameCount >= minimumVoicedFrames;
}

class MicrophoneCaptureTracker {
  int _pcmByteCount = 0;
  int _encodedFrameCount = 0;
  int _voicedFrameCount = 0;
  int _peakAmplitude = 0;
  bool _streamFailed = false;

  void addPcmFrame(Uint8List frame) {
    _pcmByteCount += frame.length;
    final samples = ByteData.sublistView(frame);
    var framePeak = 0;
    for (var offset = 0; offset + 1 < frame.length; offset += 2) {
      final sample = samples.getInt16(offset, Endian.little).abs();
      if (sample > framePeak) framePeak = sample;
    }
    if (framePeak > _peakAmplitude) _peakAmplitude = framePeak;
    if (framePeak >= MicrophoneCaptureResult.voicedPeakThreshold) {
      _voicedFrameCount++;
    }
  }

  void markEncodedFrame() => _encodedFrameCount++;

  void markStreamError(Object error) => _streamFailed = true;

  MicrophoneCaptureResult finish() => MicrophoneCaptureResult(
    pcmByteCount: _pcmByteCount,
    encodedFrameCount: _encodedFrameCount,
    voicedFrameCount: _voicedFrameCount,
    peakAmplitude: _peakAmplitude,
    streamFailed: _streamFailed,
  );
}
