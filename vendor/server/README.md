# Vendored Music Assistant server subset

This is a **read-only copy** of the patched Music Assistant server files that
this image uses, taken from the `Carunga/server` fork so everything can be read
in one place. The Docker build does **not** use this copy — it clones the fork at
a pinned revision (see the top-level README and `Dockerfile`).

Only the files the build actually copies are vendored:

- `music_assistant/providers/squeezelite/` — the patched Squeezelite provider
  (LMS-faithful sync, SqueezePlay menus, group-aware transport, power/mute).
- `music_assistant/controllers/cache/helpers.py` — the expired-empty-collection
  cache fix.

Source: `github.com/Carunga/server`, branch `better-squeeze-power-mute-controls`
(`52bfbb2b8e7e235b2b9e897e5a0bb96dd7f8913b`).

Music Assistant is licensed under Apache-2.0; these files retain that license.
