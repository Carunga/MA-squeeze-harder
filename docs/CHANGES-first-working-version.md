# lms-ma — first working version

- **Date/time:** 2026-09-19 21:11:31 CEST (2026-09-19T19:11:31Z)
- **Base:** Music Assistant stable **2.10.4** + **aioslimproto 3.2.2**
- **Status:** working; verified on real hardware (wired squeezelite + Squeezebox Radio)

## Original cause of the problem

MA's SlimProto sync was an ad-hoc approximation, not LMS's server-side corrected
sync:

1. **No player<->server clock mapping** in `aioslimproto`: `elapsed`/`jiffies`
   were extrapolated from the server wall clock between 5s `STAt` heartbeats, so
   values were noisy and not comparable across players.
2. **Provider steady-state corrector** averaged extrapolated elapsed diffs
   (8 playpoints, 8 ms floor, 5 s lockout) with no reference-player selection
   and no buffer/latency accounting.
3. **Start path** used `pause()` + a fixed 200 ms `pause_and_unpause()` hack
   instead of scheduling a common player-clock start instant (`strm u`).

Result: players started at different times and drift could not be reliably
corrected/tightened.

A second, independent bug affected hardware: the sync-group member URL's mime
was guessed by string-splitting the URL (which has no extension), yielding
garbage like `audio/103:8098/slimproto/multi`. Squeezelite tolerated the wrong
codec; the Squeezebox Radio's decoder did not, so it never played the group
stream.

## Changes in this first working version

### aioslimproto (base 3.2.2)

- `const.py` (+32): LMS sync constants copied verbatim (check interval,
  deviation gates, jiffies tracking, packet latency, sync start delay).
- `client.py` (+124, includes temporary debug logs):
  - `track_jiffies_epoch()` — min-latency estimator mapping player jiffies to
    server time (port of `Player::trackJiffiesEpoch`).
  - `jiffies_to_timestamp()`, `play_point` (status time + apparent stream start),
    `start_at()` (common-instant `strm u`), `request_status()`.
  - per-player sync knobs: `start_delay`, `play_delay`, `min_sync_adjust`,
    `maintain_sync`, `packet_latency`.
  - jiffies epoch tracked on every `STMt`.
- `sync.py` (new): `SyncGroup.start()` / `.check()` — 1:1 ports of LMS
  `StreamingController::_syncStart` / `::_CheckSync`.
- `tests/sync_test.py` (new): 54 tests, `sync.py` 98% covered; ruff clean.

### MA `providers/squeezelite/player.py` (+25 / -114, net simplification)

- Holds a `SyncGroup`; maps the existing **"Audio synchronization delay
  correction"** (`CONF_SYNC_ADJUST`) to `client.play_delay`.
- `_handle_buffer_ready()` -> `sync_group.start(get_sync_clients())`.
- Heartbeat triggers sync on the **leader**; `_handle_sync()` ->
  `sync_group.check(...)`.
- Removed old average-diff algorithm, `pause_and_unpause()`, the WiiM pause hack
  + `is_group_playback`, `SyncPlayPoint` and unused imports.

### Mime fix (required for Squeezebox Radio)

- `_handle_play_url_for_slimplayer(..., mime_type=None)`; sync-group path passes
  `get_mime_type(member_codec)` instead of deriving it from the URL.

### Environment / config only (not code)

- Seeded dev `/data` with `squeezelite` + `filesystem_local` providers.
- Streams server port moved `8097 -> 8098` (8097 owned by Jellyfin).
- MA run on host networking for hardware testing (`<host-ip>`, UI :8095).

## Verification

- Virtual (L1): coordinated start ~2 ms; injected 150 ms drift corrected in ~2 s.
- Virtual via MA (L2): 3-5 ms.
- Real hardware (L3): Wired-A (wired squeezelite-pCP) + Wired-B **0 ms**;
  Wired-A + Squeezebox Radio (WiFi, FW 8.5.3) **~1 ms** after the mime fix.
  Bounded 30-50 ms `skipAhead` corrections occasionally (inaudible), consistent
  with WiFi clock drift.

## Notes / TODO before upstreaming

- Remove temporary debug logs in `client.py` (`STAT`, `STATRAW`, `STAtt`).
- PRs target `dev`; the mime change is a standalone bugfix and a
  `backport-to-stable` candidate.
- **Test constraint:** never play on Wired-B
  (`<mac-wohnzimmer>`).
