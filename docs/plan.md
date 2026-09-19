# SlimProto sync fix — LMS-faithful plan

> **First working version:** see `CHANGES-first-working-version.md`
> (2026-09-19 21:11 CEST) — root cause, changed files, and L1/L2/L3 results.

## Goal & non-goals

- **Goal:** Make MA's Squeezelite/SlimProto sync groups start together and stay
  together by porting Lyrion Music Server's server-side sync algorithm as closely
  as possible.
- **Approach:** Put the reusable mechanism in `aioslimproto`; keep MA server
  changes to thin calls.
- **Non-goals:** Universal/cross-provider groups; non-SlimProto providers; changes
  to HA's slimproto integration (only additive library APIs).
- **Affected players:** squeezelite and SqueezePlay-based hardware (Radio/Touch).
  Other MA players untouched.

## LMS reference implementation (source of truth)

| Mechanism | LMS location |
|---|---|
| Player<->server clock map (`jiffiesEpoch`, min-latency estimator) | `Slim/Player/Player.pm::trackJiffiesEpoch`, `::jiffiesToTimestamp` |
| Play point (`statusTime`, `apparentStreamStartTime`) | `Slim/Player/Squeezebox2.pm::playPoint`; `Player.pm::publishPlayPoint` |
| Coordinated start | `Slim/Player/StreamingController.pm::_syncStart` + `Squeezebox2.pm::startAt` |
| Steady-state correction | `StreamingController.pm::_CheckSync` |
| Primitive frames | `Squeezebox.pm::stream` (`u`/`p`/`a`/`t`), `Squeezebox2.pm::pauseForInterval/skipAhead` |
| STAT ingestion | `Slim/Networking/Slimproto.pm::_stat_handler` |

Key facts:

- Clock offset is a **minimum-latency filter** over `(jiffies, STAT-arrival-time)`,
  *not* the `strm t` echo. LMS explicitly disabled the echo for latency:
  `# stop using this method to track latency - it is too unreliable`.
- Sync compares **apparent stream start times in server time**, than which
  nothing is more LMS-faithful.
- Reference player = most-behind player that **cannot** `skipAhead`, so hardware
  is never skipped.

## LMS constants to copy verbatim

```
CHECK_SYNC_INTERVAL        = 0.950
MIN_DEVIATION_ADJUST       = 0.010
MAX_DEVIATION_ADJUST       = 10.000
PLAYPOINT_RECENT_THRESHOLD = 3.0
PLAY_POINT_LIST_SIZE       = 8
MAX_STARTTIME_VARIATION    = 0.015
JIFFIES_OFFSET_TRACKING_LIST_SIZE = 50
JIFFIES_OFFSET_TRACKING_LIST_MIN  = 10
JIFFIES_EPOCH_MIN_ADJUST   = 0.001
JIFFIES_EPOCH_MAX_ADJUST   = 0.005
PACKET_LATENCY             = 0.002
DEFAULT_MIN_SYNC_ADJUST    = 0.030   # Player.pm default (SB2 uses 0.010)
SYNC_START_DELAY           = 0.200
```

## Changes — aioslimproto (all additive)

**`const.py`**

- Add the constants above.

**`client.py`**

1. New per-client state: `jiffies_epoch`, `jiffies_offset_list`, `status_time`,
   `apparent_stream_start_time`, `start_delay`, `play_delay`, `min_sync_adjust`,
   `maintain_sync`, `packet_latency`, `_last_stat_at`.
2. `track_jiffies_epoch(jiffies, server_time)` — direct port of
   `Player.pm::trackJiffiesEpoch` (min-latency epoch, 50-slot list, 1–5 ms nudges,
   wraparound guard).
3. `jiffies_to_timestamp(jiffies)` — `epoch + jiffies/1000 - packet_latency`.
4. `play_point` property — `status_time = jiffies_to_timestamp(jiffies)`;
   `apparent = status_time - elapsed_ms/1000` (from raw STAt values, not the
   extrapolated property).
5. `start_at(server_time)` — `strm u` with
   `interval = int((server_time - jiffies_epoch) * 1000)` (port of
   `Squeezebox2::startAt`).
