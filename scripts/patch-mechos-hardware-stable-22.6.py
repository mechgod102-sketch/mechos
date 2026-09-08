#!/usr/bin/env python3
# MECHOS_HARDWARE_STABLE_PATCHER_V22_8
from __future__ import annotations

import re
import sys
from pathlib import Path

MARKER = "# MECHOS_HARDWARE_STABLE_22_6_INTEGRATION"
PREPARE_CALL = "bash /workspace/scripts/mechos-hardware-prepare-stable.sh final"
SEED_CALL = "bash /workspace/scripts/mechos-hardware-stable-seed-v22.sh final"
ACCOUNT_CALL = "bash /workspace/scripts/mechos-postinstall-account-hotfix.sh final"
FOLLOW_STABLE_CALL = "bash /workspace/scripts/mechos-hardware-follow-stable.sh final"


def ensure_existing_patch(text: str) -> str:
    if SEED_CALL not in text:
        raise SystemExit("hardware stable marker exists without seed integration call")
    if ACCOUNT_CALL not in text:
        raise SystemExit("hardware stable marker exists without postinstall account hotfix call")

    if PREPARE_CALL not in text:
        anchor = SEED_CALL + "\n"
        if anchor not in text:
            raise SystemExit("could not place stable preparation before 22.6 seed")
        text = text.replace(anchor, PREPARE_CALL + "\n" + anchor, 1)

    if FOLLOW_STABLE_CALL not in text:
        anchor = ACCOUNT_CALL + "\n"
        if anchor not in text:
            raise SystemExit("could not place latest-stable follower after account hotfix")
        text = text.replace(anchor, anchor + FOLLOW_STABLE_CALL + "\n", 1)

    return text


def validate_order(text: str) -> None:
    for call, label in (
        (PREPARE_CALL, "stable preparation"),
        (SEED_CALL, "hardware stable seed"),
        (ACCOUNT_CALL, "postinstall account hotfix"),
        (FOLLOW_STABLE_CALL, "latest stable follower"),
    ):
        if text.count(call) != 1:
            raise SystemExit(f"{label} must appear exactly once")

    if not (
        text.index(PREPARE_CALL)
        < text.index(SEED_CALL)
        < text.index(ACCOUNT_CALL)
        < text.index(FOLLOW_STABLE_CALL)
    ):
        raise SystemExit(
            "hardware build order must be stable preparation -> 22.6 seed -> account repair -> newest stable overlay"
        )


def patch(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        text = ensure_existing_patch(text)
        path.write_text(text, encoding="utf-8")
        validate_order(path.read_text(encoding="utf-8"))
        return

    matches = list(re.finditer(r"(?m)^[ \t]*(?:sudo[ \t]+)?mkarchiso\b[^\n]*$", text))
    if not matches:
        raise SystemExit("mkarchiso invocation not found")

    match = matches[-1]
    block = (
        f"{MARKER}\n"
        "# Prepare the newest published stable target (including source-first\n"
        "# future hotfixes such as HF27), seed Hotfix 22.6 as the validated\n"
        "# physical-hardware minimum, apply the final account repair, then\n"
        "# overlay the selected cumulative stable bundle.\n"
        f"{PREPARE_CALL}\n"
        f"{SEED_CALL}\n"
        f"{ACCOUNT_CALL}\n"
        f"{FOLLOW_STABLE_CALL}\n\n"
    )
    text = text[: match.start()] + block + text[match.start() :]
    path.write_text(text, encoding="utf-8")

    check = path.read_text(encoding="utf-8")
    if check.count(MARKER) != 1:
        raise SystemExit("hardware stable integration marker was not inserted exactly once")
    validate_order(check)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: patch-mechos-hardware-stable-22.6.py BUILD_SCRIPT")
    path = Path(sys.argv[1])
    if not path.is_file():
        raise SystemExit(f"build script not found: {path}")
    patch(path)


if __name__ == "__main__":
    main()
