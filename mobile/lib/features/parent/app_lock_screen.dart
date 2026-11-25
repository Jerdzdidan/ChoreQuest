import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/app_lock/app_lock_platform.dart';
import '../../core/config.dart';
import '../../core/device/phone_readiness.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../shared/inline_error.dart';
import '../app_lock/app_lock_api.dart';

/// Shown on the Lock apps screen and when App Lock is turned on (decision 4).
const appLockThisPhoneOnly =
    'App Lock works on this phone only. To lock apps on another phone or tablet, sign in there and set it up again.';

/// The suggested default (AL-5): a child cannot turn App Lock off, or
/// uninstall ChoreQuest, from Settings or the Play Store.
const suggestedGrownUpsOnly = {'com.android.settings', 'com.android.vending'};

/// App Lock (AL-4, AL-5), from Lock apps on the parent's Profile.
///
/// Turned off: "Turn on App Lock", each permission it needs in plain words
/// with a button to its screen in the phone's settings, then the button
/// that turns it on. Settings and the Play Store start as Grown-ups only.
///
/// Turned on: this phone's apps, read here and never sent, with search, each
/// Open, Earned time or Grown-ups only; what is missing, if anything; and
/// turning it off.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> with WidgetsBindingObserver {
  bool _loading = true;
  AppLockStatus? _status;
  String? _deviceKey;
  List<InstalledApp> _apps = const [];
  Map<String, AppSetting> _rules = const {};
  String? _error;
  bool _busy = false;
  final _saving = <String>{};
  final _search = TextEditingController();
  final _icons = <String, Future<Uint8List?>>{};

  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);
  AppLockApi get _api => ref.read(appLockApiProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// Back from the phone's settings: look at the permissions again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final status = await _platform.status();
    if (mounted && status != null) setState(() => _status = status);
  }

  Future<void> _load() async {
    final status = await _platform.status();
    final key = await _platform.deviceKey();
    var apps = const <InstalledApp>[];
    var rules = const <String, AppSetting>{};
    String? error;
    if (status != null && key != null && status.enabled) {
      apps = await _platform.installedApps();
      try {
        rules = await _api.rules(key);
        await _platform.setRules(rules);
      } on ApiException catch (e) {
        error = e.message;
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = status;
      _deviceKey = key;
      _apps = apps;
      _rules = rules;
      _error = error;
    });
  }

  Future<void> _fix(AppLockCheck check) async {
    final outcome = await _platform.fix(check);
    if (!mounted) return;
    if (outcome == FixOutcome.unavailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("This phone has no screen for ${check.title.toLowerCase()}.")),
      );
    }
    await _refreshStatus();
  }

  Future<void> _turnOn() async {
    final status = _status;
    final key = _deviceKey;
    if (status == null || key == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await ref.read(sessionProvider.future);
      if (session is! ParentSession) return;
      final ticket = await _api.turnOnPhone(deviceKey: key, name: status.phoneName);
      await _platform.turnOn(householdId: session.id, ticket: ticket, baseUrl: AppConfig.apiBaseUrl);
      final apps = await _platform.installedApps();
      var rules = await _api.rules(key);
      final suggested = {
        for (final app in apps)
          if (suggestedGrownUpsOnly.contains(app.package) && !rules.containsKey(app.package))
            app.package: AppSetting.grownUpsOnly,
      };
      if (suggested.isNotEmpty) rules = await _api.setRules(key, suggested);
      await _platform.setRules(rules);
      final now = await _platform.status();
      if (!mounted) return;
      setState(() {
        _status = now ?? status;
        _apps = apps;
        _rules = rules;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final key = _deviceKey;
    if (key == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn off App Lock on this phone?'),
        content: const Text('Locked apps will open for anyone until it is turned on again. Your choices for each app are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it on')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Turn off')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _api.turnOffPhone(key);
      await _platform.turnOff();
      final status = await _platform.status();
      if (mounted) setState(() => _status = status);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(InstalledApp app, AppSetting setting) async {
    final key = _deviceKey;
    final before = _rules;
    if (key == null || (before[app.package] ?? AppSetting.open) == setting) return;
    setState(() {
      _saving.add(app.package);
      _rules = {...before, app.package: setting}..removeWhere((_, s) => s == AppSetting.open);
    });
    try {
      final rules = await _api.setRules(key, {app.package: setting});
      await _platform.setRules(rules);
      if (mounted) setState(() => _rules = rules);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rules = before);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving.remove(app.package));
    }
  }

  Future<Uint8List?> _icon(String package) => _icons.putIfAbsent(package, () => _platform.appIcon(package));

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('App Lock')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : status == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: InlineError('App Lock needs an Android phone, and could not start here.'),
                  )
                : status.enabled
                    ? _appList(status)
                    : _turnOnSteps(status),
      ),
    );
  }

  Widget _turnOnSteps(AppLockStatus status) {
    final text = Theme.of(context).textTheme;
    final error = _error;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const _ThisPhoneOnly(),
        const SizedBox(height: 20),
        Text('Turn on App Lock', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
          'App Lock needs four things from this phone. Each button opens the place in the phone\'s settings to allow it; come back here after.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 12),
        for (final check in AppLockCheck.values)
          _CheckRow(check: check, on: status.isOn(check), onFix: () => _fix(check)),
        const SizedBox(height: 12),
        Text(
          'Settings and the Play Store start as Grown-ups only, so a child cannot turn App Lock off or remove ChoreQuest from there. You can change that afterwards.',
          style: text.bodyMedium,
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          InlineError(error),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: status.ready && !_busy ? _turnOn : null,
          child: _busy
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Turn on App Lock'),
        ),
        if (!status.ready) ...[
          const SizedBox(height: 8),
          Text(
            status.missing.length == 1 ? 'Allow the one above first.' : 'Allow the ${status.missing.length} above first.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
        ],
      ],
    );
  }

  Widget _appList(AppLockStatus status) {
    final text = Theme.of(context).textTheme;
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final app in _apps)
        if (query.isEmpty || app.label.toLowerCase().contains(query)) app,
    ];
    final error = _error;
    final header = <Widget>[
      const _ThisPhoneOnly(),
      const SizedBox(height: 12),
      if (status.ready)
        _Health(
          icon: Icons.verified_user_rounded,
          title: 'App Lock is on',
          line: 'Watching ${status.phoneName}.',
        )
      else ...[
        _Health(
          icon: Icons.warning_amber_rounded,
          title: 'App Lock needs you',
          line: status.isOn(AppLockCheck.usageAccess) && status.isOn(AppLockCheck.overlay)
              ? 'It still locks apps, but allow what is below to keep it reliable.'
              : 'It cannot lock apps until what is below is allowed again.',
          warning: true,
        ),
        for (final check in status.missing) _CheckRow(check: check, on: false, onFix: () => _fix(check)),
      ],
      if (error != null) ...[
        const SizedBox(height: 8),
        InlineError(error),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          labelText: 'Search apps',
        ),
      ),
      const SizedBox(height: 8),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            _apps.isEmpty ? 'No apps found on this phone.' : 'No app is called that.',
            textAlign: TextAlign.center,
            style: text.bodyLarge,
          ),
        ),
    ];
    final footer = <Widget>[
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: _busy ? null : _turnOff,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('Turn off App Lock on this phone'),
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: header.length + shown.length + footer.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final j = i - header.length;
        if (j < shown.length) {
          final app = shown[j];
          return _AppRow(
            app: app,
            icon: _icon(app.package),
            setting: _rules[app.package] ?? AppSetting.open,
            saving: _saving.contains(app.package),
            onChanged: (setting) => _set(app, setting),
          );
        }
        return footer[j - shown.length];
      },
    );
  }
}