6. Verify/keep `pause_for(ms)` (`strm p`) and `skip_over(ms)` (`strm a`) — already
   match LMS.
7. `request_status()` — send `strm t` (matches LMS `requestStatus`).
8. In `_process_stat_stmt`: call `track_jiffies_epoch(self._jiffies, now)` and
   refresh the play point. (Optionally extract jiffies/elapsed from every `STAT`,
   as LMS does.)
9. Keep the existing `elapsed_milliseconds`/`jiffies` properties unchanged (HA
   compatibility); sync uses only the new APIs.

**`sync.py` (new module)**

- `check_sync(clients, now)` — port of `_CheckSync` (recency gate, sort by
  apparent start desc, reference selection, delta gates, `skip_over`/`pause_for`,
  `next_check` throttling).
- `sync_start(clients, now)` — port of `_syncStart`
  (`max(start_delay+play_delay)` + `SYNC_START_DELAY`, per-player `start_at`).
- Optional averaging via `publish_play_point` for old players
  (`needs_weighted_play_point`); off for our targets.

**Tests**

- Synthetic STAT streams with known latency/drift -> epoch converges.
- `check_sync` emits expected `a`/`p` frames with correct deltas.
- `sync_start` computes equal real-world start instants across two clients.

## Changes — MA `providers/squeezelite` (minimal)

**`player.py`**

1. `_handle_buffer_ready`: once all members are `BUFFER_READY`, replace
   `pause_and_unpause(...)` with `sync_start(self._get_sync_clients())`.
2. `_handle_sync`: replace the whole average-diff body with
   `check_sync(self._get_sync_clients())` (keep the `synced_to`/playing guards).
3. Delete `pause_and_unpause`, `_sync_playpoints`, `_do_not_resync_before`, and
   the old `_handle_sync` math.
4. In `_handle_play_url_for_slimplayer`, remove
   `if is_group_playback: await slimplayer.pause()` (LMS relies on `autostart=0` +
   wait-to-sync + `start_at`).
5. Map the existing per-player **"Audio synchronization delay correction"
   (`CONF_SYNC_ADJUST`)** onto `client.play_delay` (LMS `playDelay`). Keep
   `_handle_player_heartbeat` for UI elapsed only.
6. Retire `get_corrected_elapsed_milliseconds` (superseded by play points).

**`constants.py`**

- Remove the MA-local sync constants now living in aioslimproto.

**`provider.py`**

- On player config change/update, push `CONF_SYNC_ADJUST` into
  `client.play_delay`.

**`manifest.json`**

- Bump `aioslimproto` to the release containing the new APIs.

## Deliberate deviations from LMS (with justification)

1. **Group orchestration lives in `aioslimproto/sync.py`, not a
   StreamingController.** MA's group model is provider-level; a function taking a
   client list keeps the MA diff tiny and lets HA reuse it.
2. **Track jiffies on STMt (initially), not every STAT.** Minimal parsing change;
   STMt is the periodic carrier. First thing to extend if play points go stale.
3. **Only `playDelay` exposed as config** (reusing `CONF_SYNC_ADJUST`); all other
   LMS knobs use compiled defaults. Extend later.
4. **No weighted play points for SB1/SliMP3** initially (out of target device
   set).
5. **Keep MA's `MultiClientStream`**; LMS's chunk fan-out is functionally
   equivalent for our purposes.
6. **Do not use the `strm t` echo for latency** — matches LMS.

## Risks & mitigations

- **WiiM early start:** removing the pause hack may regress WiiM. LMS assumes
  `autostart=0` + wait-to-sync. Test; if needed, add a provider-only quirk (never
  in the library).
- **STAt cadence too slow:** play points stale -> `check_sync` bails. Mitigate by
  requesting status more often and/or parsing jiffies from all STATs.
- **Old hardware:** may need weighted play points / tuned `min_sync_adjust`.
- **`CONF_SYNC_ADJUST` sign:** align to LMS `playDelay` semantics and verify
  empirically.

## Validation

- Phase 0: LMS-vs-MA pcap comparison + objective two-endpoint offset measurement.
- Unit tests in aioslimproto and MA.
- Hardware matrix: 2x squeezelite, Radio+squeezelite, 2x Radios; wired/Wi-Fi;
  start, track change, seek, pause/resume.

