# Switchboard

One conversation, five frontier model providers. A Flutter web app (installable
as a PWA) where you paste your own API keys and talk to each provider directly
from the browser. It grew out of [`gc`](../gc), the Gemini chat CLI in this
repo: same bring-your-own-key idea, with a UI and four more providers.

| Provider | Maker | Get a key |
| --- | --- | --- |
| Claude | Anthropic | https://platform.claude.com/settings/keys |
| ChatGPT | OpenAI | https://platform.openai.com/api-keys |
| Gemini | Google | https://aistudio.google.com/apikey |
| Grok | xAI | https://console.x.ai |
| DeepSeek | DeepSeek | https://platform.deepseek.com/api_keys |

## What it does

- Streams replies from each provider's own API. There is no server in between.
- Switch provider between messages; the conversation so far goes to whichever
  one answers next.
- "Check key" asks the provider which models the key can use and fills the
  model picker from that list, so model names don't go stale in the source.
- A Demo line answers locally with no key and no network.
- Composer commands: `/help`, `/keys`, `/use <provider>`, `/model <id>`,
  `/system <text>`, `/clear`.

Keys, the chosen models and the current conversation are kept in the browser's
local storage. Keys are sent only to the provider they belong to. Anyone with
access to the browser profile can read them, so prefer keys with a spend limit.

## Run and build

```sh
flutter pub get
flutter run -d chrome                           # develop
flutter build web --release --no-web-resources-cdn   # PWA in build/web
```

`--no-web-resources-cdn` bundles CanvasKit so the app works offline. Serve
`build/web` from any static host over HTTPS to install it. `web/sw.js` caches
the app shell for offline use (Flutter no longer generates a caching service
worker); it never touches requests to the model providers.

If the app is served from a sub-path, pass `--base-href /that/path/`.

## Layout

- `lib/providers.dart`: the provider table. Adding another OpenAI-compatible
  provider is one entry here.
- `lib/llm_client.dart`: streaming clients for the three wire protocols
  (Anthropic Messages, OpenAI chat completions, Gemini) and model listing.
- `lib/store.dart`: persisted state and the send loop.
- `lib/chat_page.dart`, `lib/keys_page.dart`, `lib/main.dart`: screens and theme.

Fonts are IBM Plex Sans and IBM Plex Mono (SIL Open Font License, see
`assets/fonts/OFL-LICENSE.txt`).
