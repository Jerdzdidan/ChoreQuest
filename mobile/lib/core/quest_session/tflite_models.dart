import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'chore_detector.dart';
import 'lstm_detector.dart';

/// Where ml/08_convert.py --install puts the model.
const modelFolder = 'assets/models';

/// One TFLite file, run in its own isolate so the camera preview never
/// stutters. Calls run one after another: the package itself skips a call
/// made while another is running, so this queues them instead.
class TfliteRunner implements ModelRunner {
  TfliteRunner._(this._interpreter, this._isolate, this._outputLength);

  static Future<TfliteRunner> open(Uint8List model, {int threads = 2}) async {
    final interpreter = Interpreter.fromBuffer(model, options: InterpreterOptions()..threads = threads);
    final isolate = await IsolateInterpreter.create(address: interpreter.address);
    final output = interpreter.getOutputTensor(0).shape.fold<int>(1, (a, b) => a * b);
    return TfliteRunner._(interpreter, isolate, output);
  }

  final Interpreter _interpreter;
  final IsolateInterpreter _isolate;
  final int _outputLength;
  Future<void> _turn = Future.value();

  @override
  Future<Float32List> run(Float32List input) {
    final result = _turn.then((_) async {
      final output = Float32List(_outputLength);
      await _isolate.run(input.buffer.asUint8List(input.offsetInBytes, input.lengthInBytes), output.buffer);
      return output;
    });
    _turn = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> close() async {
    await _isolate.close();
    _interpreter.close();
  }
}

/// The movement model as the app ships it: the card and the two files,
/// loaded once. Each quest session gets its own detector over them.
class LstmModels {
  LstmModels(this.card, this.backbone, this.temporal);

  final ModelCard card;
  final ModelRunner backbone;
  final ModelRunner temporal;

  ChoreDetector detector() => LstmDetector(card: card, backbone: backbone, temporal: temporal);

  /// Null when the files are not there or will not load: sessions then run
  /// manual (NoModelDetector) and say so, and no child is left unable to
  /// finish.
  static Future<LstmModels?> load(AssetBundle bundle) async {
    try {
      final card = ModelCard.fromJson(
        jsonDecode(await bundle.loadString('$modelFolder/model_card.json')) as Map<String, dynamic>,
      );
      final backbone = await TfliteRunner.open(_bytes(await bundle.load('$modelFolder/backbone.tflite')));
      final temporal = await TfliteRunner.open(_bytes(await bundle.load('$modelFolder/temporal.tflite')));
      if (backbone._outputLength != card.embedding || temporal._outputLength != card.outputLength) {
        throw const FormatException('the model files do not match model_card.json');
      }
      return LstmModels(card, backbone, temporal);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _bytes(ByteData data) => data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