## Rollout

1. aioslimproto PR (additive) + release.
2. MA provider PR (bump pin + thin calls).
3. No core/model changes; other providers and HA unaffected.

## Open questions

1. Put `check_sync`/`sync_start` in `aioslimproto` (recommended) or in MA?
2. Parse jiffies from every STAT now, or STMt-only first?
3. Expose `minSyncAdjust`/`startDelay` per player, or hardcode LMS defaults
   initially?

## Base versions (decided)

- MA server: **stable 2.10.4** (`ghcr.io/music-assistant/server:2.10.4`).
- aioslimproto: **3.2.2** (the pin in stable's squeezelite manifest).
- Rationale: provider code is identical between stable 2.10.4 and beta
  2.11.0b2; beta actually pins the older aioslimproto 3.2.0. The 3.2.0 -> 3.2.2
  delta is startup/handshake correctness (autostart `2` for group playback,
  inline STAT ordering, `cont` payload, per-stream thresholds) that the
  coordinated-start path depends on.

## Environment / L1

- Dev host: `dev-host`, Ubuntu 22.04, Docker 29.x, `<lan-iface> <host-ip>/24`.
  All players/HA are on `<lan-subnet>` (same broadcast domain).
- Disk: need >= ~8 GB free on `/` (checked: 51 GB free).
- Host Python is 3.10 (too old) -> run everything in containers.
- L1 is **isolated** on a dedicated Docker bridge network: no interference with
  the HA addon or the LAN, and `tc netem` shaping is possible. L2 later switches
  `ma-dev` to `network_mode: host` for real players.
- aioslimproto is shadowed in the MA container via `PYTHONPATH=/opt/patched`
  (precedence over the pinned install); the patched provider dir is bind-mounted
  over the in-image provider directory.
- Components: `ma-dev` (official image), `sl1`/`sl2` (Debian + squeezelite,
  null ALSA), sidecar `tcpdump` on the L1 network.

### Layout

```
/home/seb/dev/lms-ma/
  plan.md
  aioslimproto/            # clone @3.2.2 (patched)
  ma-server/               # sparse checkout @2.10.4 (provider overlay)
  ma-dev/
    docker-compose.yml
    squeezelite/Dockerfile
  data/                    # MA /data
  captures/                # pcap + logs + CSVs
```

## Results (L1 + L2)

### aioslimproto changes (base 3.2.2)

- `const.py`: LMS constants (check interval, deviation gates, jiffies tracking,
  packet latency, sync start delay) - copied verbatim.
- `client.py`: added `track_jiffies_epoch()` (min-latency clock estimator),
  `jiffies_to_timestamp()`, `play_point` (status_time + apparent stream start),
  `start_at()` (strm-u at a common server time), `request_status()`, and
  per-player sync prefs (`start_delay`/`play_delay`/`min_sync_adjust`/
  `maintain_sync`/`packet_latency`). Jiffies epoch is tracked on every STMt.
- `sync.py` (new): `SyncGroup.start()` and `SyncGroup.check()` - ports of
  `StreamingController::_syncStart` and `::_CheckSync`.

### MA provider changes (stable 2.10.4, `squeezelite/player.py`, net -95 lines)

- Import `SyncGroup`; hold `self._sync_group`.
- `on_config_updated()`: map `CONF_SYNC_ADJUST` -> `client.play_delay`.
- `_handle_play_url_for_slimplayer()`: removed the WiiM `pause()` hack and the
  now-unused `is_group_playback` parameter (LMS relies on autostart=0 +
  buffer-ready + coordinated start).
- `_handle_buffer_ready()`: after all members are buffer-ready, call
  `self._sync_group.start(self._get_sync_clients())`.
- `_handle_player_heartbeat()`: trigger sync on the group leader
  (`group_members`), not per synced child.
- `_handle_sync()`: thin wrapper over `self._sync_group.check(...)`.
- Removed the old average-elapsed-diff algorithm, `pause_and_unpause()`,
  `SyncPlayPoint`/`_sync_playpoints`, and now-unused imports.

### L1 (isolated bridge, 2x squeezelite, PulseAudio null sink)

- Baseline (unsynced) offset: **~63 ms**.
- Coordinated start: **~2 ms**.
- Injected +150 ms skip -> detected **153 ms** delta -> `skipAhead 153ms` ->
  back to **<2 ms** within ~2 s.
- STAt cadence observed: ~1 s (enough for the 3 s play-point recency gate).

### L2 (real MA 2.10.4 + patched provider + patched library)

- Both squeezelite clients registered; Filesystem provider scanned `/media`
  (`tone` added).
- `players/cmd/set_members` grouped MA-A (leader) + MA-B; playback via
  `player_queues/play_media`.
- Log: both players `startAt in 200.0ms`; steady-state play points **3-5 ms**,
  no resync corrections.

### Reproduction

```
# L1 harness
docker compose -f ma-dev/docker-compose.yml up -d
# perturb (from inside slim-dev):
python -c "import urllib.request as u;print(u.urlopen('http://localhost:8000/control/skip?player=<mac-test-1>&ms=150').read())"

# L2 MA stack
docker compose -f ma-dev/docker-compose.ma.yml up -d
# admin token: POST /setup ; ws auth command ; then:
#   players/cmd/set_members {"target_player":"<leader>","player_ids_to_add":["<child>"]}
#   player_queues/play_media {"queue_id":"<leader>","media":"library://track/1"}
```

### Notes / next

- `ma-dev` currently runs `LOG_LEVEL=verbose` to surface `aioslimproto.*` DEBUG
  (play points / startAt). Switch back to `debug` to reduce log volume.
- Open: regression tests for `sync.py` + clock mapping; then upstream PRs
  (aioslimproto first, then MA provider - both target `dev`; base is stable).
- Known caveat: dropping the WiiM pause hack may regress WiiM; a provider-only
  quirk can be re-added if needed (never in the library).

## Regression tests (added)

`aioslimproto/tests/sync_test.py` - 54 passed, 2 xfailed; `sync.py` 98% covered
(only the unreachable defensive `if not play_points` guard remains):

- Jiffies epoch: converges to the minimum offset despite latency; follows slow
  clock drift with bounded mapping error.
- Play point: status/apparent-start math; `None` before playback starts.
- `SyncGroup.start`: single-player no-op; all players align to one server instant
  (max delay + 200 ms headroom); per-player `strm u` interval verified.
- `SyncGroup.check`: stale play-point bail; below-min / above-max gates;
  skip-ahead for the lagging player; pause for the player ahead of a
  non-skippable reference; throttling; debug logging.

Lint/format clean (`ruff check` + `ruff format --check`) on all changed files.

Run the suite:

```
docker run --rm -v /home/seb/dev/lms-ma/aioslimproto:/src -w /src python:3.13-slim \
  sh -c "pip install -q pytest pytest-asyncio pytest-cov aiohttp pillow && python -m pytest tests/"
```

## L3 hardware findings (real players)

> **TEST CONSTRAINT: never play anything on Wired-B
> (`<mac-wohnzimmer>`).** All playback tests use only Wired-A
> (`<mac-keller>`) and, once its stream issue is fixed, the Squeezebox
> Radio (`<mac-radio>`). It was only used once, to prove the algorithm on
> a second wired squeezelite, and must not be included again.

Dev MA on host networking at `<host-ip>`; UI :8095; streams server 8098
(8097 collided with Jellyfin).

### Two wired squeezelite (Wired-A + Wired-B) - PASS

- Both advertise `AccuratePlayPoints`.
- Native sync group via `set_members`; coordinated start ~200 ms.
- Steady state: play points identical, **0 ms difference**, sustained (no resync).
- Conclusion: the LMS-ported algorithm syncs real squeezelite hardware correctly.

### Squeezebox Radio (WiFi, FW 8.5.3, `Model=baby`) - FIXED

- Advertises `AccuratePlayPoints`.
- Solo playback through MA works.
- In a native sync group the Radio connected to the multi-client stream
  (`STMc` -> `codc` -> `cont`) but then immediately sent `STMd` with
  `output_buffer_fullness=0`, `elapsed=0`; it never decoded the group stream.

**Root cause:** the provider derived the `strm s` mime type for sync-group
member URLs by string-splitting the URL (which has no file extension),
producing garbage like `audio/103:8098/slimproto/multi`. aioslimproto then sent
a wrong codec, and the Radio's decoder failed. Squeezelite tolerated it; the
Radio did not.

**Fix:** pass the member codec's mime explicitly
(`mime_type=get_mime_type(member_codec)`) from the sync-group `play_media` path;
`_handle_play_url_for_slimplayer` now accepts an optional `mime_type`.

**Result:** Radio + wired squeezelite (Wired-A) now sync at ~1 ms
(play points `+0ms` / `-1ms`, sustained). This is a genuine provider bugfix and
should be kept alongside the sync work.

### Service state

- `ma-dev` runs `LOG_LEVEL=verbose` (needed for `aioslimproto.sync` DEBUG and
  HELO capabilities); switch back to `debug` to reduce log volume.
- Temporary debug logs currently in `client.py` (`STAT`, `STATRAW`, `STAtt`) -
  remove before upstreaming.

## Follow-up A — Group-aware playback controls (pause / play / stop / power / volume)

**Problem.** Transport controls on a sync-group member only affect that member.
The Radio sends them over the legacy CLI (`['pause','1']`, `['mode','play']`,
`['button','...']`). MA's provider builds `SlimServer(...)` **without a
`cli_command_handler`**, so `aioslimproto`'s built-in handlers call
`player.pause()/play()/...` on the single `SlimClient`, bypassing MA's
group redirect (`_get_player_with_redirect()`); hardware `BUTN`/`IR`
`PAUSE`/`PLAY`/`POWER`/`VOLUME_DOWN` are likewise intercepted in the library.

**Goal.** A playback control on any sync-group member applies to the whole group
(via the sync leader / active group), matching MA's own redirect semantics.

**Approach.**
- Provider: pass a `cli_command_handler` to `SlimServer`; map
  `pause`, `play`, `stop`, `mode <play|pause|stop>`, `power`, and
  `button <play|pause|power|volup|voldown|jump_fwd>` to MA player commands
  (`mass.players.cmd_*`), which already redirect a synced member to the leader.
  Raise `NotImplementedError` for anything else so the default CLI handling runs.
- Library (`aioslimproto`): stop acting locally on `PAUSE`/`PLAY`/`POWER`/
  `VOLUME_DOWN` in `_process_butn`/`_process_ir`; forward them (or add an
  opt-in hook) so the consumer applies group semantics. Keep it additive so
  HA's `slimproto` integration is unaffected.
- Volume on a member applies to the group (group volume).

**Success.** pause/play/stop/power/volume on a synced member affect the whole
group; solo players unchanged; no regressions in HA's slimproto integration.

**Files.** `music_assistant/providers/squeezelite/{provider,player}.py`;
`aioslimproto/{client,cli}.py`.

## Follow-up B — Expose the other (non-transport) buttons to Home Assistant

**Goal.** Every discrete button press that is not a playback control (the
Radio's 6 preset buttons and other front-panel buttons; hardware standalone
buttons) is surfaced to Home Assistant so users can build their own automations.

**Decisions.**
- Exposure mechanism: a generic **`music_assistant` event** keyed by
  player + button (no per-button entities).
- Scope: **discrete buttons only**; knob and IR remote codes are excluded.
- Transport buttons (play/pause/stop/power/volume) are handled by Follow-up A
  and are **not** additionally emitted as events.

**Approach.**
- Provider/library: emit all discrete button events as structured events
  (SqueezePlay CLI `button <name>` incl. `.single`/`.hold`/`.double`; hardware
  numeric `ButtonCode`), and remove the current `if not queue: return`
  early-out so events also fire while idle.
- Publish to HA via a generic `music_assistant` event (player + button name),
  reusing MA's Home Assistant plugin plumbing.
- Capture the exact button names empirically first (press each Radio button
  while capturing CLI requests) to build the name mapping.

**Depends on:** A (do A first; B reuses the same CLI/button layer).
