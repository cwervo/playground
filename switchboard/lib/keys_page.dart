import 'package:material_ui/material_ui.dart';

import 'chat_page.dart';
import 'main.dart';
import 'providers.dart';
import 'store.dart';

class KeysPage extends StatelessWidget {
  const KeysPage({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final palette = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 16),
                        SizedBox(width: 6),
                        Text('Back to chat'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: palette.line),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'API keys',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Text(
                              'Each key is saved in this browser\'s storage '
                              'as you type and is sent only to its own '
                              'provider. Anyone who can use this browser '
                              'profile can read them, so use keys with a '
                              'spending limit. You only need one to start.',
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: palette.muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          for (final p in providers) ...[
                            _KeyCard(store: store, provider: p),
                            const SizedBox(height: 14),
                          ],
                          const SizedBox(height: 14),
                          _SystemPrompt(store: store),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyCard extends StatefulWidget {
  const _KeyCard({required this.store, required this.provider});
  final AppStore store;
  final ModelProvider provider;

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  late final _key = TextEditingController(
    text: widget.store.keyFor(widget.provider.id),
  );
  late final _model = TextEditingController(
    text: widget.store.modelFor(widget.provider),
  );
  bool _show = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final p = widget.provider;
    final palette = Palette.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final hasKey = store.keyFor(p.id).isNotEmpty;
        final check = store.checkFor(p.id);
        final models = store.modelsFor(p.id);
        final current = store.modelFor(p);
        final (status, statusColor) = switch (check) {
          KeyCheck.ok => ('Working', palette.good),
          KeyCheck.failed => ('Not working', palette.bad),
          KeyCheck.checking => ('Checking…', palette.muted),
          KeyCheck.unchecked => (
            hasKey ? 'Saved' : 'No key',
            hasKey ? palette.good : palette.muted,
          ),
        };
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            border: Border.all(color: palette.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProviderDot(p, size: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: p.name,
                        style: const TextStyle(
                          fontSize: 18,
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
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontFamily: mono,
                      fontSize: 13,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: !_show,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: mono, fontSize: 14),
                decoration: InputDecoration(
                  labelText: '${p.maker} API key',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: p.keyHint,
                  suffixIcon: IconButton(
                    tooltip: _show ? 'Hide key' : 'Show key',
                    icon: Icon(
                      _show ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                onChanged: (v) => store.setKey(p.id, v),
                onSubmitted: (_) => store.checkKey(p.id),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: hasKey && check != KeyCheck.checking
                        ? () => store.checkKey(p.id)
                        : null,
                    child: const Text('Check key'),
                  ),
                  KeyLink(p),
                  Text(
                    Uri.parse(p.keyUrl).host,
                    style: TextStyle(
                      fontFamily: mono,
                      fontSize: 12,
                      color: palette.muted,
                    ),
                  ),
                ],
              ),
              if (store.checkDetail(p.id).isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  store.checkDetail(p.id),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: check == KeyCheck.failed
                        ? palette.bad
                        : palette.muted,
                  ),
                ),
              ],
              if (hasKey) ...[
                const SizedBox(height: 14),
                if (models.isEmpty)
                  TextField(
                    controller: _model,
                    autocorrect: false,
                    style: const TextStyle(fontFamily: mono, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      helperText:
                          'Check the key to choose from your account\'s models.',
                    ),
                    onChanged: (v) => store.setModel(p.id, v),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: models.any((m) => m.id == current)
                        ? current
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    hint: Text(current),
                    style: TextStyle(
                      fontFamily: mono,
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    items: [
                      for (final m in models)
                        DropdownMenuItem(
                          value: m.id,
                          child: Text(m.id, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) store.setModel(p.id, v);
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SystemPrompt extends StatefulWidget {
  const _SystemPrompt({required this.store});
  final AppStore store;

  @override
  State<_SystemPrompt> createState() => _SystemPromptState();
}

class _SystemPromptState extends State<_SystemPrompt> {
  late final _controller = TextEditingController(text: widget.store.system);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      minLines: 2,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'System prompt (optional, sent to every provider)',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: 'e.g. Answer briefly. Prefer metric units.',
      ),
      onChanged: widget.store.setSystem,
    );
  }
}
