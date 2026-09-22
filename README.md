# MA-squeeze-harder

Music Assistant **2.10.4** with an **LMS-faithful SlimProto/Squeezebox sync fix**
plus a **SqueezePlay library/Home-Assistant menu** and **group-aware transport
controls**, packaged so it can be built and run locally. No container registry is
needed.

The original Music Assistant sync was an approximation. This build ports Lyrion
Music Server's server-side corrected sync into `aioslimproto` + the Squeezelite
provider.

## What is fixed / added

- player <-> server clock mapping via a min-latency jiffies estimator
- play points (`status_time` + apparent stream start) per player
- coordinated start at a common player-clock instant (`strm u`)
- steady-state drift correction (`skipAhead` / `pauseFor`)
- bugfix: correct mime type for sync-group member streams (this is what makes a
  Squeezebox Radio actually play inside a sync group)
- **group-aware transport controls**: pause/play/stop/next/previous on any
  sync-group member are applied to the whole group
- **SqueezePlay library menu** under *My Music*: **Playlists / Artists /
  Discover**, directly playable (Discover aggregates the recommendation rows of
  every provider that supports them)
- **Home Assistant scripts** at the **root** of the home menu (only shown when
  the Home Assistant plugin is configured), sorted alphabetically, with the Home
  Assistant logo
- the player's **custom name** is pushed to the device (renaming it in Music
  Assistant renames the Squeezebox)
- a **core cache fix** so an expired *empty* collection (e.g. a playlist that
  cached no tracks) is re-fetched instead of resolving to nothing
- the **SlimProto <-> Sendspin bridge** (experimental, see below)

Verified: wired squeezelite players hold ~0-2 ms; a wired squeezelite + a
Squeezebox Radio (WiFi) hold ~1 ms with occasional ~30-50 ms corrections.

## Experimental: Sendspin bridge

The Sendspin bridge is included but **off by default** and still **experimental**.
It registers each Squeezelite player as an external Sendspin client so it can take
part in a Sendspin group, and it now has the **audio path**: the group's PCM is
served to the device and started on the Sendspin timeline, with a drift monitor
that nudges it back with skip/pause, live per-track title/artwork, and a
**self-learning per-player lead**. It is not sample-accurate (SlimProto has no
client-side scheduling), so expect near-sync (tens of ms), not perfection.
Leave the `sendspin_bridge` provider option disabled unless you are experimenting.

## Home Assistant scripts menu

The *HA scripts* entry appears only when the **Home Assistant** plugin is
configured (Settings -> Providers -> add *Home Assistant* with your HA URL and a
long-lived access token). It lists `script.*` entities carrying the label
`squeeze` (falling back to a name/entity-id match when labels are unavailable);
selecting one runs the script.

## Requirements

- Docker with **Docker Compose** on a **Linux** host.
- **Host networking** is required; MA and all players must be on the same L2
  network (SlimProto uses UDP broadcast discovery on 3483; hardware Squeezebox
  players only support port 3483).
- **Only one** SlimProto server on the network: stop/disable any other Music
  Assistant or Lyrion/LMS instance while this runs.
- Internet access at **build time** (the Dockerfile clones the patched provider)
  and at the **first provider load** (see Notes), to fetch the patched
  `aioslimproto` fork from GitHub.

## Build & run

```sh
git clone <this repo>
cd MA-squeeze-harder
docker compose up -d --build
docker compose logs -f music-assistant
```

Then open the web UI at `http://<host-ip>:8095` and complete onboarding (create
an admin user).

The build clones the provider from GitHub and pins a specific commit; Docker
caches that layer, so add `--no-cache` if you change the pinned revision:

```sh
docker compose build --no-cache
```

## Add players

- Settings -> Player Providers -> add **Squeezelite**.
- Software players: point them at `<host-ip>:3483` (squeezelite `-s`).
- Hardware Squeezebox players: they discover the server via broadcast, so make
  sure no other MA/LMS is running on the network.

## Sync groups

Group players in the Music Assistant UI (or via the API
`players/cmd/set_members`). For the tightest result use a wired player as the
group leader.

## Ports (host networking)

- `3483` SlimProto control + discovery (TCP/UDP)
- `8095` web UI
- `8097` audio streams server (default; configurable in Settings -> System ->
  Streams if the port is taken)
- `9000` / `9090` legacy CLI (JSON-RPC / telnet)

## Notes / known limits

- Pinned snapshot: no updates, not an official release.
- On the **first provider load**, Music Assistant installs the patched
  `aioslimproto` from `github.com/Carunga/aioslimproto` (the provider manifest
  `requirements` entry, pinned to a commit) into the container venv with `uv`.
  This needs outbound HTTPS to GitHub at that moment; the image ships `git` for
  it, and the bundled upstream `aioslimproto` is removed so the install applies
  cleanly on the first load. The install lasts for the life of the container and
  is redone when the container is recreated.
- Wi-Fi players sync well but can show periodic ~30-50 ms corrections
  (inaudible on music). Wired players are tighter.
- Volume is intentionally **per-player** (not group); power follows Music
  Assistant's default behavior.
- Hardware remote/button transport (`BUTN`/`IR`) is not group-aware yet; the
  Squeezebox Radio's front panel uses the CLI and is covered.
- The Sendspin bridge is experimental and disabled by default (see above).
- Tested with squeezelite (wired, pCP) and a Squeezebox Radio (WiFi, FW 8.5.3).

## Source branches

Both forks are pinned in the image:

- `github.com/Carunga/aioslimproto` branch `better-squeeze-sync`
  (`7ca0729be24e4dc613a88415b1a076e5d9b1c537`) - LMS sync primitives + CLI fix.
  The provider manifest's `requirements` entry pins this commit.
- `github.com/Carunga/server` branch `feat/squeezelite-all`
  (`713192f810ab03d66186cda797df7e8d7a8aa261`) - the patched Squeezelite provider,
  the cache fix and the mime/transport/menu changes. This is also the revision
  cloned by the Dockerfile (override with `--build-arg SERVER_REV=...`).

Based on Music Assistant 2.10.4. Apache-2.0, same as upstream.
