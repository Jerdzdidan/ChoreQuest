import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/quest_session/model_check.dart';
import '../../core/quest_session/tflite_models.dart';
import 'quest_session_providers.dart';

/// The reference clip ml/08_convert.py --reference installs beside the
/// model, or null when there is none.
final referenceClipProvider = FutureProvider<ReferenceClip?>((ref) async {
  try {
    final json = jsonDecode(await rootBundle.loadString('$modelFolder/reference.json')) as Map<String, dynamic>;
    final frames = await rootBundle.load('$modelFolder/reference_frames.bin');
    return ReferenceClip.fromFiles(frames.buffer.asUint8List(frames.offsetInBytes, frames.lengthInBytes), json);
  } catch (_) {
    return null;
  }
});

/// M11, in test builds only: how long the movement model takes on this
/// phone, per frame for the CNN and per window for the LSTM, so the team can
/// choose 160, 192 or 224 pixels; and, with a reference clip installed
/// (ml/08_convert.py --reference), whether the phone gives the numbers
/// Python did (LS-5).
class ModelBenchmarkScreen extends ConsumerStatefulWidget {
  const ModelBenchmarkScreen({super.key});

  @override
  ConsumerState<ModelBenchmarkScreen> createState() => _ModelBenchmarkScreenState();
}

class _ModelBenchmarkScreenState extends ConsumerState<ModelBenchmarkScreen> {
  BenchmarkResult? _result;
  var _running = false;
  String? _error;

  Future<void> _run(LstmModels models, ReferenceClip? reference) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await runBenchmark(models.card, models.backbone, models.temporal, reference: reference);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final models = ref.watch(lstmModelsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Model benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Test builds only', style: text.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 8),
          switch (models) {
            AsyncData(value: final loaded?) => _loaded(loaded, text),
            AsyncData() || AsyncError() => Text(
                'No movement model in assets/models/. Run ml/08_convert.py --install, then build the app again.',
                style: text.bodyLarge,
              ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ],
      ),
    );
  }

  Widget _loaded(LstmModels models, TextTheme text) {
    final card = models.card;
    final result = _result;
    final looked = ref.watch(referenceClipProvider);
    final reference = looked.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Model ${card.version}', style: text.titleMedium),
        Text('${card.inputSize} x ${card.inputSize} pixels, ${card.classes.length} classes, '
            '${card.window} frames a window at ${card.framesPerSecond} a second'),
        const SizedBox(height: 8),
        Text(looked.isLoading
            ? 'Looking for a reference clip…'
            : reference == null
                ? 'No reference clip installed: timing on random frames only.'
                : 'Reference clip: ${reference.frames.length} frames, ${reference.expected.length} signals from Python.'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _running || looked.isLoading ? null : () => _run(models, reference),
          child: Text(_running ? 'Running…' : 'Run'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
        ],
        if (result != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CNN, per frame: ${BenchmarkResult.mean(result.backboneMs)} ms on average, '
                    '${BenchmarkResult.p90(result.backboneMs)} ms at the 90th percentile '
                    '(${result.backboneMs.length} frames)'),
                const SizedBox(height: 4),
                Text('LSTM, per window: ${BenchmarkResult.mean(result.temporalMs)} ms on average, '
                    '${BenchmarkResult.p90(result.temporalMs)} ms at the 90th percentile '
                    '(${result.temporalMs.length} windows)'),
                if (result.matchesPython != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    result.matchesPython!
                        ? 'Matches Python: the largest difference is ${result.largestDifference!.toStringAsFixed(4)} '
                            '(allowed ${result.tolerance}) over ${result.signals} signals.'
                        : 'Does not match Python: a difference of ${result.largestDifference!.toStringAsFixed(4)}, '
                            'more than the ${result.tolerance} allowed.',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
