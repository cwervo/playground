import 'dart:ui' show Color;

/// Which wire protocol a provider speaks.
enum ApiKind { anthropic, openAiCompatible, gemini, demo }

/// One model provider the app can talk to.
///
/// Adding a provider that speaks the OpenAI chat-completions protocol is a
/// single entry in [providers] below.
class ModelProvider {
  const ModelProvider({
    required this.id,
    required this.name,
    required this.maker,
    required this.kind,
    required this.baseUrl,
    required this.keyUrl,
    required this.keyHint,
    required this.defaultModel,
    required this.color,
    this.preferred = const [],
  });

  final String id;

  /// What people call the product, e.g. "Claude".
  final String name;

  /// The company behind it, e.g. "Anthropic".
  final String maker;
  final ApiKind kind;
  final String baseUrl;

  /// Page where a signed-in user creates an API key.
  final String keyUrl;

  /// Placeholder showing what a key usually looks like.
  final String keyHint;

  /// Model used until the account's real model list has been fetched.
  final String defaultModel;

  /// Substrings tried in order to pick a model from the fetched list when
  /// [defaultModel] isn't offered to this account.
  final List<String> preferred;

  final Color color;

  bool get needsKey => kind != ApiKind.demo;
  String get host => needsKey ? Uri.parse(baseUrl).host : 'this device';
}

const demoProvider = ModelProvider(
  id: 'demo',
  name: 'Demo',
  maker: 'No network',
  kind: ApiKind.demo,
  baseUrl: '',
  keyUrl: '',
  keyHint: '',
  defaultModel: 'canned-reply',
  color: Color(0xFF8A8FA8),
);

/// The five frontier providers, in the order they appear in the UI.
const providers = <ModelProvider>[
  ModelProvider(
    id: 'anthropic',
    name: 'Claude',
    maker: 'Anthropic',
    kind: ApiKind.anthropic,
    baseUrl: 'https://api.anthropic.com/v1',
    keyUrl: 'https://platform.claude.com/settings/keys',
    keyHint: 'sk-ant-…',
    defaultModel: 'claude-opus-5-5',
    preferred: ['claude-opus', 'claude-sonnet', 'claude'],
    color: Color(0xFFD97757),
  ),
  ModelProvider(
    id: 'openai',
    name: 'ChatGPT',
    maker: 'OpenAI',
    kind: ApiKind.openAiCompatible,
    baseUrl: 'https://api.openai.com/v1',
    keyUrl: 'https://platform.openai.com/api-keys',
    keyHint: 'sk-…',
    defaultModel: 'gpt-5',
    preferred: ['gpt-5', 'gpt-4', 'gpt'],
    color: Color(0xFF10A37F),
  ),
  ModelProvider(
    id: 'google',
    name: 'Gemini',
    maker: 'Google',
    kind: ApiKind.gemini,
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHint: 'AIza…',
    defaultModel: 'gemini-2.5-pro',
    preferred: ['pro', 'flash', 'gemini'],
    color: Color(0xFF4285F4),
  ),
  ModelProvider(
    id: 'xai',
    name: 'Grok',
    maker: 'xAI',
    kind: ApiKind.openAiCompatible,
    baseUrl: 'https://api.x.ai/v1',
    keyUrl: 'https://console.x.ai',
    keyHint: 'xai-…',
    defaultModel: 'grok-4',
    preferred: ['grok-4', 'grok'],
    color: Color(0xFF6B7280),
  ),
  ModelProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    maker: 'DeepSeek',
    kind: ApiKind.openAiCompatible,
    baseUrl: 'https://api.deepseek.com',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    keyHint: 'sk-…',
    defaultModel: 'deepseek-chat',
    preferred: ['deepseek-chat', 'deepseek'],
    color: Color(0xFF4D6BFE),
  ),
];

ModelProvider providerById(String id) => id == demoProvider.id
    ? demoProvider
    : providers.firstWhere((p) => p.id == id, orElse: () => demoProvider);
