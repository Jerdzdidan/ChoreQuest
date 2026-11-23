import 'package:flutter/material.dart';

/// Who drew the artwork in ChoreQuest (L2).
///
/// Kenney's packs are CC0 and ask for nothing; they are named because it
/// costs nothing to say so. The badge drawings come from game-icons.net under
/// CC BY 3.0, which does require the author's name beside each one, so every
/// badge is listed with the artist who drew it.
class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Artwork and credits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'The pictures in ChoreQuest are free artwork made by other people. '
            'These are their names and licences.',
            style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _Source(
            title: 'Kenney',
            licence: 'CC0 1.0 (public domain)',
            url: 'kenney.nl',
            note: 'The character a child dresses up: its bodies, hair, clothes '
                'and hats. Also the pets, the rugs, wall pictures and plants '
                'in a child’s room, and the pictures on the story chapters.',
            items: const [
              'Roguelike Characters',
              'Roguelike / RPG pack',
              'Roguelike Indoor pack',
              'Animal Pack Redux',
              'Emotes pack',
            ],
          ),
          const SizedBox(height: 20),
          _Source(
            title: 'game-icons.net',
            licence: 'CC BY 3.0 — the artists below must be named',
            url: 'game-icons.net',
            note: 'The badge drawings.',
            items: const [
              'Lorc: Rookie Hero (sprout), Chore Champion (trophy), Study Star '
                  '(open book), Outdoor Explorer (pine tree), Helping Hand (high five)',
              'Delapouite: Kitchen Hero (cooking pot), Bedroom Hero (bunk beds), '
                  'Early Bird (rooster), Weekend Warrior (calendar), Perfect Week '
                  '(checklist), Century Club (star medal), Team Player (team idea)',
              'Carl Olsen: Streak Star (flame)',
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Nothing here was changed except in size and colour, and the pieces '
            'used were cut from the packs above.',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Source extends StatelessWidget {
  const _Source({
    required this.title,
    required this.licence,
    required this.url,
    required this.note,
    required this.items,
  });

  final String title;
  final String licence;
  final String url;
  final String note;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            SelectableText(url, style: text.bodyMedium?.copyWith(color: scheme.primary)),
            const SizedBox(height: 2),
            Text(licence, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text(note, style: text.bodyMedium),
            const SizedBox(height: 10),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: text.bodyMedium),
                    Expanded(child: Text(item, style: text.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
