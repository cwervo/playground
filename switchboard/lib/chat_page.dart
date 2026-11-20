import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/link.dart';
import 'package:url_launcher/url_launcher.dart';

import 'keys_page.dart';
import 'main.dart';
import 'providers.dart';
import 'store.dart';

const _helpText =
    '/help             this list\n'
    '/keys             add or change API keys\n'
    '/use <provider>   switch line: claude, chatgpt, gemini, grok, deepseek, demo\n'
    '/model <id>       set the model for the current provider\n'
    '/system <text>    set the system prompt (empty to clear)\n'
    '/clear            start a new conversation';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.store});
  final AppStore store;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  bool _pinned = true;

  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_followReply);
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _pinned = _scroll.position.maxScrollExtent - _scroll.offset < 120;
    });
  }

  @override
  void dispose() {
    store.removeListener(_followReply);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Keeps the newest text in view unless the reader has scrolled up.
  void _followReply() {
    if (!_pinned) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !_input.value.composing.isValid) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openKeys() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => KeysPage(store: store)));
    // Back from the Keys screen: put the cursor where typing continues.
    _focus.requestFocus();
  }

  void _submit() {
    final text = _input.text.trim();
    if (text.isEmpty || store.busy) return;
    _input.clear();
    _pinned = true;
    if (text.startsWith('/')) {
      _command(text);
    } else {
      store.send(text);
    }
    _focus.requestFocus();
  }

  void _command(String line) {
    final space = line.indexOf(' ');
    final name = (space < 0 ? line : line.substring(0, space)).toLowerCase();
    final arg = space < 0 ? '' : line.substring(space + 1).trim();
    switch (name) {
      case '/help':
        store.addNote(_helpText);
      case '/keys':
        _openKeys();
      case '/clear' || '/new':
        store.newChat();
      case '/system':
        store.setSystem(arg);
        store.addNote(
          arg.isEmpty ? 'System prompt cleared.' : 'System prompt set.',
        );
      case '/model':
        if (arg.isEmpty) {
          store.addNote(
            '${store.active.name} is using ${store.modelFor(store.active)}.',
          );
        } else if (!store.active.needsKey) {
          store.addNote('The demo line has only one canned model.');
        } else {
          store.setModel(store.activeId, arg);
          store.addNote('${store.active.name} will use $arg.');
        }
      case '/use':
        final want = arg.toLowerCase();
        final match = [demoProvider, ...providers]
            .where(
              (p) =>
                  p.id == want ||
                  p.name.toLowerCase() == want ||
                  p.maker.toLowerCase() == want,
            )
            .firstOrNull;
        if (match == null) {
          store.addNote(
            'No provider called "$arg". Try claude, chatgpt, gemini, grok, '
            'deepseek or demo.',
          );
        } else if (!store.hasKey(match.id)) {
          store.addNote('${match.name} has no key yet. Type /keys to add one.');
        } else {
          store.setActive(match.id);
          store.addNote(
            'Switched to ${match.name} (${store.modelFor(match)}).',
          );
        }
      default:
        store.addNote('Unknown command $name. Type /help for the list.');
    }
  }

  void _pickProvider() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ProviderSheet(store: store, onKeys: _openKeys),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final palette = Palette.of(context);
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _TopBar(
                  store: store,
                  onSwitch: _pickProvider,
                  onKeys: _openKeys,
                ),
                Divider(color: palette.line),
                Expanded(
                  child: store.messages.isEmpty
                      ? _Welcome(store: store, onKeys: _openKeys)
                      : SelectionArea(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            itemCount: store.messages.length,
                            itemBuilder: (context, i) => _Centered(
                              child: _Bubble(
                                message: store.messages[i],
                                streaming:
                                    store.busy &&
                                    i == store.messages.length - 1,
                              ),
                            ),
                          ),
                        ),
                ),
                Divider(color: palette.line),
                _Centered(child: _composer(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final p = store.active;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              autofocus: true,
              minLines: 1,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Message ${p.name}, or /help',
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (store.busy)
            OutlinedButton(onPressed: store.stop, child: const Text('Stop'))
          else
            FilledButton(onPressed: _submit, child: const Text('Send')),
        ],
      ),
    );
  }
}

/// Holds content to a readable measure with a 16px gutter.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

class ProviderDot extends StatelessWidget {
  const ProviderDot(this.provider, {super.key, this.size = 10});
  final ModelProvider provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: provider.color, shape: BoxShape.circle),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.store,
    required this.onSwitch,
    required this.onKeys,
  });
  final AppStore store;
  final VoidCallback onSwitch;
  final VoidCallback onKeys;

  @override
  Widget build(BuildContext context) {
    final p = store.active;
    final palette = Palette.of(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Switch provider. Current: ${p.name}',
                child: OutlinedButton(
                  onPressed: onSwitch,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProviderDot(p),
                      const SizedBox(width: 10),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontFamily: 'IBM Plex Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          store.modelFor(p),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.unfold_more, size: 18, color: palette.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (store.messages.isNotEmpty)
            TextButton(onPressed: store.newChat, child: const Text('New chat')),
          TextButton(onPressed: onKeys, child: const Text('Keys')),
        ],
      ),
    );
  }
}

