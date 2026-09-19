# Music Assistant 2.10.4 with the LMS-faithful Squeezebox/SlimProto sync fix.
FROM ghcr.io/music-assistant/server:2.10.4

# Patched aioslimproto, shadowed via PYTHONPATH. MA skips its "aioslimproto==3.2.2"
# requirement check because this package reports version 0.0.0 (dev/editable).
COPY aioslimproto/ /opt/patched/aioslimproto/
ENV PYTHONPATH=/opt/patched

# Patched squeezelite provider: LMS-style sync + sync-group member mime fix.
COPY squeezelite/player.py /app/venv/lib/python3.14/site-packages/music_assistant/providers/squeezelite/player.py
