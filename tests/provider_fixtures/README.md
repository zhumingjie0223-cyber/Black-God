# Provider transport fixtures

These are synthetic test bodies using the providers' documented wire formats, not recordings of authenticated API calls. They contain no credentials or real user prompts. Tests execute the production `NexusSSEParser` and `NexusClient`; URLProtocol intercepts all HTTP traffic in transport tests.

Sources verified on 2026-09-08:

- [Anthropic streaming event sequence, text deltas and in-stream errors](https://platform.claude.com/docs/en/build-with-claude/streaming)
- [OpenAI Chat Completions streaming schema and finish reasons](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events)
- [WHATWG SSE framing](https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation)

Run `bash tests/run_provider_transport_tests.sh` on macOS. This verifies protocol/error/cancellation behavior locally; live credentials, provider availability and entitlement checks remain separate release checks.