class _ProviderSheet extends StatelessWidget {
  const _ProviderSheet({required this.store, required this.onKeys});
  final AppStore store;
  final VoidCallback onKeys;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  'ANSWER THE NEXT MESSAGE WITH',
                  style: TextStyle(
                    fontFamily: mono,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: palette.muted,
                  ),
                ),
              ),
              for (final p in [...providers, demoProvider])
                _row(context, p, palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, ModelProvider p, Palette palette) {
    final ready = store.hasKey(p.id);
    final selected = store.activeId == p.id;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        Navigator.of(context).pop();
        if (ready) {
          store.setActive(p.id);
        } else {
          onKeys();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? palette.panel : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Opacity(opacity: ready ? 1 : 0.35, child: ProviderDot(p, size: 12)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: p.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: p.maker == p.name ? '' : '  ${p.maker}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ready ? store.modelFor(p) : 'No key yet',
                    style: TextStyle(
                      fontFamily: mono,
                      fontSize: 13,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 20, color: scheme.primary)
            else if (!ready)
              Text(
                'Add key',
                style: TextStyle(
                  fontFamily: mono,
                  fontSize: 13,
                  color: scheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// First-run view: what the app does and where each key comes from.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.store, required this.onKeys});
  final AppStore store;
  final VoidCallback onKeys;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: _Centered(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'switchboard',
              style: TextStyle(
                fontFamily: mono,
                fontSize: 14,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'One conversation.\nFive model providers.',
              style: TextStyle(
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                'Paste your own API keys and talk to each provider directly '
                'from this browser. Switch provider between messages and the '
                'conversation carries over. Keys are stored on this device '
                'and sent only to the provider they belong to.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: palette.muted,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: palette.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (final (i, p) in providers.indexed) ...[
                    if (i > 0) Divider(color: palette.line),
                    _providerRow(context, p, palette),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: onKeys,
                  child: Text(store.hasAnyKey ? 'Manage keys' : 'Add a key'),
                ),
                if (!store.hasAnyKey)
                  OutlinedButton(
                    onPressed: () => store.send(
                      'Show me how this works before I add a key.',
                    ),
                    child: const Text('Try the demo line'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerRow(BuildContext context, ModelProvider p, Palette palette) {
    final ready = store.hasKey(p.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(
        children: [
          ProviderDot(p),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: p.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  TextSpan(
                    text: p.maker == p.name ? '' : '  ${p.maker}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (ready)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Text(
                'Key saved',
                style: TextStyle(
                  fontFamily: mono,
                  fontSize: 13,
                  color: palette.good,
                ),
              ),
            )
          else
            KeyLink(p),
        ],
      ),
    );
  }
}

/// A real link to the page where a provider issues API keys.
class KeyLink extends StatelessWidget {
  const KeyLink(this.provider, {super.key});
  final ModelProvider provider;

  @override
  Widget build(BuildContext context) {
    return Link(
      uri: Uri.parse(provider.keyUrl),
      target: LinkTarget.blank,
      builder: (context, follow) => TextButton(
        onPressed: follow,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Get a key', semanticsLabel: 'Get a key from ${provider.maker}'),
            const SizedBox(width: 4),
            const Icon(Icons.north_east, size: 14),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.streaming});
  final Message message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    final scheme = Theme.of(context).colorScheme;
    const body = TextStyle(fontSize: 16, height: 1.55);

    if (message.role == 'note') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          message.text,
          style: TextStyle(
            fontFamily: mono,
            fontSize: 13,
            height: 1.6,
            color: palette.muted,
          ),
        ),
      );
    }

    if (message.role == 'user') {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 10, bottom: 10, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: palette.panel,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(message.text, style: body),
        ),
      );
    }

    final p = providerById(message.providerId ?? demoProvider.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProviderDot(p, size: 8),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${p.name}  ${message.model ?? ''}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: mono,
                    fontSize: 13,
                    color: palette.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (message.text.isNotEmpty)
            MarkdownBody(
              data: message.text,
              onTapLink: (_, href, _) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null && uri.hasScheme) launchUrl(uri);
              },
              styleSheet: MarkdownStyleSheet(
                p: body.copyWith(color: scheme.onSurface),
                listBullet: body.copyWith(color: scheme.onSurface),
                h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                h2: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                h3: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                a: TextStyle(
                  color: scheme.primary,
                  decoration: TextDecoration.underline,
                ),
                code: TextStyle(
                  fontFamily: mono,
                  fontSize: 14,
                  color: scheme.primary,
                  backgroundColor: palette.panel,
                ),
                codeblockPadding: const EdgeInsets.all(12),
                codeblockDecoration: BoxDecoration(
                  color: palette.panel,
                  borderRadius: BorderRadius.circular(6),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: palette.line, width: 3),
                  ),
                ),
                blockquotePadding: const EdgeInsets.only(left: 12),
                tableBorder: TableBorder.all(color: palette.line),
                tableCellsPadding: const EdgeInsets.all(8),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(top: BorderSide(color: palette.line)),
                ),
                blockSpacing: 12,
              ),
            )
          else if (streaming)
            Text(
              'Waiting for ${p.name}…',
              style: body.copyWith(color: palette.muted),
            ),
          for (final note in message.notes)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                note,
                style: TextStyle(
                  fontFamily: mono,
                  fontSize: 13,
                  color: palette.muted,
                ),
              ),
            ),
          if (message.error != null)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: palette.bad),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                message.error!,
                style: TextStyle(fontSize: 15, height: 1.45, color: palette.bad),
              ),
            ),
        ],
      ),
    );
  }
}
