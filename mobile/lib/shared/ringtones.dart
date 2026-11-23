/// One alarm sound: what a parent sees, and the file that rings.
///
/// The parent's preview plays the same asset the child's alarm rings, so what
/// was heard when choosing is what rings.
class Ringtone {
  const Ringtone({required this.title, required this.asset});

  final String title;

  /// An OGG file under assets/ringtones/.
  final String asset;
}

/// Alarm sounds a quest can ring with, keyed as the server stores them
/// (assignments.ringtone_key), in the shape of the cosmetics registries.
///
/// All six are from Kenney's "85 Short music jingles" (CC0), named by the
/// instrument that plays them. Each is one to two seconds long and loops
/// while the alarm rings. A new sound is a new file and a new entry; nothing
/// on the server changes.
const ringtones = <String, Ringtone>{
  'classic': Ringtone(title: 'Game tune', asset: 'assets/ringtones/classic.ogg'),
  'game_tune': Ringtone(title: 'Game tune 2', asset: 'assets/ringtones/game_tune.ogg'),
  'steel_drums': Ringtone(title: 'Steel drums', asset: 'assets/ringtones/steel_drums.ogg'),
  'steel_drums_2': Ringtone(title: 'Steel drums 2', asset: 'assets/ringtones/steel_drums_2.ogg'),
  'plucked_strings': Ringtone(title: 'Plucked strings', asset: 'assets/ringtones/plucked_strings.ogg'),
  'saxophone': Ringtone(title: 'Saxophone', asset: 'assets/ringtones/saxophone.ogg'),
};

/// What a quest rings with unless the parent chooses another. The server's
/// default (Assignment::DEFAULT_RINGTONE) is the same key.
const defaultRingtone = 'classic';

/// The ringtone for [key], or the default for a key this version does not
/// know, so an alarm always has a sound.
Ringtone ringtoneFor(String key) => ringtones[key] ?? ringtones[defaultRingtone]!;

/// How a ringing sound gets louder: from [startVolume] up to full over
/// [rampUp], rather than starting at full. The users are four to ten.
const rampUp = Duration(seconds: 10);
const startVolume = 0.15;

/// The volume [elapsed] into a ramp: [startVolume] at the start, rising in a
/// straight line to 1 at [rampUp], and 1 from then on.
double rampedVolume(Duration elapsed, {Duration over = rampUp}) {
  if (elapsed <= Duration.zero) return startVolume;
  if (elapsed >= over) return 1;
  return startVolume + (1 - startVolume) * elapsed.inMilliseconds / over.inMilliseconds;
}
