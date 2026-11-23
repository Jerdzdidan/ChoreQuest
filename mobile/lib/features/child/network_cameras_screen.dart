import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/camera/network_camera.dart';
import '../../core/uploads/client_token.dart';
import '../../shared/theme.dart';
import 'quest_session_providers.dart';

/// Network cameras on the child's phone (DV-11), for a grown-up: the ones
/// added, each saying whether it answers, and a way to add one by its
/// address. A camera is saved only once it has answered with a picture. Its
/// login stays in this phone's secure storage.
class NetworkCamerasScreen extends ConsumerStatefulWidget {
  const NetworkCamerasScreen({super.key});

  @override
  ConsumerState<NetworkCamerasScreen> createState() => _NetworkCamerasScreenState();
}

class _NetworkCamerasScreenState extends ConsumerState<NetworkCamerasScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  List<NetworkCameraConfig>? _saved;
  Map<String, bool> _answering = const {};
  NetworkProbe? _tried;
  var _trying = false;
  var _saving = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    for (final field in [_name, _address, _username, _password]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _reload() async {
    final source = ref.read(networkCameraSourceProvider);
    final saved = await source.store.load();
    if (mounted) setState(() => _saved = saved);
    final listed = await source.list();
    if (mounted) setState(() => _answering = {for (final camera in listed) camera.key: camera.connected});
  }

  NetworkCameraConfig _fromForm(String id) => NetworkCameraConfig(
        id: id,
        name: _name.text.trim(),
        url: _address.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      );

  /// Anything typed after a try needs another.
  void _edited(String _) {
    if (_tried != null || _formError != null) {
      setState(() {
        _tried = null;
        _formError = null;
      });
    }
  }

  Future<void> _try() async {
    if (_name.text.trim().isEmpty || _address.text.trim().isEmpty) {
      setState(() => _formError = 'Give the camera a name and its address.');
      return;
    }
    setState(() {
      _trying = true;
      _tried = null;
      _formError = null;
    });
    final probe = await ref.read(networkCameraSourceProvider).client.probe(_fromForm('trying'));
    if (!mounted) return;
    setState(() {
      _trying = false;
      _tried = probe;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(networkCameraSourceProvider).put(_fromForm('net-${newClientToken().substring(0, 8)}'));
    for (final field in [_name, _address, _username, _password]) {
      field.clear();
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _tried = null;
    });
    await _reload();
    unawaited(ref.read(cameraReporterProvider).refresh());
  }

  Future<void> _remove(NetworkCameraConfig camera) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${camera.name}?'),
        content: const Text('Quests scheduled with it use the phone camera instead until another is chosen.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (sure != true) return;
    await ref.read(networkCameraSourceProvider).remove(camera.id);
    await _reload();
    unawaited(ref.read(cameraReporterProvider).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = _saved;
    final tried = _tried;

    return Scaffold(
      appBar: AppBar(title: const Text('Network cameras')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('For a grown-up', style: text.labelLarge?.copyWith(color: scheme.primary)),
            const SizedBox(height: 4),
            Text(
              "A CCTV or IP camera on this Wi-Fi can watch quests instead of the phone. ChoreQuest needs the camera's "
              'snapshot (JPEG) or MJPEG address, such as http://192.168.1.20/snapshot.jpg. Its password stays on this phone.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (saved == null)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else
              for (final camera in saved) ...[
                _SavedCamera(camera: camera, answering: _answering[camera.id], onRemove: () => _remove(camera)),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            Text('Add a camera', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              onChanged: _edited,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'Kitchen CCTV'),
            ),
            TextField(
              controller: _address,
              onChanged: _edited,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Address', hintText: 'http://192.168.1.20/snapshot.jpg'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _username,
              onChanged: _edited,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Login name (if any)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _password,
              onChanged: _edited,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (if any)'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _trying || _saving ? null : _try,
              child: _trying
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Try it'),
            ),
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(_formError!, style: text.bodyMedium?.copyWith(color: scheme.error)),
            ],
            if (tried != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: tried.ok
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              tried.picture!,
                              height: 180,
                              fit: BoxFit.contain,
                              semanticLabel: "The camera's picture",
                              errorBuilder: (_, _, _) => const SizedBox(height: 8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tried.feed == NetworkFeed.mjpeg ? 'It answers, with a live stream.' : 'It answers, with a picture.',
                            style: text.bodyLarge?.copyWith(color: QuestColors.of(context).approved.ink),
                          ),
                        ],
                      )
                    : Text(tried.problem!, style: text.bodyLarge?.copyWith(color: scheme.error)),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: tried != null && tried.ok && !_saving ? _save : null,
              child: const Text('Save camera'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SavedCamera extends StatelessWidget {
  const _SavedCamera({required this.camera, required this.answering, required this.onRemove});

  final NetworkCameraConfig camera;

  /// Null while it is being tried.
  final bool? answering;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = QuestColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (String status, Color ink) = switch (answering) {
      true => ('Answering', colors.approved.ink),
      false => ('Not answering', scheme.error),
      null => ('Trying…', scheme.onSurfaceVariant),
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: [
            const Icon(Icons.videocam_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                container: true,
                label: '${camera.name}: $status',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(camera.name, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(camera.url, style: text.bodySmall, overflow: TextOverflow.ellipsis),
                    Text(status, style: text.bodyMedium?.copyWith(color: ink, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            IconButton(tooltip: 'Remove ${camera.name}', onPressed: onRemove, icon: const Icon(Icons.delete_outline_rounded)),
          ],
        ),
      ),
    );
  }
}

