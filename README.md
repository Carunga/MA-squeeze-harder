# MA-squeeze-harder

Music Assistant **2.10.4** with an **LMS-faithful SlimProto/Squeezebox sync fix**
plus a **SqueezePlay library/Home-Assistant menu** and **group-aware transport
controls**, packaged so it can be built and run locally. No container registry is
needed.

The original Music Assistant sync was an approximation. This build ports Lyrion
Music Server's server-side corrected sync into `aioslimproto` + the Squeezelite
provider.

## Repository layout

Everything the image is built from is reachable from this repo:

- `aioslimproto/` — **git submodule** of
  [`github.com/Carunga/aioslimproto`](https://github.com/Carunga/aioslimproto),
  branch `better-squeeze-power-mute-controls` (the LMS sync primitives, CLI/menu
  fixes, and the power/mute/wake fixes).
- `vendor/server/` — a **read-only copy** of the patched Music Assistant server
  files from
  [`github.com/Carunga/server`](https://github.com/Carunga/server), branch
  `better-squeeze-power-mute-controls` (the patched Squeezelite provider + the
  cache fix). Only the files the build uses are vendored.
- `Dockerfile` / `docker-compose.yml` — the build.

Clone with the submodule:

```sh
git clone --recurse-submodules <this repo>
```

If you already cloned without it:

```sh
git submodule update --init --recursive
```

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
git clone --recurse-submodules <this repo>
cd MA-squeeze-harder
docker compose up -d --build
docker compose logs -f music-assistant
```

The `aioslimproto/` submodule is included for reading/development; the image
build itself pins the exact revisions it ships (see *Source* below), so the
submodule checkout does not change what gets built.

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

## Source

### Development branches (mirrored by the submodule / vendored copy)

- `github.com/Carunga/aioslimproto` branch `better-squeeze-power-mute-controls`
  (`04bd13aceca2bb8a9b54e68331df411081625721`) - LMS sync primitives, the
  CLI/menu fixes, mute via zero gain, and the power/wake fixes (status +
  home-menu push on power changes, LMS-aligned `aude`).
- `github.com/Carunga/server` branch `better-squeeze-power-mute-controls`
  (`52bfbb2b8e7e235b2b9e897e5a0bb96dd7f8913b`) - the patched Squeezelite
  provider (sync, SqueezePlay menus, group-aware transport, native mute, the
  `playerpower` home entry) plus the expired-empty-collection cache fix.

### Image build pins (what the Docker image actually ships)

For reproducibility the image does **not** build the development branches; it
pins tested revisions:

- `github.com/Carunga/server` at
  `7740615c23e265dd9be05ea589fa1e1d9c90b836` — the `SERVER_REV` build arg in
  `Dockerfile` (override with `--build-arg SERVER_REV=...`).
- `github.com/Carunga/aioslimproto` at the commit pinned by that revision's
  provider `requirements` entry (installed into the venv on first provider load).

Based on Music Assistant 2.10.4. Apache-2.0, same as upstream.
