# AI providers

Clevylo supports **Ollama and OpenRouter**. Choose a provider and its runtime model in Settings. Each adapter handles model discovery, streaming, cancellation, image inputs, and structured study generation.

## Ollama: local default

Install and open [Ollama](https://ollama.com/), and install a suitable local model using Ollama's own interface. Clevylo does not install Ollama, download models, sign into cloud services, or change daemon configuration. In Clevylo Settings, choose Ollama, refresh models, select an installed model, and test the connection. No API key is needed. A vision-capable model is required for worksheet images; text-only models can still use extracted text.

The adapter calls only `http://127.0.0.1:11434`: `GET /api/tags` for discovery, `POST /api/show` to inspect a selected model, and streaming `POST /api/chat`. It never sends the OpenRouter key to Ollama. The current documented chat format uses message content, optional base64 images, and an optional JSON schema in `format`; replies arrive as newline-delimited JSON. See [Ollama chat](https://docs.ollama.com/api/chat), [model listing](https://docs.ollama.com/api/tags), and [structured outputs](https://docs.ollama.com/capabilities/structured-outputs).

Ollama itself supports cloud models. Clevylo filters cloud-named entries and remote metadata from discovery, and checks `/api/show` before sending student content, rejecting `remote_host` or `remote_model`. It requires local `model_info`. A trusted local Ollama daemon is still part of the privacy boundary; Clevylo cannot attest to a modified daemon's behavior. For strict local-only use, Ollama documents `disable_ollama_cloud: true` in its server configuration or `OLLAMA_NO_CLOUD=1`, followed by restarting Ollama. These are optional user-managed settings. See the [official Ollama FAQ](https://docs.ollama.com/faq#how-do-i-disable-ollama-cloud-features) and [official API type definitions](https://github.com/ollama/ollama/blob/main/api/types.go).

## OpenRouter: optional cloud

Create your own [OpenRouter API key](https://openrouter.ai/settings/keys), save it in Clevylo Settings, refresh the model catalog, and choose a model ID. OpenRouter account credits, free-model limitations, and provider billing are separate from a ChatGPT subscription. Consult the selected model's current pricing before use. The connection test performs a real short generation and may incur usage charges.

Keys are stored only in the macOS login Keychain under service `com.clevylo.app.credentials`, account `openrouter-api-key`, with device-only unlocked accessibility and synchronization disabled. Save replaces the same item; delete removes it. No key belongs in the library JSON, source repository, or diagnostics.

The public catalog is `GET https://openrouter.ai/api/v1/models`; it is fetched without credentials. Generation uses authenticated `POST https://openrouter.ai/api/v1/chat/completions`. See the [official quickstart](https://openrouter.ai/docs/quickstart). Local images are encoded as `image_url` data URLs in a multipart user message. Images require a compatible model; see [image inputs](https://openrouter.ai/docs/guides/overview/multimodal/image-understanding). Study generation requests a strict JSON schema and `require_parameters: true` so an incompatible route reports an error instead of silently ignoring the schema. See [structured outputs](https://openrouter.ai/docs/guides/features/structured-outputs).

Clevylo requires cloud consent before sending student content. Only the chosen question, conversation context, images, and retrieved passages are supplied. OpenRouter routes the request to the selected model's upstream provider; their applicable data policies govern processing.

## Behavior and limits

- Both adapters use cancellable URLSession streams with ephemeral sessions, no cookies, no URL cache, no credential storage, fixed destinations, and all HTTP redirects rejected. Ollama also bypasses configured proxies.
- OpenRouter SSE parsing handles comments, multiline events, arbitrary byte boundaries, Unicode, repeated terminal usage frames, and `[DONE]`. Ollama parses NDJSON. No reasoning-token stream is shown and no tool calls are executed. See [OpenRouter streaming](https://openrouter.ai/docs/api_reference/streaming).
- Cancellation closes that operation's connection. OpenRouter upstream processing and billing may continue for providers that do not support cancellation, as described in the streaming documentation.
- Network request timeout is 90 seconds; total resource timeout is 300 seconds. Output is bounded to 4 MiB of streamed events and 8,192 generated tokens. Images are limited to four, totaling 20 MiB; full request data is capped at 30 MiB. Smaller inputs may be required by the selected model.
- Truncation, malformed events, refusal, HTTP errors, incomplete streams, and empty output surface as errors. Partial streamed text is not a successfully completed study set. Study parsing validates generated data separately before saving.
- Sources are JSON-encoded in a separate user reference message. Trusted instructions explicitly treat references and images as untrusted material. No tool definitions, command execution, or secret lookup are exposed to models. This constrains capabilities; it is not a guarantee that a language model will never follow misleading prose.
- Exact vision, context, and schema support varies by model and provider. Current Ollama versions are recommended; older daemons may not honor explicit context-truncation controls.

## Verification

`ProviderTests` uses only synthetic URLProtocol responses and tests real adapter request construction and URLSession stream handling, including cancellation. It covers both wire formats, Unicode framing, source separation, image encoding, schema isolation, key isolation, model discovery, remote Ollama aliases, redirects, and readable error handling. No test downloads a model or sends a real API key.

A successful automated test run proves client behavior against controlled responses. Live tutoring, study-generation quality, model capability, actual provider billing, and Keychain permission prompts must also be checked in the user's configured environment. See the main README for the recorded build/test results and any live-check limitations.

Recorded on 2026-09-23: the focused provider XCTest bundle ran 17 tests with zero failures. A read-only live probe returned HTTP 200 and 456 entries from OpenRouter's public catalog. Ollama at the fixed loopback address refused the connection. No live model inference, paid request, model download, or real credential write was performed by these checks.

ATS verification: Apple documents IP-address exceptions for macOS 14 and later in [NSExceptionDomains](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSExceptionDomains). An isolated app-bundle probe against a synthetic loopback HTTP listener on this development host succeeded both with no exception and with an explicit `127.0.0.1` exception. This is evidence for this host only; the app declares a narrow loopback HTTP exception for deployment compatibility. URLProtocol fixtures do not exercise ATS.
