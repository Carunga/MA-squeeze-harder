# MA-squeeze-harder

Music Assistant **2.10.4** with an **LMS-faithful SlimProto/Squeezebox sync fix**,
packaged so it can be built and run locally. No container registry needed.

## What is fixed

The original MA sync was an approximation. This build ports Lyrion Music Server's
server-side corrected sync into `aioslimproto` + the Squeezelite provider:

- player &lt;-&gt; server clock mapping via a min-latency jiffies estimator
- play points (`status_time` + apparent stream start) per player
- coordinated start at a common player-clock instant (`strm u`)
- steady-state drift correction (`skipAhead` / `pauseFor`)
- bugfix: correct mime type for sync-group member streams (this is what makes
  e.g. a Squeezebox Radio actually play inside a sync group)

Verified: wired squeezelite players hold ~0-2 ms; a wired squeezelite + a
Squeezebox Radio (WiFi) hold ~1 ms with occasional ~30-50 ms corrections.

## Requirements

- Docker + Docker Compose on a **Linux** host
- **host networking** (required for SlimProto discovery/streaming); MA and all
  players on the same L2 subnet
- **only one** MA/SlimProto server per network
- outbound HTTPS to `github.com` on first start (see Notes)

## Build and run

```bash
git clone <this repo>
cd MA-squeeze-harder
docker compose up -d --build
```

Then open `http://<host-ip>:8095` and complete onboarding (create an admin user).

## Add players

- Settings -> Player Providers -> add **Squeezelite**.
  On adding the provider, MA installs the patched `aioslimproto` from the fork
  listed in the provider manifest (this is the `git+https://...` requirement).
- Software players: point them at `<host-ip>:3483` (squeezelite `-s`).
- Hardware Squeezebox players: they discover the server via broadcast, so make
  sure no other MA/LMS is running on the network.

## Test media

Add a music provider (e.g. **Filesystem (local disk)** on `/media`, or Tidal/Spotify).
A click/impulse track is handy for hearing sync quality.

## Sync groups

Group players in the MA UI (or via the API `players/cmd/set_members`). For the
tightest result use a wired player as the group leader.

## Notes / caveats

- On first provider load MA fetches the patched `aioslimproto` from
  `github.com/Carunga/aioslimproto` via the manifest `requirements` entry
  (`aioslimproto @ git+https://...@<sha>`), installed with `uv`. This needs
  outbound HTTPS to GitHub at that moment; it is cached in the `/data` volume's
  environment afterwards.
- The stream server defaults to TCP **8097**; if that port is taken, change it in
  Settings -> System -> Streams.
- Wi-Fi players sync well but can show periodic ~30-50 ms corrections
  (inaudible on music). Wired players are tighter.
- Optional: the Home Assistant **Music Assistant** integration can point at this
  server (`http://<host-ip>:8095`); when MA does not run as a HA app, log in with
  an **admin** account.
- Tested with squeezelite (wired, pCP) and a Squeezebox Radio (WiFi, FW 8.5.3).

## Patches / source

- Patched library: `github.com/Carunga/aioslimproto` branch `better-squeeze-sync`
  (see `patches/aioslimproto/`). The provider manifest pins its commit.
- Patched provider: `patches/server/` (3 commits: mime fix, sync integration,
  requirement).

Based on Music Assistant 2.10.4. Apache-2.0, same as upstream.
