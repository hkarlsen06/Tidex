#!/usr/bin/env python3
"""Capture Duo fixtures through the command returned by T3 device_open.

Screenshots are evidence for visual review, not automatic layout approvals.
"""

import argparse
import json
import struct
import subprocess
from pathlib import Path


SCREENS = [
    "onboarding", "onboarding-setup", "login", "signup", "time-input", "screenshot-prompt",
    "reset-password", "accept-terms", "calendar-import", "event-details",
    "settings", "settings-profile", "settings-security", "settings-notifications",
    "settings-appearance", "settings-calendar", "settings-data", "settings-recurring", "settings-feedback",
    "money", "money-payroll", "stats", "calendar", "shared-calendar",
    "friends", "friends:add-friend", "friends:profile", "chat", "chat-reply", "payroll-breakdown",
    "pay-settings-review", "pay-history-tariff-editor", "job-pay-setup", "add-job-setup",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent-device", required=True, type=Path)
    parser.add_argument("--device-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--screens", nargs="+", choices=SCREENS, default=SCREENS)
    parser.add_argument("--poses", nargs="+", choices=["closed", "open", "half-open"],
                        default=["closed", "open"])
    parser.add_argument("--themes", nargs="+", choices=["light", "dark"], default=["dark"])
    parser.add_argument("--text-size", default="large")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = []

    def command(parts, allow_unverified_fold=False):
        result = subprocess.run(parts, capture_output=True, text=True, timeout=90)
        if result.returncode:
            # Some Device Hub versions dispatch the hinge event but cannot read its angle.
            # Capture and validate the active panel before accepting that specific outcome.
            if not (allow_unverified_fold
                    and "first hinge-angle read returned no sample" in result.stdout + result.stderr):
                raise RuntimeError(result.stdout + result.stderr)
        return result

    def device(*parts, **kwargs):
        return command([str(args.agent_device), *parts], **kwargs)

    def environment(name, value):
        command(["xcrun", "simctl", "spawn", args.device_id,
                 "launchctl", "setenv", name, value])

    environment("TIDEX_UI_TEST_SCENARIO", "design-review")
    # open establishes the app session needed by the input and capture commands.
    device("open", "no.tidex.app", "--relaunch", "--launch-args", "-ui-testing")
    device("settings", "text-size", args.text_size)
    try:
        for pose in args.poses:
            fold = device("fold", pose, allow_unverified_fold=True)
            for theme in args.themes:
                for screen in args.screens:
                    fixture, _, friend_view = screen.partition(":")
                    scenario = {"chat": "friends-chat", "chat-reply": "friends-chat-reply"}.get(
                        fixture, "design-review")
                    environment("TIDEX_UI_TEST_SCENARIO", scenario)
                    environment("TIDEX_DESIGN_SCREEN", fixture)
                    environment("TIDEX_DESIGN_FRIENDS_VIEW", friend_view or "cards")
                    device("open", "no.tidex.app", "--relaunch", "--launch-args", "-ui-testing",
                           "--launch-args", "-cachedTheme", "--launch-args", theme)
                    device("wait", "role=text" if fixture == "stats" else "role=button", "30000")
                    device("wait", "stable", "2500", "30000")
                    name = f"{pose}-{theme}-{args.text_size}-{screen.replace(':', '-')}"
                    snapshot = json.loads(device("snapshot", "-i", "--json", "--timeout", "20000").stdout)
                    if not snapshot.get("success") or not snapshot.get("data", {}).get("nodes"):
                        raise RuntimeError(f"No accessibility evidence for {name}")
                    args.output.joinpath(f"{name}.json").write_text(json.dumps(snapshot, indent=2))
                    png = args.output / f"{name}.png"
                    device("screenshot", str(png))
                    width, height = struct.unpack(">II", png.read_bytes()[16:24])
                    expected = (466, 678) if pose == "closed" else (669, 951)
                    if tuple(sorted((width, height))) != expected:
                        raise RuntimeError(f"Unexpected {pose} panel for {name}: {width}x{height}")
                    item = dict(screen=screen, pose=pose, theme=theme, text_size=args.text_size,
                                width=width, height=height, screenshot=png.name,
                                hinge_angle_verified=fold.returncode == 0,
                                review="pending")
                    manifest.append(item)
                    (args.output / "captures.json").write_text(json.dumps(manifest, indent=2))
                    print(f"Captured {name} {width}x{height}", flush=True)
    finally:
        device("settings", "text-size", "large")
        # Do not leak fixture selection into a later normal launch.
        for name in ["TIDEX_UI_TEST_SCENARIO", "TIDEX_DESIGN_SCREEN", "TIDEX_DESIGN_FRIENDS_VIEW"]:
            command(["xcrun", "simctl", "spawn", args.device_id, "launchctl", "unsetenv", name])


if __name__ == "__main__":
    main()
