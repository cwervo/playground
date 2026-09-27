import 'package:flutter/material.dart';

import 'click_log.dart';

/// Shows the "Pop!" modal for [click]. Resolves to true if the user chose
/// to open the link.
Future<bool> showPopDialog(BuildContext context, LinkClick click, int count) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (context, _, __) => _PopDialog(click: click, count: count),
    // Springy scale so the modal itself "pops" in.
    transitionBuilder: (context, animation, _, child) => ScaleTransition(
      scale: CurvedAnimation(
        parent: animation,
        curve: Curves.elasticOut,
        reverseCurve: Curves.easeIn,
      ),
      child: FadeTransition(opacity: animation, child: child),
    ),
  ).then((open) => open ?? false);
}

class _PopDialog extends StatelessWidget {
  const _PopDialog({required this.click, required this.count});

  final LinkClick click;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = TimeOfDay.fromDateTime(click.at).format(context);
    return AlertDialog(
      icon: const Text('💥', style: TextStyle(fontSize: 48)),
      title: const Text('Pop!'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(click.label, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(click.url,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary)),
          const SizedBox(height: 16),
          Text(
            'Saved at $time — '
            '${count == 1 ? 'first pop' : 'pop #$count'} for this link.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open link'),
        ),
      ],
    );
  }
}
