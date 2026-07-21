# StoryGraph KOReader Plugin

Sync reading progress and status from KOReader to StoryGraph.

## Status

Implemented and tested. Ready for use on KOReader devices.

## What It Does

- Tracks reading progress (percentage) on StoryGraph when you read on KOReader
- Updates reading status: "currently reading" on book open, "finished" at 95%+
- Maps books via ISBN; falls back to title+author search with user selection
- Batches syncs on book close; retries failed syncs on next action
- Minimal UI: popup window for book selection and logs

## How It Works

StoryGraph has no public API. This plugin reverse-engineers undocumented HTTP endpoints (see [API.md](API.md)).

```
Book open/close → Plugin queues action → Batched sync on close → HTTP POST to StoryGraph
```

## Requirements

- KOReader (any device: Kindle, Kobo, PocketBook, Android)
- StoryGraph account
- Internet connection (syncs when online, queues when offline)

## Installation

Download the latest release from [Releases](../../releases) and extract `storygraph.koplugin/` into your KOReader `plugins/` directory.

## Configuration

Credentials stored in plugin config file (plaintext). Configure via popup window on first use.

## Development

### Nix flake

```bash
nix develop       # enter dev shell
dev               # launch KOReader with plugin loaded
run-tests         # run test suite (unit, integration, or all)
check-lint        # run luacheck
check-types       # run lua-language-server diagnostics
```

### Test suite

86 tests covering unit and integration scenarios:

- **Unit tests** — mocked KOReader dependencies, fast isolated tests
- **Integration tests** — real KOReader modules, validates plugin flow and queue persistence
- **HttpInspector** — visual test harness in `web/index.html` for API debugging

### CI

- API health check runs on tags and manual dispatch
- Release workflow bundles plugin into zip on `v*` tags

## Documentation

- [agents.md](agents.md) — agent context (start here if you're an AI)
- [API.md](API.md) — reverse-engineered StoryGraph endpoints
- [DESIGN.md](DESIGN.md) — design decisions and rationale

## License

TBD
