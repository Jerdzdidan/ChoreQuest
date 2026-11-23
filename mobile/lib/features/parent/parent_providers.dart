import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/allocation_rule.dart';
import '../../core/models/camera.dart';
import '../../core/models/child_activity.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/parent_notification.dart';
import '../../core/models/chore.dart';
import '../../core/models/family_quest.dart';
import '../../core/models/screen_time_report.dart';
import '../../core/notifications/local_notifier.dart';
import '../../core/session/session_controller.dart';
import 'parent_api.dart';
import 'review_watcher.dart';

final parentApiProvider = Provider<ParentApi>(
  (ref) => ParentApi(ref.watch(apiClientProvider)),
);

// Every data provider below is autoDispose. The ProviderScope outlives a
// sign-out, so a list kept alive after its screens close would show one
// parent's children to the next person who signs in on the same phone.

final childrenProvider = FutureProvider.autoDispose<List<ChildProfile>>(
  (ref) => ref.watch(parentApiProvider).children(),
);

final assignmentsProvider =
    FutureProvider.autoDispose.family<List<Assignment>, int>(
  (ref, childId) => ref.watch(parentApiProvider).assignments(childId),
);

/// Every chore in the catalogue, whatever the age: the Quests tab (PQ1).
final fullCatalogueProvider = FutureProvider.autoDispose<ChoreCatalogue>(
  (ref) => ref.watch(parentApiProvider).catalogue(),
);

final catalogueProvider =
    FutureProvider.autoDispose.family<ChoreCatalogue, int>(
  (ref, childId) => ref.watch(parentApiProvider).catalogueFor(childId),
);

/// The third-party cameras connected to a child's phone (PS-6, BE-8).
final childCamerasProvider = FutureProvider.autoDispose.family<List<ReportedCamera>, int>(
  (ref, childId) => ref.watch(parentApiProvider).childCameras(childId),
);

final ruleProvider = FutureProvider.autoDispose.family<AllocationRule, int>(
  (ref, childId) => ref.watch(parentApiProvider).rule(childId),
);

/// The household's shared quests (F2), for the Board and the form.
final familyQuestsProvider = FutureProvider.autoDispose<List<FamilyQuest>>(
  (ref) => ref.watch(parentApiProvider).familyQuests(),
);

/// One child's Activity tab figures (ACT1).
final activityProvider = FutureProvider.autoDispose.family<ChildActivity, int>(
  (ref, childId) => ref.watch(parentApiProvider).activity(childId),
);

final reportProvider =
    FutureProvider.autoDispose.family<ScreenTimeReport, int>(
  (ref, childId) => ref.watch(parentApiProvider).report(childId),
);

/// The Review tab's lists. The parent's shell watches it for as long as a
/// parent is signed in, and calls [ReviewFeedController.refresh] on a timer.
final reviewFeedProvider =
    AsyncNotifierProvider.autoDispose<ReviewFeedController, ReviewFeed>(
  ReviewFeedController.new,
);

class ReviewFeedController extends AsyncNotifier<ReviewFeed> {
  ReviewWatcher? _watcher;

  ReviewWatcher get _look => _watcher ??= ReviewWatcher(
        api: ref.read(parentApiProvider),
        notifier: ref.read(appNotifierProvider),
      );

  @override
  Future<ReviewFeed> build() => _look.look();

  /// Looks again; the watcher announces anything new. A failed look keeps the
  /// last lists on screen rather than blanking them over a dropped connection.
  Future<void> refresh() async {
    try {
      final feed = await _look.look();
      if (ref.mounted) state = AsyncData(feed);
    } on ApiException catch (error, stackTrace) {
      if (ref.mounted && !state.hasValue) state = AsyncError(error, stackTrace);
    }
  }
}

/// The parent's notifications (NT1): every photo sent, newest first, and how
/// many arrived since the list was last opened. The bell shows that count
/// (PN2); the shell looks again on the same beat as the review lists.
final notificationsProvider =
    AsyncNotifierProvider.autoDispose<NotificationsController, NotificationFeed>(
  NotificationsController.new,
);

class NotificationsController extends AsyncNotifier<NotificationFeed> {
  @override
  Future<NotificationFeed> build() => ref.watch(parentApiProvider).notifications();

  /// Looks again. A failed look keeps the last feed on screen.
  Future<void> refresh() async {
    try {
      final feed = await ref.read(parentApiProvider).notifications();
      if (ref.mounted) state = AsyncData(feed);
    } on ApiException catch (error, stackTrace) {
      if (ref.mounted && !state.hasValue) state = AsyncError(error, stackTrace);
    }
  }

  /// Marks everything seen. The bell drops to zero at once; the list keeps
  /// showing which photos were new until it is next loaded.
  Future<void> markSeen() async {
    await ref.read(parentApiProvider).markNotificationsSeen();
    final feed = state.value;
    if (ref.mounted && feed != null) {
      // Everything carried over but the count: the alarm events too.
      state = AsyncData(NotificationFeed(items: feed.items, alarms: feed.alarms, unreadCount: 0));
    }
  }
}
