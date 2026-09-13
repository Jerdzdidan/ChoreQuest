import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/allocation_rule.dart';
import '../../core/models/child_profile.dart';
import '../../core/models/chore.dart';
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

final catalogueProvider =
    FutureProvider.autoDispose.family<List<ChoreTemplate>, int>(
  (ref, childId) => ref.watch(parentApiProvider).catalogueFor(childId),
);

final ruleProvider = FutureProvider.autoDispose.family<AllocationRule, int>(
  (ref, childId) => ref.watch(parentApiProvider).rule(childId),
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
