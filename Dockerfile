# Music Assistant 2.10.4 with the LMS-faithful Squeezebox/SlimProto sync fix.
FROM ghcr.io/music-assistant/server:2.10.4

# git is needed by uv to install the git+ requirement below.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/*

# Patched squeezelite provider: LMS-style sync + sync-group member mime fix.
COPY squeezelite/player.py /app/venv/lib/python3.14/site-packages/music_assistant/providers/squeezelite/player.py

# The provider manifest points the aioslimproto requirement at the patched
# fork (git+https://...@<sha>). MA installs it via uv on first provider load,
# because the provider imports aioslimproto.sync, which does not exist upstream.
COPY squeezelite/manifest.json /app/venv/lib/python3.14/site-packages/music_assistant/providers/squeezelite/manifest.json
