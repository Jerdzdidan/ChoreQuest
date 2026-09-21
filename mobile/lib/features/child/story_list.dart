import 'package:flutter/material.dart';

import '../../core/models/child_progress.dart';
import '../../shared/story_chapters.dart';

/// The hero's story so far: open chapters in full, and the ones still to
/// come with what opens them.
class StoryList extends StatelessWidget {
  const StoryList({super.key, required this.progress});

  final ChildProgress progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final chapter in storyChapters)
          _ChapterRow(chapter: chapter, open: chapter.unlockedBy(progress)),
      ],
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.open});

  final StoryChapter chapter;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ink = open ? chapter.ink : scheme.onSurfaceVariant;

    return MergeSemantics(
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        color: open ? chapter.background : scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: open ? Colors.white : scheme.surfaceContainerHighest,
                ),
                child: open
                    ? ExcludeSemantics(
                        child: Text(chapter.emoji, style: const TextStyle(fontSize: 26)),
                      )
                    : Icon(Icons.lock_rounded, color: scheme.outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chapter ${chapter.number}',
                      style: text.labelLarge?.copyWith(color: ink),
                    ),
                    Text(
                      chapter.title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: open ? chapter.ink : null,
                      ),
                    ),
                    Text(
                      open ? chapter.blurb : chapter.milestone.describe,
                      style: text.bodyMedium?.copyWith(color: ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
