import '../../core/models/cosmetics.dart';
import '../../shared/cosmetics.dart';
import 'child_api.dart';

/// Keeps the server's record of a child's unlocked cosmetics in step with
/// their level.
///
/// Unlock levels live in the app's registries, so when a refresh brings new
/// XP the app works out what the child's level unlocks and reports whatever
/// the server does not hold yet. The server records each item once.
class CosmeticUnlocks {
  CosmeticUnlocks(this.api);

  final ChildApi api;

  /// The highest level fully recorded since this screen opened.
  int? _recordedUpTo;
  Future<List<(CosmeticCategory, String)>>? _running;

  /// Records what [level] unlocks, returning the items this call added. A
  /// level already recorded costs nothing, and a call while one is running
  /// joins it instead of reporting the same items twice.
  Future<List<(CosmeticCategory, String)>> sync(int level) {
    final done = _recordedUpTo;
    if (done != null && level <= done) return Future.value(const []);

    final running = _running;
    if (running != null) return running;

    // A block, not an arrow: an arrow would hand whenComplete this very
    // future to wait on, and it would never finish.
    final started = _sync(level).whenComplete(() {
      _running = null;
    });
    _running = started;
    return started;
  }

  Future<List<(CosmeticCategory, String)>> _sync(int level) async {
    final wardrobe = await api.cosmetics();
    final missing = unlocksToRecord(level, wardrobe);
    if (missing.isNotEmpty) await api.recordUnlocked(missing);
    _recordedUpTo = level;
    return missing;
  }
}
