import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/sparkline.dart';
import '../widgets/stat_card.dart';

/// List of deployed workers plus the "new worker" flow.
class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key, required this.api, required this.onOpenWorker});

  final ApiClient api;
  final void Function(String name) onOpenWorker;

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen> {
  List<WorkerSummary>? _workers;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await widget.api.workers();
      if (!mounted) return;
      setState(() {
        _workers = list;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _newWorker() async {
    final created = await showDialog<String>(
      context: context,
      builder: (_) => NewWorkerDialog(api: widget.api),
    );
    if (created != null) {
      await _refresh();
      widget.onOpenWorker(created);
    }
  }

  Future<void> _delete(WorkerSummary w) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${w.name}?'),
            content: const Text(
                'The script, its KV namespace and its logs are removed from the runtime.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await widget.api.deleteWorker(w.name);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workers = _workers;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newWorker,
        icon: const Icon(Icons.add),
        label: const Text('New worker'),
      ),
      body: workers == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text('Could not list workers: $_error'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
              children: [
                Row(children: [
                  Text('Workers', style: theme.textTheme.headlineMedium),
                  const SizedBox(width: 12),
                  Text('${workers.length} deployed',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
                ]),
                const SizedBox(height: 12),
                if (_error != null)
                  MaterialBanner(
                      content: Text(_error!),
                      leading: const Icon(Icons.cloud_off),
                      actions: [TextButton(onPressed: _refresh, child: const Text('Retry'))]),
                if (workers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(children: [
                        Icon(Icons.rocket_launch_outlined,
                            size: 48, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text('Nothing deployed yet', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        const Text('Deploy one of the bundled examples or write your own script.'),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: _newWorker,
                            icon: const Icon(Icons.add),
                            label: const Text('New worker')),
                      ]),
                    ),
                  ),
                for (final w in workers)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onOpenWorker(w.name),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(
                          children: [
                            Icon(Icons.memory,
                                color: w.inflight > 0
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(w.name,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    if (w.inflight > 0)
                                      _Chip('${w.inflight} running', theme.colorScheme.primary),
                                    if (w.errors > 0)
                                      _Chip('${fmtInt(w.errors)} errors', theme.colorScheme.error),
                                  ]),
                                  const SizedBox(height: 2),
                                  Text(
                                    'v${w.deploys} · ${w.instructionsInScript} insn · ${fmtInt(w.cpuLimit)} insn / ${fmtBytes(w.memLimit)} limits · '
                                    '${w.kvEntries} kv · last ${fmtAgo(w.lastInvokedMs)}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Expanded(flex: 2, child: Sparkline(values: w.rps, height: 30)),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 110,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtInt(w.requests), style: theme.textTheme.titleMedium),
                                  Text('requests · ${fmtMicros(w.avgCpuUs)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'open') widget.onOpenWorker(w.name);
                                if (v == 'delete') _delete(w);
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'open', child: Text('Open')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Dialog for creating a worker from an example or a blank script.
class NewWorkerDialog extends StatefulWidget {
  const NewWorkerDialog({super.key, required this.api});
  final ApiClient api;

  @override
  State<NewWorkerDialog> createState() => _NewWorkerDialogState();
}

class _NewWorkerDialogState extends State<NewWorkerDialog> {
  final _name = TextEditingController();
  List<ExampleScript>? _examples;
  ExampleScript? _selected;
  String? _error;
  bool _busy = false;

  static const _blank = '; new worker\npush "hello\\n"\nres.body\nhalt\n';

  @override
  void initState() {
    super.initState();
    widget.api.examples().then((list) {
      if (!mounted) return;
      setState(() {
        _examples = list;
        if (list.isNotEmpty) {
          _selected = list.first;
          _name.text = list.first.name;
        }
      });
    }).catchError((e) {
      if (mounted) setState(() => _examples = const []);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,46}$').hasMatch(name) || name.endsWith('-')) {
      setState(() => _error = 'Names use a-z, 0-9 and "-" (max 47 chars).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deploy(name, script: _selected?.script ?? _blank);
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final examples = _examples;
    return AlertDialog(
      title: const Text('New worker'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'Routes: /w/<name>/…  or  Host: <name>.<domain>',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 16),
            Text('Start from', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            if (examples == null)
              const LinearProgressIndicator()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _ChoiceTile(
                        selected: _selected == null,
                        title: const Text('Blank script'),
                        onTap: () => setState(() => _selected = null),
                      ),
                      for (final ex in examples)
                        _ChoiceTile(
                          selected: identical(_selected, ex),
                          title: Text(ex.name, style: const TextStyle(fontFamily: 'monospace')),
                          subtitle: ex.description.isEmpty ? null : Text(ex.description),
                          onTap: () => setState(() {
                            _selected = ex;
                            if (_name.text.isEmpty || examples.any((e) => e.name == _name.text)) {
                              _name.text = ex.name;
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _create, child: const Text('Deploy')),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final bool selected;
  final Widget title;
  final Widget? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
