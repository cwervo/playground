import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../widgets/stat_card.dart';

/// One worker: script editor + deploy, invoke console, logs, KV browser.
class WorkerScreen extends StatefulWidget {
  const WorkerScreen({super.key, required this.api, required this.name, required this.onBack});

  final ApiClient api;
  final String name;
  final VoidCallback onBack;

  @override
  State<WorkerScreen> createState() => _WorkerScreenState();
}

class _WorkerScreenState extends State<WorkerScreen> {
  WorkerDetail? _detail;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent: true));
  }

  @override
  void didUpdateWidget(covariant WorkerScreen old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) {
      _detail = null;
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final d = await widget.api.worker(widget.name);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _detail == null) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _detail;
    if (d == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Could not load ${widget.name}: $_error'),
                const SizedBox(height: 8),
                TextButton(onPressed: widget.onBack, child: const Text('Back to workers')),
              ]),
      );
    }
    final url = widget.api.workerUrl(d.name);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 0),
            child: Row(
              children: [
                IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: 4),
                Text(d.name,
                    style: theme.textTheme.headlineMedium?.copyWith(fontFamily: 'monospace')),
                const SizedBox(width: 16),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SelectableText(url,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      IconButton(
                        tooltip: 'Copy URL',
                        iconSize: 18,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: url));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Copied worker URL')));
                        },
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox(
              height: 92,
              child: Row(
                children: [
                  Expanded(child: StatCard(label: 'Requests', value: fmtInt(d.requests), hint: '${d.requestsLastMinute} last minute', icon: Icons.bolt)),
                  const SizedBox(width: 10),
                  Expanded(child: StatCard(label: 'Errors', value: fmtInt(d.errors), hint: '${(100 * d.errorRate).toStringAsFixed(1)}%', icon: Icons.error_outline, color: d.errors > 0 ? theme.colorScheme.error : null)),
                  const SizedBox(width: 10),
                  Expanded(child: StatCard(label: 'Avg CPU', value: fmtMicros(d.avgCpuUs), hint: 'max ${fmtMicros(d.maxCpuNs / 1000)}', icon: Icons.speed)),
                  const SizedBox(width: 10),
                  Expanded(child: StatCard(label: 'Instructions', value: fmtInt(d.instructions), hint: 'limit ${fmtInt(d.cpuLimit)} / req', icon: Icons.functions)),
                  const SizedBox(width: 10),
                  Expanded(child: StatCard(label: 'Peak memory', value: fmtBytes(d.peakMem), hint: 'limit ${fmtBytes(d.memLimit)}', icon: Icons.sd_storage_outlined)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const TabBar(tabs: [
            Tab(text: 'Script', icon: Icon(Icons.code, size: 18)),
            Tab(text: 'Invoke', icon: Icon(Icons.play_arrow, size: 18)),
            Tab(text: 'Logs', icon: Icon(Icons.receipt_long, size: 18)),
            Tab(text: 'KV', icon: Icon(Icons.storage, size: 18)),
          ]),
          Expanded(
            child: TabBarView(
              children: [
                _ScriptTab(api: widget.api, detail: d, onDeployed: _load),
                _InvokeTab(api: widget.api, name: d.name),
                _LogsTab(api: widget.api, name: d.name),
                _KvTab(api: widget.api, name: d.name),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Script tab
// ---------------------------------------------------------------------
class _ScriptTab extends StatefulWidget {
  const _ScriptTab({required this.api, required this.detail, required this.onDeployed});
  final ApiClient api;
  final WorkerDetail detail;
  final Future<void> Function() onDeployed;

  @override
  State<_ScriptTab> createState() => _ScriptTabState();
}

class _ScriptTabState extends State<_ScriptTab> {
  late final TextEditingController _script = TextEditingController(text: widget.detail.script);
  late final TextEditingController _cpu = TextEditingController(text: '${widget.detail.cpuLimit}');
  late final TextEditingController _mem = TextEditingController(text: '${widget.detail.memLimit}');
  late final TextEditingController _env = TextEditingController(
      text: widget.detail.env.entries.map((e) => '${e.key}=${e.value}').join('\n'));
  AssembleResult? _check;
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;
  bool _showListing = false;
  int _deployedVersion = 0;

  @override
  void initState() {
    super.initState();
    _deployedVersion = widget.detail.deploys;
  }

  @override
  void didUpdateWidget(covariant _ScriptTab old) {
    super.didUpdateWidget(old);
    // Another client deployed a new version: refresh the editor if the
    // user has not touched it.
    if (widget.detail.deploys != _deployedVersion && _script.text == old.detail.script) {
      _script.text = widget.detail.script;
      _deployedVersion = widget.detail.deploys;
    }
  }

  @override
  void dispose() {
    _script.dispose();
    _cpu.dispose();
    _mem.dispose();
    _env.dispose();
    super.dispose();
  }

  Map<String, String> _parseEnv() {
    final out = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final i = t.indexOf('=');
      if (i <= 0) continue;
      out[t.substring(0, i).trim()] = t.substring(i + 1);
    }
    return out;
  }

  Future<void> _assemble() async {
    setState(() => _busy = true);
    try {
      final r = await widget.api.assemble(_script.text);
      if (!mounted) return;
      setState(() {
        _check = r;
        _message = r.ok
            ? 'Assembled: ${r.instructions} instructions, ${r.constants} constants'
            : r.error;
        _messageIsError = !r.ok;
        _showListing = r.ok && _showListing;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = '$e';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deploy() async {
    setState(() => _busy = true);
    try {
      final d = await widget.api.deploy(
        widget.detail.name,
        script: _script.text,
        cpuLimit: int.tryParse(_cpu.text.trim()),
        memLimit: int.tryParse(_mem.text.trim()),
        env: _parseEnv(),
      );
      if (!mounted) return;
      _deployedVersion = d.deploys;
      setState(() {
        _message = 'Deployed version ${d.deploys} (${d.instructionsInScript} instructions). '
            'In-flight requests finish on the previous version.';
        _messageIsError = false;
        _cpu.text = '${d.cpuLimit}';
        _mem.text = '${d.memLimit}';
      });
      await widget.onDeployed();
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e is ApiException ? e.message : '$e';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.of(context).size.width > 1000;
    final editor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _script,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
              hintText: '; one instruction per line\npush "hello"\nres.body\nhalt',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _deploy,
              icon: const Icon(Icons.rocket_launch),
              label: const Text('Deploy'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _assemble,
              icon: const Icon(Icons.check),
              label: const Text('Assemble'),
            ),
            const SizedBox(width: 8),
            if (_check != null && _check!.ok)
              TextButton.icon(
                onPressed: () => setState(() => _showListing = !_showListing),
                icon: Icon(_showListing ? Icons.visibility_off : Icons.visibility),
                label: const Text('Bytecode'),
              ),
            const SizedBox(width: 12),
            if (_message != null)
              Expanded(
                child: Text(
                  _message!,
                  style: TextStyle(
                      color: _messageIsError ? theme.colorScheme.error : theme.colorScheme.primary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
          ],
        ),
        if (_showListing && _check != null && _check!.ok) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: Card(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  for (final l in _check!.listing)
                    Text('${l.pc.toString().padLeft(4)}  ${l.text}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Limits', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _cpu,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'CPU budget (instructions per request)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _mem,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Memory arena (bytes per request)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 20),
        Text('Bindings', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('One NAME=value per line, read with the env instruction.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _env,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
              hintText: 'GREETING=hello\nAPI_KEY=…',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Changes to limits and bindings apply on the next Deploy.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(20),
      child: wide
          ? Row(children: [
              Expanded(flex: 3, child: editor),
              const SizedBox(width: 20),
              SizedBox(width: 320, child: settings),
            ])
          : Column(children: [
              Expanded(flex: 3, child: editor),
              const SizedBox(height: 16),
              Expanded(flex: 2, child: settings),
            ]),
    );
  }
}

// ---------------------------------------------------------------------
// Invoke tab
// ---------------------------------------------------------------------
class _InvokeTab extends StatefulWidget {
  const _InvokeTab({required this.api, required this.name});
  final ApiClient api;
  final String name;

  @override
  State<_InvokeTab> createState() => _InvokeTabState();
}

class _InvokeTabState extends State<_InvokeTab> {
  String _method = 'GET';
  final _path = TextEditingController(text: '/');
  final _headers = TextEditingController();
  final _body = TextEditingController();
  InvokeResult? _result;
  String? _error;
  bool _busy = false;
  final List<InvokeResult> _history = [];

  @override
  void dispose() {
    _path.dispose();
    _headers.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final headers = <String, String>{};
    for (final line in _headers.text.split('\n')) {
      final i = line.indexOf(':');
      if (i > 0) headers[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    try {
      final r = await widget.api.invoke(widget.name,
          method: _method, path: _path.text.trim().isEmpty ? '/' : _path.text.trim(),
          headers: headers, body: _body.text);
      if (!mounted) return;
      setState(() {
        _result = r;
        _history.insert(0, r);
        if (_history.length > 20) _history.removeLast();
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  DropdownMenu<String>(
                    initialSelection: _method,
                    width: 120,
                    inputDecorationTheme: const InputDecorationTheme(isDense: true, border: OutlineInputBorder()),
                    dropdownMenuEntries: const [
                      DropdownMenuEntry(value: 'GET', label: 'GET'),
                      DropdownMenuEntry(value: 'POST', label: 'POST'),
                      DropdownMenuEntry(value: 'PUT', label: 'PUT'),
                      DropdownMenuEntry(value: 'DELETE', label: 'DELETE'),
                      DropdownMenuEntry(value: 'PATCH', label: 'PATCH'),
                    ],
                    onSelected: (v) => setState(() => _method = v ?? 'GET'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _path,
                      style: const TextStyle(fontFamily: 'monospace'),
                      decoration: const InputDecoration(
                          labelText: 'Path', isDense: true, border: OutlineInputBorder()),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: _headers,
                  maxLines: 3,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                      labelText: 'Headers (Name: value per line)',
                      isDense: true,
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  maxLines: 6,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                      labelText: 'Body', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Send'),
                ),
                const SizedBox(height: 16),
                if (_history.length > 1) ...[
                  Text('Recent', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final h in _history)
                          ListTile(
                            dense: true,
                            leading: _StatusDot(h),
                            title: Text(
                                '${h.status}  ·  ${fmtInt(h.instructions)} insn  ·  ${fmtMicros(h.cpuUs.toDouble())}',
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                            onTap: () => setState(() => _result = h),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: r == null
                ? Center(
                    child: Text(
                      _error ?? 'Send a request to see the response and per-request metrics.',
                      style: TextStyle(
                          color: _error != null
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : _ResponseView(result: r, error: _error),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot(this.r);
  final InvokeResult r;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = !r.ok ? cs.error : (r.status >= 400 ? Colors.orange : Colors.green);
    return Icon(Icons.circle, size: 10, color: color);
  }
}

class _ResponseView extends StatelessWidget {
  const _ResponseView({required this.result, this.error});
  final InvokeResult result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;
    final cpuPct = r.cpuLimit == 0 ? 0.0 : (r.instructions / r.cpuLimit).clamp(0.0, 1.0);
    final memPct = r.memLimit == 0 ? 0.0 : (r.memPeak / r.memLimit).clamp(0.0, 1.0);
    return ListView(
      children: [
        Row(children: [
          _StatusDot(r),
          const SizedBox(width: 8),
          Text(r.ok ? 'HTTP ${r.status}' : 'Error ${r.errorCode}',
              style: theme.textTheme.titleLarge),
          const SizedBox(width: 16),
          Text(
            '${fmtInt(r.instructions)} instructions · ${fmtMicros(r.cpuUs.toDouble())} cpu · '
            '${fmtMicros(r.wallUs.toDouble())} wall · ${fmtBytes(r.memPeak)} peak · ${r.switches} switches',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
        const SizedBox(height: 10),
        _Meter(label: 'CPU budget', pct: cpuPct, text: '${fmtInt(r.instructions)} / ${fmtInt(r.cpuLimit)}'),
        const SizedBox(height: 6),
        _Meter(label: 'Memory arena', pct: memPct, text: '${fmtBytes(r.memPeak)} / ${fmtBytes(r.memLimit)}'),
        const SizedBox(height: 14),
        if (!r.ok)
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  '${r.errorCode == 1102 ? 'Worker exceeded resource limits' : 'Worker threw exception'}\n${r.error}',
                  style: TextStyle(
                      fontFamily: 'monospace', color: theme.colorScheme.onErrorContainer)),
            ),
          ),
        if (r.headers.isNotEmpty) ...[
          Text('Headers', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          for (final h in r.headers.entries)
            SelectableText('${h.key}: ${h.value}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          const SizedBox(height: 12),
        ],
        Text('Body', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(r.body.isEmpty ? '(empty)' : r.body,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.pct, required this.text});
  final String label;
  final double pct;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = pct >= 1 ? theme.colorScheme.error : (pct > 0.75 ? Colors.orange : theme.colorScheme.primary);
    return Row(children: [
      SizedBox(width: 110, child: Text(label, style: theme.textTheme.bodySmall)),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct, minHeight: 8, color: color),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 170,
        child: Text(text,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------
// Logs tab
// ---------------------------------------------------------------------
class _LogsTab extends StatefulWidget {
  const _LogsTab({required this.api, required this.name});
  final ApiClient api;
  final String name;

  @override
  State<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<_LogsTab> {
  List<LogEntry> _logs = const [];
  Timer? _timer;
  bool _follow = true;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final logs = await widget.api.logs(widget.name);
      if (!mounted) return;
      final grew = logs.length != _logs.length;
      setState(() => _logs = logs);
      if (_follow && grew && _scroll.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(children: [
            Text('${_logs.length} entries (ring buffer keeps the last 256)',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Spacer(),
            FilterChip(
              label: const Text('Follow'),
              selected: _follow,
              onSelected: (v) => setState(() => _follow = v),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                await widget.api.clearLogs(widget.name);
                _refresh();
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear'),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _logs.isEmpty
                  ? Center(
                      child: Text('No log lines yet. Use the log instruction in your script.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      itemCount: _logs.length,
                      itemBuilder: (_, i) {
                        final e = _logs[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(fmtClock(e.tsMs),
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SelectableText(e.msg,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: e.isError ? theme.colorScheme.error : null)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------
// KV tab
// ---------------------------------------------------------------------
class _KvTab extends StatefulWidget {
  const _KvTab({required this.api, required this.name});
  final ApiClient api;
  final String name;

  @override
  State<_KvTab> createState() => _KvTabState();
}

class _KvTabState extends State<_KvTab> {
  List<KvEntry> _entries = const [];
  Timer? _timer;
  final _key = TextEditingController();
  final _value = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _key.dispose();
    _value.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final list = await widget.api.kv(widget.name);
      if (mounted) setState(() => _entries = list);
    } catch (_) {}
  }

  Future<void> _put() async {
    final k = _key.text.trim();
    if (k.isEmpty) return;
    try {
      await widget.api.kvPut(widget.name, k, _value.text);
      _key.clear();
      _value.clear();
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: _key,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Key', isDense: true, border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _value,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder()),
                onSubmitted: (_) => _put(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _put, child: const Text('Put')),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _entries.isEmpty
                  ? null
                  : () async {
                      await widget.api.kvClear(widget.name);
                      _refresh();
                    },
              child: const Text('Clear all'),
            ),
          ]),
          const SizedBox(height: 12),
          Text('${_entries.length} entries · shared by every request to this worker',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: _entries.isEmpty
                  ? Center(
                      child: Text('Namespace is empty.',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _entries[i];
                        return ListTile(
                          dense: true,
                          title: Text(e.key, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                          subtitle: Text(e.value.length > 200 ? '${e.value.substring(0, 200)}…' : e.value,
                              style: const TextStyle(fontFamily: 'monospace')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(fmtAgo(e.updatedMs), style: theme.textTheme.bodySmall),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () {
                                _key.text = e.key;
                                _value.text = e.value;
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                await widget.api.kvDelete(widget.name, e.key);
                                _refresh();
                              },
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