class _ThisPhoneOnly extends StatelessWidget {
  const _ThisPhoneOnly();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.smartphone_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                appLockThisPhoneOnly,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Health extends StatelessWidget {
  const _Health({required this.icon, required this.title, required this.line, this.warning = false});

  final IconData icon;
  final String title;
  final String line;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ink = warning ? scheme.onErrorContainer : scheme.onSurface;
    return Card(
      color: warning ? scheme.errorContainer : scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: ink),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleMedium?.copyWith(color: ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line, style: text.bodyMedium?.copyWith(color: ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One permission: what it is for, whether it is allowed, and the button
/// that opens where to allow it.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.check, required this.on, required this.onFix});

  final AppLockCheck check;
  final bool on;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: on ? scheme.primary : scheme.outline,
            semanticLabel: on ? 'Allowed' : 'Not allowed yet',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.title, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(check.why, style: text.bodyMedium),
                if (!on) ...[
                  const SizedBox(height: 6),
                  OutlinedButton(onPressed: onFix, child: Text(check.fixLabel)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One app on this phone and its setting.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.icon,
    required this.setting,
    required this.saving,
    required this.onChanged,
  });

  final InstalledApp app;
  final Future<Uint8List?> icon;
  final AppSetting setting;
  final bool saving;
  final ValueChanged<AppSetting> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 40,
            child: FutureBuilder(
              future: icon,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                return bytes == null
                    ? const Icon(Icons.apps_rounded, size: 32)
                    : Image.memory(bytes, width: 40, height: 40, excludeFromSemantics: true);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(app.label, style: text.titleMedium)),
                    if (saving) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final choice in AppSetting.values)
                      ChoiceChip(
                        label: Text(choice.label),
                        selected: choice == setting,
                        onSelected: saving ? null : (_) => onChanged(choice),
                        tooltip: '${app.label}: ${choice.label}. ${choice.meaning}',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
