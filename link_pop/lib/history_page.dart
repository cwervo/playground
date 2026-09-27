import 'package:flutter/material.dart';

import 'click_log.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.log});

  final ClickLog log;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text('Saved pops (${log.total})'),
          actions: [
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_sweep),
              onPressed: log.total == 0 ? null : () => _confirmClear(context),
            ),
          ],
        ),
        body: log.total == 0
            ? const Center(child: Text('No pops yet. Go click a link!'))
            : ListView.separated(
                itemCount: log.total,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final c = log.clicks[i];
                  return ListTile(
                    leading: const Text('💥', style: TextStyle(fontSize: 24)),
                    title: Text(c.label),
                    subtitle: Text(c.url),
                    trailing: Text(_stamp(c.at)),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all saved pops?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok ?? false) await log.clear();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
