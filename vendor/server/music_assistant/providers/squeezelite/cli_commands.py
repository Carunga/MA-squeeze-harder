"""Mapping of legacy SlimProto CLI transport commands to Music Assistant actions."""

from __future__ import annotations

from typing import Any


def map_transport_command(command: str, args: list[Any]) -> str | None:
    """
    Map a legacy SlimProto CLI transport command to a Music Assistant action.

    Only transport commands are mapped; everything else returns None so the caller
    can fall back to aioslimproto's own CLI handling.

    :param command: The CLI command name (e.g. ``pause``, ``mode``, ``button``).
    :param args: The CLI command arguments.
    """
    arg = args[0] if args else None
    if command == "play":
        return "play"
    if command == "stop":
        return "stop"
    if command == "pause":
        # LMS semantics: 1 = pause, 0 = resume, no argument = toggle
        if arg in (1, "1"):
            return "pause"
        if arg in (0, "0"):
            return "play"
        return "play_pause"
    if command == "mode":
        if arg in ("play", "pause", "stop"):
            return arg
        return None
    if command == "button":
        if arg in ("play", "pause"):
            return arg
        if arg in ("jump_fwd", "fwd"):
            return "next"
        if arg in ("jump_rew", "rew"):
            return "previous"
        return None
    return None
