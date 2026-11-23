import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/ringtones.dart';

/// Plays a ringtone for the parent to hear before choosing it (PS-8): the
/// same file the child's alarm rings, getting louder as it starts, as the
/// alarm does.
///
/// A preview that cannot play stays silent and changes nothing: the parent
/// can still choose.
class RingtonePreview {
  AudioPlayer? _player;
  Timer? _ramp;

  /// How long a preview takes to reach full volume: shorter than the alarm's
  /// own ramp, since a preview is one play of a sound a second or two long.
  static const ramp = Duration(milliseconds: 1200);

  Future<void> play(String key) async {
    _ramp?.cancel();
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.setVolume(startVolume);
      // AssetSource reads from assets/ by itself.
      await player.play(AssetSource(ringtoneFor(key).asset.replaceFirst('assets/', '')));
      final started = DateTime.now();
      _ramp = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final volume = rampedVolume(DateTime.now().difference(started), over: ramp);
        player.setVolume(volume);
        if (volume >= 1) timer.cancel();
      });
    } catch (_) {
      // No sound is no harm.
    }
  }

  Future<void> stop() async {
    _ramp?.cancel();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  void dispose() {
    _ramp?.cancel();
    _player?.dispose();
  }
}

final ringtonePreviewProvider = Provider.autoDispose<RingtonePreview>((ref) {
  final preview = RingtonePreview();
  ref.onDispose(preview.dispose);
  return preview;
});

/// The ringtone a quest rings with: its name and a play button, and a tap to
/// choose another from the list, where each can be heard first.
class RingtoneField extends ConsumerWidget {
  const RingtoneField({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final preview = ref.read(ringtonePreviewProvider);
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _RingtoneDialog(initial: value, preview: preview),
    );
    await preview.stop();
    if (chosen != null) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ringtoneFor(value).title;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.music_note_rounded),
      title: const Text('Ringtone'),
      subtitle: Text(title),
      trailing: IconButton(
        tooltip: 'Play $title',
        icon: const Icon(Icons.play_circle_outline_rounded),
        onPressed: enabled ? () => ref.read(ringtonePreviewProvider).play(value) : null,
      ),
      onTap: enabled ? () => _choose(context, ref) : null,
    );
  }
}

class _RingtoneDialog extends StatefulWidget {
  const _RingtoneDialog({required this.initial, required this.preview});

  final String initial;
  final RingtonePreview preview;

  @override
  State<_RingtoneDialog> createState() => _RingtoneDialogState();
}

class _RingtoneDialogState extends State<_RingtoneDialog> {
  late String _chosen = ringtones.containsKey(widget.initial) ? widget.initial : defaultRingtone;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ringtone'),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _chosen,
          onChanged: (key) {
            if (key == null) return;
            setState(() => _chosen = key);
            widget.preview.play(key);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final MapEntry(:key, value: ringtone) in ringtones.entries)
                RadioListTile<String>(
                  value: key,
                  title: Text(ringtone.title),
                  secondary: IconButton(
                    tooltip: 'Play ${ringtone.title}',
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    onPressed: () => widget.preview.play(key),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_chosen), child: const Text('Choose')),
      ],
    );
  }
}
