import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'click_log.dart';
import 'history_page.dart';
import 'pop_dialog.dart';
import 'pop_sound.dart';

typedef LinkOpener = Future<void> Function(Uri uri);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = ClickLog();
  await log.load();
  runApp(LinkPopApp(
    log: log,
    sound: AssetPopSound(),
    openLink: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
  ));
}

class LinkPopApp extends StatelessWidget {
  const LinkPopApp({
    super.key,
    required this.log,
    required this.sound,
    required this.openLink,
  });

  final ClickLog log;
  final PopSound sound;
  final LinkOpener openLink;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Link Pop',
      theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: Colors.pink,
          brightness: Brightness.dark,
          useMaterial3: true),
      home: HomePage(log: log, sound: sound, openLink: openLink),
    );
  }
}

class Link {
  const Link(this.label, this.url);
  final String label;
  final String url;
}

const _starterLinks = [
  Link('Folk Computer', 'https://folk.computer'),
  Link('Flutter', 'https://flutter.dev'),
  Link('Wikipedia: Onomatopoeia', 'https://en.wikipedia.org/wiki/Onomatopoeia'),
  Link('Bubble wrap', 'https://en.wikipedia.org/wiki/Bubble_wrap'),
];

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.log,
    required this.sound,
    required this.openLink,
  });

  final ClickLog log;
  final PopSound sound;
  final LinkOpener openLink;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Link> _links = [..._starterLinks];
  final _urlField = TextEditingController();
  late final TapGestureRecognizer _inlineFolk = TapGestureRecognizer()
    ..onTap = () => _onLinkTap(_starterLinks[0]);
  late final TapGestureRecognizer _inlineBubble = TapGestureRecognizer()
    ..onTap = () => _onLinkTap(_starterLinks[3]);

  @override
  void dispose() {
    _urlField.dispose();
    _inlineFolk.dispose();
    _inlineBubble.dispose();
    super.dispose();
  }

  /// The one path every link click takes: pop, save, modal, maybe open.
  Future<void> _onLinkTap(Link link) async {
    // Don't let a failed sound (e.g. no audio device) block the rest.
    widget.sound.play().catchError((Object _) {});
    final click = await widget.log.record(link.label, link.url);
    if (!mounted) return;
    final open =
        await showPopDialog(context, click, widget.log.countFor(link.url));
    if (open) await widget.openLink(Uri.parse(link.url));
  }

  void _addLink() {
    var text = _urlField.text.trim();
    if (text.isEmpty) return;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("That doesn't look like a link")));
      return;
    }
    setState(() => _links.insert(0, Link(uri.host, text)));
    _urlField.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      fontWeight: FontWeight.w600,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link Pop 💥'),
        actions: [
          ListenableBuilder(
            listenable: widget.log,
            builder: (context, _) => IconButton(
              tooltip: 'Saved pops',
              icon: Badge.count(
                count: widget.log.total,
                isLabelVisible: widget.log.total > 0,
                child: const Icon(Icons.history),
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => HistoryPage(log: widget.log))),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text.rich(
            TextSpan(
              style: theme.textTheme.bodyLarge,
              children: [
                const TextSpan(text: 'Every link here goes '),
                const TextSpan(
                    text: 'pop', style: TextStyle(fontStyle: FontStyle.italic)),
                const TextSpan(
                    text: '. Each click is saved, plays a pop, and shows a '
                        'modal before anything opens. Try '),
                TextSpan(
                    text: 'Folk Computer',
                    style: linkStyle,
                    recognizer: _inlineFolk),
                const TextSpan(text: ' or some '),
                TextSpan(
                    text: 'bubble wrap',
                    style: linkStyle,
                    recognizer: _inlineBubble),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlField,
                  decoration: const InputDecoration(
                    labelText: 'Add a link',
                    hintText: 'example.com',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  onSubmitted: (_) => _addLink(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add link',
                onPressed: _addLink,
                icon: const Icon(Icons.add_link),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: widget.log,
            builder: (context, _) => Column(
              children: [
                for (final link in _links)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(link.label, style: linkStyle),
                      subtitle: Text(link.url),
                      trailing: _PopCount(widget.log.countFor(link.url)),
                      onTap: () => _onLinkTap(link),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PopCount extends StatelessWidget {
  const _PopCount(this.count);
  final int count;

  @override
  Widget build(BuildContext context) =>
      count == 0 ? const SizedBox.shrink() : Chip(label: Text('$count 💥'));
}
