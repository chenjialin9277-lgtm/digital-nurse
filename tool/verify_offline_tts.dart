import 'dart:io';
import 'dart:math' as math;

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

void main(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/verify_offline_tts.dart '
      '<native-lib-dir> <model-dir> <output.wav>',
    );
    exitCode = 64;
    return;
  }

  final nativeDirectory = arguments[0];
  final modelDirectory = arguments[1];
  final output = arguments[2];
  sherpa_onnx.initBindings(nativeDirectory);

  final separator = Platform.pathSeparator;
  final tts = sherpa_onnx.OfflineTts(
    sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: '$modelDirectory${separator}zh_CN-xiao_ya-medium.onnx',
          lexicon: '$modelDirectory${separator}lexicon.txt',
          tokens: '$modelDirectory${separator}tokens.txt',
        ),
        numThreads: 4,
        debug: false,
      ),
      ruleFsts: <String>[
        '$modelDirectory${separator}phone.fst',
        '$modelDirectory${separator}date.fst',
        '$modelDirectory${separator}number.fst',
      ].join(','),
    ),
  );

  final watch = Stopwatch()..start();
  final audio = tts.generate(text: '您好，我是急诊病房数字护士。这是固定宣教离线语音测试。');
  watch.stop();
  tts.free();

  var peak = 0.0;
  var energy = 0.0;
  for (final sample in audio.samples) {
    peak = math.max(peak, sample.abs());
    energy += sample * sample;
  }
  final rms = math.sqrt(energy / math.max(1, audio.samples.length));
  final wrote = sherpa_onnx.writeWave(
    filename: output,
    samples: audio.samples,
    sampleRate: audio.sampleRate,
  );
  stdout.writeln(
    'sampleRate=${audio.sampleRate} samples=${audio.samples.length} '
    'duration=${(audio.samples.length / audio.sampleRate).toStringAsFixed(2)}s '
    'peak=${peak.toStringAsFixed(4)} rms=${rms.toStringAsFixed(4)} '
    'generationMs=${watch.elapsedMilliseconds} wrote=$wrote',
  );
  if (!wrote || audio.samples.isEmpty || peak < 0.01 || rms < 0.001) {
    exitCode = 1;
  }
}
