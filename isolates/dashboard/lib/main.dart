import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/overview_screen.dart';
import 'screens/reference_screen.dart';
import 'screens/worker_screen.dart';
import 'screens/workers_screen.dart';

void main() {
  runApp(const IsolatesDashboard());
}

class IsolatesDashboard extends StatelessWidget {
  const IsolatesDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFF6821F);
    return MaterialApp(
      title: 'isolates',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 4)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 4)),
      ),
      themeMode: ThemeMode.system,
      home: const Shell(),
    );
  }
}

enum _Section { overview, workers, reference }

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final ApiClient _api = ApiClient();
  _Section _section = _Section.overview;
  String? _openWorker;

  void _open(String name) => setState(() {
        _section = _Section.workers;
        _openWorker = name;
      });

  Future<void> _editBaseUrl() async {
    final ctl = TextEditingController(text: _api.baseUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Runtime API URL'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'http://127.0.0.1:8787',
              helperText: 'Leave empty to use the origin this page was served from.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (s) => Navigator.pop(ctx, s),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) {
      setState(() {
        _api.baseUrl = v.trim();
        _openWorker = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body = switch (_section) {
      _Section.overview => OverviewScreen(key: const ValueKey('overview'), api: _api, onOpenWorker: _open),
      _Section.workers => _openWorker == null
          ? WorkersScreen(key: const ValueKey('workers'), api: _api, onOpenWorker: _open)
          : WorkerScreen(
              key: ValueKey('worker-$_openWorker'),
              api: _api,
              name: _openWorker!,
              onBack: () => setState(() => _openWorker = null)),
      _Section.reference => ReferenceScreen(key: const ValueKey('reference'), api: _api),
    };
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _section.index,
            onDestinationSelected: (i) => setState(() {
              _section = _Section.values[i];
              if (_section != _Section.workers) _openWorker = null;
            }),
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(Icons.hub, color: theme.colorScheme.primary, size: 30),
                const SizedBox(height: 4),
                Text('isolates',
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: 'Runtime API URL',
                    onPressed: _editBaseUrl,
                    icon: const Icon(Icons.settings_ethernet),
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: Text('Overview')),
              NavigationRailDestination(
                  icon: Icon(Icons.memory_outlined),
                  selectedIcon: Icon(Icons.memory),
                  label: Text('Workers')),
              NavigationRailDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book),
                  label: Text('Reference')),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}
