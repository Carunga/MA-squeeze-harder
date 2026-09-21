# Music Assistant 2.10.4 with the LMS-faithful Squeezebox/SlimProto sync fix,
# the SqueezePlay library/HA-scripts menus and group-aware transport controls.
FROM ghcr.io/music-assistant/server:2.10.4

# git is needed twice:
#  - at build time, to fetch the patched provider from the fork below;
#  - at the first provider load, when Music Assistant installs the patched
#    aioslimproto from its fork via `uv pip install git+https://...@<sha>`
#    (the requirement comes from the provider manifest).
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Tested revisions (see README). Override with --build-arg to try others.
ARG SERVER_REPO=https://github.com/Carunga/server
ARG SERVER_REV=918781da7a7226c30d3a3083a2d751548b20c8ec

# Remove the bundled upstream aioslimproto. The patched provider imports
# aioslimproto.sync, which does not exist upstream; that import fails on the
# first load, which makes Music Assistant install *all* of the provider's
# requirements - including the git+ fork pinned in the manifest. If the bundled
# copy stayed installed, its `const` submodule would already be cached and the
# retry after the install would not pick up the patched constants.
RUN /app/venv/bin/uv pip uninstall aioslimproto

# Fetch the patched provider and the core cache fix at the pinned revision.
RUN git clone --filter=blob:none --no-checkout "${SERVER_REPO}" /tmp/server \
 && git -C /tmp/server fetch --depth 1 origin "${SERVER_REV}" \
 && git -C /tmp/server checkout --detach FETCH_HEAD

# The whole provider directory (player.py, provider.py, library_menu.py,
# cli_commands.py, sendspin_bridge.py, ha_logo.png, strings.json, manifest.json,
# ...) plus helpers.py, where the expired-empty-collection cache fix lives.
# The provider manifest already pins the aioslimproto fork, so no edit is needed.
RUN cp -r /tmp/server/music_assistant/providers/squeezelite/. \
        /app/venv/lib/python3.14/site-packages/music_assistant/providers/squeezelite/ \
 && cp /tmp/server/music_assistant/controllers/cache/helpers.py \
        /app/venv/lib/python3.14/site-packages/music_assistant/controllers/cache/helpers.py \
 && rm -rf /tmp/server
