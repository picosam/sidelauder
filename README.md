# Sidelauder

A Slack-style rail for macOS that switches between the Claude Desktop profiles
created by [claude-multiprofile](https://github.com/jmdarre-v/claude-multiprofile).

**Unofficial. Sidelauder is an independent open-source project. It is not
affiliated with, endorsed by, or partnered with Anthropic, and it is not
affiliated with claude-multiprofile or its author.** "Claude" and "Anthropic"
are names of Anthropic, PBC. They appear here only to say what this software
works with.

## Status

Pre-alpha. There is no code yet and nothing to install. The repository holds
the specification, which is the plan the code will be built against:

- [docs/spec.md](docs/spec.md), version 0.2. The spec still carries the
  working name "Switchyard" in its text; that name was replaced by Sidelauder
  before this repository was created, and the next revision (v0.3, after the
  first spikes) renames it throughout.

## Principles

- It builds on claude-multiprofile and does not duplicate it. Profile
  knowledge is read from that tool, never re-implemented.
- It never reads or writes Claude's data, credentials or Keychain entries.
- It uses public macOS APIs only, and adds no network access.

## Licence

MIT. See [LICENSE](LICENSE).
