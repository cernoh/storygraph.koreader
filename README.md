# StoryGraph KOReader Plugin

Sync reading progress and status from KOReader to StoryGraph.

## Status

Design complete. Implementation not started.

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

## Configuration

Credentials stored in plugin config file (plaintext). Configure via popup window on first use.

## Documentation

- [agents.md](agents.md) — agent context (start here if you're an AI)
- [API.md](API.md) — reverse-engineered StoryGraph endpoints
- [DESIGN.md](DESIGN.md) — design decisions and rationale

## License

TBD
