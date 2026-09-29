# Sidelauder

A Slack-style rail for macOS that switches between the Claude Desktop profiles
created by [claude-multiprofile](https://github.com/jmdarre-v/claude-multiprofile).

**Unofficial. Sidelauder is an independent open-source project. It is not
affiliated with, endorsed by, or partnered with Anthropic, and it is not
affiliated with claude-multiprofile or its author.** "Claude" and "Anthropic"
are names of Anthropic, PBC. They appear here only to say what this software
works with.

## Status

Pre-alpha. There is no app yet and nothing to install. The repository holds:

- [docs/spec.md](docs/spec.md), version 0.3 (draft): the plan the app will be
  built against, revised after the first spikes.
- [docs/spikes/](docs/spikes/): the results of those spikes (M0), with the
  harnesses that produced them in [spikes/](spikes/).
- The interim adapter that reads claude-multiprofile's profiles until it has a
  machine-readable output of its own:
  [App/Sidelauder/upstream-status.mjs](App/Sidelauder/upstream-status.mjs),
  with its tests in [Tests/Adapter/](Tests/Adapter/).

## Principles

- It builds on claude-multiprofile and does not duplicate it. Profile
  knowledge is read from that tool, never re-implemented.
- It never reads or writes Claude's data, credentials or Keychain entries.
- It uses public macOS APIs only, and adds no network access.

## Licence

MIT. See [LICENSE](LICENSE).
