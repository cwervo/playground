import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';

/// Instruction-set reference pulled live from the runtime.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  late Future<List<InstructionDoc>> _future = widget.api.reference();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<InstructionDoc>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Could not load the reference: ${snap.error}'),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () => setState(() => _future = widget.api.reference()),
                  child: const Text('Retry')),
            ]),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final docs = all
            .where((d) =>
                _filter.isEmpty ||
                d.name.contains(_filter) ||
                d.desc.toLowerCase().contains(_filter))
            .toList();
        final core = docs.where((d) => !d.isHostCall).toList();
        final host = docs.where((d) => d.isHostCall).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Instruction set', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'Workers are stack machines. One instruction per line, labels end with ":", '
              'comments start with ";" or "#". Every request starts at the top with an '
              'empty stack and runs until halt.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Filter instructions',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 20),
            _Section(title: 'Core (${core.length})', docs: core),
            const SizedBox(height: 20),
            _Section(title: 'Host calls (${host.length})', docs: host),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Resource model', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      '• Each request runs on its own fiber with a private machine stack '
                      'switched by hand-written assembly (iso_ctx_switch).\n'
                      '• Strings live in a per-request arena; exhausting it fails the '
                      'request with error 1102.\n'
                      '• Every instruction costs one unit of the CPU budget; running out '
                      'also yields error 1102.\n'
                      '• Runtime faults (bad types, stack underflow, division by zero) '
                      'are error 1101.\n'
                      '• The scheduler preempts a fiber every 2,000 instructions, so slow '
                      'workers cannot starve fast ones.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.docs});
  final String title;
  final List<InstructionDoc> docs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < docs.length; i++)
                Container(
                  color: i.isOdd ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(docs[i].name,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                      ),
                      SizedBox(
                        width: 100,
                        child: Text(docs[i].operand,
                            style: TextStyle(
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Expanded(child: Text(docs[i].desc)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
