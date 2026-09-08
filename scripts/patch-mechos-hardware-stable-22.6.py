#!/usr/bin/env python3
# MECHOS_HARDWARE_STABLE_PATCHER_V22_7
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_HARDWARE_STABLE_22_6_INTEGRATION"
SEED_CALL = "bash /workspace/scripts/mechos-hardware-stable-seed-v22.sh final"
ACCOUNT_CALL = "bash /workspace/scripts/mechos-postinstall-account-hotfix.sh final"
FOLLOW_STABLE_CALL = "bash /workspace/scripts/mechos-hardware-follow-stable.sh final"


def patch(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        if SEED_CALL not in text:
            raise SystemExit("hardware stable marker exists without seed integration call")
        if ACCOUNT_CALL not in text:
            raise SystemExit("hardware stable marker exists without postinstall account hotfix call")
        if FOLLOW_STABLE_CALL not in text:
            # Upgrade an already-patched 22.6 build script in place.
            anchor = ACCOUNT_CALL + "\n"
            if anchor not in text:
                raise SystemExit("could not place latest-stable follower after account hotfix")
            text = text.replace(anchor, anchor + FOLLOW_STABLE_CALL + "\n", 1)
            path.write_text(text, encoding="utf-8")
        check = path.read_text(encoding="utf-8")
        if not (
            check.index(SEED_CALL)
            < check.index(ACCOUNT_CALL)
            < check.index(FOLLOW_STABLE_CALL)
        ):
            raise SystemExit(
                "hardware build order must be 22.6 seed -> account repair -> newest stable overlay"
            )
        return

    matches = list(re.finditer(r"(?m)^[ \t]*(?:sudo[ \t]+)?mkarchiso\b[^\n]*$", text))
    if not matches:
        raise SystemExit("mkarchiso invocation not found")

    match = matches[-1]
    block = (
        f"{MARKER}\n"
        "# Seed Hotfix 22.6 as the physical-hardware minimum, apply the final\n"
        "# account repair, then overlay the newest published cumulative stable\n"
        "# bundle selected by updates/stable.json. This keeps new hardware ISOs\n"
        "# current without dropping the validated 22.6 hardware baseline.\n"
        f"{SEED_CALL}\n"
        f"{ACCOUNT_CALL}\n"
        f"{FOLLOW_STABLE_CALL}\n\n"
    )
    text = text[: match.start()] + block + text[match.start() :]
    path.write_text(text, encoding="utf-8")

    check = path.read_text(encoding="utf-8")
    if check.count(MARKER) != 1:
        raise SystemExit("hardware stable integration marker was not inserted exactly once")
    if check.count(SEED_CALL) != 1:
        raise SystemExit("hardware stable seed was not inserted exactly once")
    if check.count(ACCOUNT_CALL) != 1:
        raise SystemExit("postinstall account hotfix was not inserted exactly once")
    if check.count(FOLLOW_STABLE_CALL) != 1:
        raise SystemExit("latest stable follower was not inserted exactly once")
    if not (
        check.index(SEED_CALL)
        < check.index(ACCOUNT_CALL)
        < check.index(FOLLOW_STABLE_CALL)
    ):
        raise SystemExit(
            "hardware build order must be 22.6 seed -> account repair -> newest stable overlay"
        )


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-mechos-hardware-stable-22.6.py BUILD_SCRIPT")
    path = Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"build script not found: {path}")
    patch(path)


if __name__ == "__main__":
    main()
