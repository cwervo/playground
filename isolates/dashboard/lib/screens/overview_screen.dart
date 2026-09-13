import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/sparkline.dart';
import '../widgets/stat_card.dart';

/// Platform-wide health: scheduler counters, isolates, per-worker traffic.
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key, required this.api, required this.onOpenWorker});

  final ApiClient api;
  final void Function(String name) onOpenWorker;

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  PlatformStatus? _status;
  List<WorkerSummary> _workers = const [];
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([widget.api.status(), widget.api.workers()]);
      if (!mounted) return;
      setState(() {
        _status = results[0] as PlatformStatus;
        _workers = results[1] as List<WorkerSummary>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _status;
    if (s == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : _Unreachable(error: _error!, baseUrl: widget.api.baseUrl, onRetry: _refresh),
      );
    }
    final totalRpm = _workers.fold<int>(0, (a, w) => a + w.requestsLastMinute);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text('Lost contact with the runtime: $_error'),
              leading: const Icon(Icons.cloud_off),
              actions: [TextButton(onPressed: _refresh, child: const Text('Retry'))],
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Platform', style: theme.textTheme.headlineMedium),
              const SizedBox(width: 12),
              Text('isolates ${s.version} · ${s.arch} · pid ${s.pid} · up ${fmtDuration(s.uptimeMs)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: _columns(context),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 3.6,
            children: [
              StatCard(
                  label: 'Isolates',
                  value: fmtInt(s.isolates),
                  hint: '${s.inflight} fiber${s.inflight == 1 ? '' : 's'} running now',
                  icon: Icons.memory),
              StatCard(
                  label: 'Requests',
                  value: fmtInt(s.requests),
                  hint: '$totalRpm in the last minute',
                  icon: Icons.bolt),
              StatCard(
                  label: 'Errors',
                  value: fmtInt(s.errors),
                  hint: s.requests == 0
                      ? 'no traffic yet'
                      : '${(100 * s.errors / s.requests).toStringAsFixed(2)}% of requests',
                  icon: Icons.error_outline,
                  color: s.errors > 0 ? theme.colorScheme.error : null),
              StatCard(
                  label: 'Context switches',
                  value: fmtInt(s.contextSwitches),
                  hint: 'assembly iso_ctx_switch calls',
                  icon: Icons.swap_horiz),
              StatCard(
                  label: 'Fibers',
                  value: '${fmtInt(s.fibersDone)} / ${fmtInt(s.fibersTotal)}',
                  hint: 'done / created · ${fmtBytes(s.fiberStackBytes)} stack each',
                  icon: Icons.layers),
              StatCard(
                  label: 'Connections',
                  value: fmtInt(s.connections),
                  hint: '${fmtInt(s.connectionsTotal)} total',
                  icon: Icons.cable),
              StatCard(
                  label: 'Time slice',
                  value: '${fmtInt(s.sliceInstructions)} insn',
                  hint: 'preemption granularity',
                  icon: Icons.timer_outlined),
              StatCard(
                  label: 'Defaults',
                  value: '${fmtInt(s.defaultCpuLimit)} insn',
                  hint: '${fmtBytes(s.defaultMemLimit)} arena · ${s.persistence ? 'persisted' : 'in-memory'}',
                  icon: Icons.tune),
            ],
          ),
          const SizedBox(height: 28),
          Text('Traffic by worker', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Requests per second over the last 60 seconds.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_workers.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Icon(Icons.inbox_outlined, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('No workers deployed yet. Open Workers to deploy one from an example.')),
                  ],
                ),
              ),
            ),
          for (final w in _workers)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onOpenWorker(w.name),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w.name,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontFamily: 'monospace')),
                            Text(
                              '${fmtInt(w.requests)} req · ${fmtInt(w.errors)} err · ${fmtMicros(w.avgCpuUs)} avg cpu',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Sparkline(
                          values: w.rps,
                          height: 36,
                          color: w.errors > 0 && w.errorRate > 0.5
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 64,
                        child: Text('${w.requestsLastMinute}/min',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelLarge),
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

  int _columns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w > 1400) return 4;
    if (w > 900) return 3;
    if (w > 600) return 2;
    return 1;
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.error, required this.baseUrl, required this.onRetry});
  final String error;
  final String baseUrl;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Text('Runtime unreachable', style: Theme.of(context).textTheme.titleLarge),
              ]),
              const SizedBox(height: 12),
              Text('Could not reach the control plane at ${baseUrl.isEmpty ? 'this origin' : baseUrl}.'),
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              const SizedBox(height: 16),
              const Text('Start it with:'),
              const SizedBox(height: 4),
              const SelectableText('make run          # from the isolates/ directory',
                  style: TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 16),
              Row(children: [
                FilledButton.icon(
                    onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                const SizedBox(width: 8),
                const Text('or change the API URL from the toolbar.'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
