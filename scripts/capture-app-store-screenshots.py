#!/usr/bin/env python3
"""Capture English and Bokmal App Store PNGs using the real UI and offline fixtures.

Run from the repository root: python3 scripts/capture-app-store-screenshots.py
Use --iphone / --ipad to select existing simulator UUIDs explicitly.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, text=True, **kwargs)


def default_device(name):
    inventory = json.loads(run(
        "xcrun", "simctl", "list", "devices", "available", "--json", capture_output=True
    ).stdout)
    for runtime, devices in sorted(inventory["devices"].items()):
        if ".iOS-" not in runtime:
            continue
        for device in devices:
            if device["name"] == name:
                return device["udid"]
    raise SystemExit(f"No available {name} simulator. Specify a UUID with --iphone or --ipad.")


def capture(device, family, output):
    inventory = json.loads(run(
        "xcrun", "simctl", "list", "devices", "--json", capture_output=True
    ).stdout)
    selected = next((d for ds in inventory["devices"].values() for d in ds if d["udid"] == device), None)
    if selected is None or not selected.get("isAvailable"):
        raise SystemExit(f"Simulator unavailable: {device}")
    was_booted = selected["state"] == "Booted"
    if not was_booted:
        run("xcrun", "simctl", "boot", device)
    run("xcrun", "simctl", "bootstatus", device, "-b")
    run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41",
        "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
        "--batteryState", "charged", "--batteryLevel", "100")
    try:
        environment = dict(os.environ,
            XCODE_TEST_AGENT_DESTINATION=f"platform=iOS Simulator,id={device}",
            XCODE_TEST_AGENT_KEEP_ARTIFACTS="1")
        # The wrapper retains diagnostic artifacts; its heartbeat stays visible on stderr.
        result = subprocess.run([
            str(ROOT / "scripts/xcode-test-agent.sh"), "--json", "--",
            "-only-testing:TidexAppUITests/TidexAppUITests/testAppStoreScreenshots",
            "-parallel-testing-enabled", "NO",
        ], cwd=ROOT, env=environment, text=True, stdout=subprocess.PIPE)
        payload = json.loads(result.stdout.strip().splitlines()[-1])
        if result.returncode or payload["status"] != "SUCCESS":
            print(json.dumps(payload, ensure_ascii=False, indent=2))
            raise SystemExit("Screenshot UI test failed; no screenshots from this run were published.")
        with tempfile.TemporaryDirectory(prefix="tidex-screenshot-export-") as temporary:
            run("xcrun", "xcresulttool", "export", "attachments", "--path",
                payload["result_bundle_path"], "--output-path", temporary,
                stdout=subprocess.DEVNULL)
            exports = Path(temporary)
            screenshots = {}
            for test in json.loads((exports / "manifest.json").read_text()):
                for attachment in test["attachments"]:
                    match = re.match(r"(en|nb)-(\d{2}-[a-z]+)_", attachment["suggestedHumanReadableName"])
                    if not match:
                        continue
                    language, screen = match.groups()
                    source = exports / attachment["exportedFileName"]
                    header = source.read_bytes()[:24]
                    if header[:8] != b"\x89PNG\r\n\x1a\n":
                        raise SystemExit(f"Expected PNG: {source}")
                    size = struct.unpack(">II", header[16:24])
                    accepted = {"iPhone": {(1260, 2736), (1290, 2796), (1320, 2868)},
                                "iPad": {(2048, 2732), (2064, 2752)}}
                    if size not in accepted[family]:
                        raise SystemExit(f"Unexpected {family} screenshot size: {size}")
                    screenshots[(language, screen)] = source
            expected = {(language, screen) for language in ("en", "nb")
                        for screen in ("01-home", "02-statistics", "03-schedule", "04-payroll", "05-add", "06-wagey")}
            if set(screenshots) != expected:
                raise SystemExit(f"Incomplete screenshots: expected {expected}, got {set(screenshots)}")
            for (language, screen), source in screenshots.items():
                destination = output / {"en": "en-US", "nb": "no"}[language]
                destination.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination / f"{family}-{screen}.png")
            print(f"Verified and saved {len(screenshots)} {family} screenshots to {output}", flush=True)
    finally:
        run("xcrun", "simctl", "status_bar", device, "clear")
        if not was_booted:
            run("xcrun", "simctl", "shutdown", device)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone", help="iPhone simulator UUID")
    parser.add_argument("--ipad", help="iPad simulator UUID")
    parser.add_argument("--output", type=Path, help="Output directory; defaults to ASConnectScreenshots/<version>")
    args = parser.parse_args()
    version = re.search(r"^MARKETING_VERSION = (\S+)",
                        (ROOT / "ios/Version.xcconfig").read_text(), re.MULTILINE).group(1)
    output = args.output or ROOT / "ios/ASConnectScreenshots" / version
    iphone = args.iphone or default_device("iPhone 17 Pro Max")
    raw = output / "raw-dark"
    capture(iphone, "iPhone", raw)
    capture(args.ipad or default_device("iPad Pro 13-inch (M5)"), "iPad", raw)
    run("node", str(ROOT / "scripts/render-app-store-screenshots.mjs"), str(output))


if __name__ == "__main__":
    main()
