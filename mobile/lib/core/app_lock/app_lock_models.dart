/// App Lock's settings, permissions and requests (AL-3 to AL-6). Free of
/// Flutter, so the parent's notification model can use the permission names.
library;

/// An app's setting under App Lock (AL-5). What the server and the watcher
/// store is [key]; what the parent reads is [label].
enum AppSetting {
  open('open', 'Open', 'Anyone can open it.'),
  earnedTime('earned_time', 'Earned time', 'A child spends earned minutes, or a grown-up uses their PIN.'),
  grownUpsOnly('grown_ups_only', 'Grown-ups only', 'Only a grown-up, with their PIN.');

  const AppSetting(this.key, this.label, this.meaning);

  final String key;
  final String label;
  final String meaning;

  static AppSetting parse(String? raw) {
    for (final setting in values) {
      if (setting.key == raw) return setting;
    }
    return open;
  }
}

/// What App Lock needs on this phone (AL-4), in plain words. The keys are
/// what the watcher reports to the server.
enum AppLockCheck {
  usageAccess(
    'usage_access',
    'Usage access',
    'Lets ChoreQuest see which app is open, so it knows when a locked app starts.',
    'Turn on usage access',
  ),
  overlay(
    'overlay',
    'Display over other apps',
    'Lets the "Who\'s using this?" screen open on top of a locked app.',
    'Allow display over other apps',
  ),
  notifications(
    'notifications',
    'Notifications',
    'Shows the minutes left, warns a minute before time is up, and says if App Lock stops.',
    'Turn on notifications',
  ),
  battery(
    'battery',
    'Not put to sleep by battery saving',
    'Keeps App Lock watching while the phone sleeps. Without it, the phone may stop App Lock.',
    'Turn off battery saving for ChoreQuest',
  );

  const AppLockCheck(this.key, this.title, this.why, this.fixLabel);

  final String key;
  final String title;

  /// What it is for, said to the grown-up turning App Lock on.
  final String why;

  final String fixLabel;
}

/// App Lock on this phone, as Android reports it.
class AppLockStatus {
  const AppLockStatus({
    required this.enabled,
    required this.running,
    required this.checks,
    required this.phoneName,
  });

  /// A grown-up turned App Lock on here.
  final bool enabled;

  /// The watcher is running now.
  final bool running;

  final Map<AppLockCheck, bool> checks;

  /// The maker and model, which the parent sees.
  final String phoneName;

  bool isOn(AppLockCheck check) => checks[check] ?? false;

  List<AppLockCheck> get missing => [for (final check in AppLockCheck.values) if (!isOn(check)) check];

  bool get ready => missing.isEmpty;
}

/// An app on this phone, read here and never sent.
class InstalledApp {
  const InstalledApp({required this.package, required this.label});

  final String package;
  final String label;
}

/// Why the lock screen came up.
enum LockReason {
  /// A locked app was opened.
  locked,

  /// A child's earned minutes ran out while it was open.
  timeUp,

  /// The next minute could not be bought: the server could not be reached.
  offline;

  static LockReason parse(String? raw) => switch (raw) {
        'time_up' => timeUp,
        'offline' => offline,
        _ => locked,
      };
}

/// The watcher brought the lock screen up over [package].
class LockRequest {
  const LockRequest({
    required this.package,
    required this.label,
    required this.reason,
    this.setting = AppSetting.earnedTime,
  });

  final String package;
  final String label;
  final LockReason reason;

  /// Earned time or Grown-ups only: whether a child may open it at all.
  final AppSetting setting;
}
