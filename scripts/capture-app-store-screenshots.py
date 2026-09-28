#!/usr/bin/env python3
"""Capture App Store PNGs using the real UI and offline fixtures.

iPhone captures cover every App Store locale in ios/fastlane/metadata and feed the 3D renderer.
iPad captures cover en-US and no and feed the flat renderer.

Run from the repository root: python3 scripts/capture-app-store-screenshots.py
Use --iphone / --ipad to select existing simulator UUIDs explicitly. iPhone locales are split
across --iphone-simulators copies of the iPhone simulator (created on first use, shut down after).
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


def simulators():
    inventory = json.loads(run(
        "xcrun", "simctl", "list", "devices", "--json", capture_output=True
    ).stdout)
    return {d["udid"]: dict(d, runtime=runtime) for runtime, ds in inventory["devices"].items() for d in ds}


def copies(device, count):
    """The device plus count - 1 simulators of the same model and runtime, created if missing."""
    known = simulators()
    base = known[device]
    devices = [device]
    for number in range(2, count + 1):
        name = f"{base['name']} (Screenshots {number})"
        existing = next((d["udid"] for d in known.values() if d["name"] == name
                         and d["runtime"] == base["runtime"] and d.get("isAvailable")), None)
        devices.append(existing or run(
            "xcrun", "simctl", "create", name, base["deviceTypeIdentifier"], base["runtime"],
            capture_output=True).stdout.strip())
    return devices


def capture(devices, family, output, locales):
    known = simulators()
    if any(device not in known or not known[device].get("isAvailable") for device in devices):
        raise SystemExit(f"Simulator unavailable: {devices}")
    started = [device for device in devices if known[device]["state"] != "Booted"]
    for device in started:
        run("xcrun", "simctl", "boot", device)
    for device in devices:
        run("xcrun", "simctl", "bootstatus", device, "-b", stdout=subprocess.DEVNULL)
        run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41",
            "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
            "--batteryState", "discharging", "--batteryLevel", "100")
    try:
        environment = dict(os.environ,
            XCODE_TEST_AGENT_DESTINATION=f"platform=iOS Simulator,id={devices[0]}",
            XCODE_TEST_AGENT_KEEP_ARTIFACTS="1",
            TEST_RUNNER_TIDEX_SCREENSHOT_LOCALES=",".join(locales),
            # Each simulator takes every len(devices)-th locale; see testAppStoreScreenshots.
            TEST_RUNNER_TIDEX_SCREENSHOT_SHARDS=",".join(devices))
        # xcodebuild counts the app's AVAudioSession runtime warning as a failure and then spends
        # 10 minutes timing out on collecting simulator diagnostics.
        destinations = ["-collect-test-diagnostics", "never"]
        if len(devices) > 1:
            # One build, tested on every simulator at once.
            environment["XCODE_TEST_AGENT_PARALLEL"] = "1"
            destinations += ["-parallel-testing-enabled", "NO",
                             "-maximum-concurrent-test-simulator-destinations", str(len(devices))]
            for device in devices[1:]:
                destinations += ["-destination", f"platform=iOS Simulator,id={device}"]
        # The wrapper retains diagnostic artifacts; its heartbeat stays visible on stderr.
        result = subprocess.run([
            str(ROOT / "scripts/xcode-test-agent.sh"), "--json", "--", *destinations,
            "-only-testing:TidexAppUITests/TidexAppUITests/testAppStoreScreenshots",
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
                    match = re.match(r"(.+)-(\d{2}-[a-z]+)_", attachment["suggestedHumanReadableName"])
                    if not match or match.group(1) not in locales:
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
            expected = {(language, screen) for language in locales
                        for screen in ("01-home", "02-statistics", "03-schedule", "04-payroll", "05-add")}
            if set(screenshots) != expected:
                raise SystemExit(f"Incomplete screenshots: expected {expected}, got {set(screenshots)}")
            for (language, screen), source in screenshots.items():
                destination = output / language
                destination.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(source, destination / f"{family}-{screen}.png")
            print(f"Verified and saved {len(screenshots)} {family} screenshots to {output}", flush=True)
    finally:
        for device in devices:
            run("xcrun", "simctl", "status_bar", device, "clear")
        for device in started:
            run("xcrun", "simctl", "shutdown", device)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone", help="iPhone simulator UUID")
    parser.add_argument("--ipad", help="iPad simulator UUID")
    parser.add_argument("--iphone-simulators", type=int, default=3,
                        help="Simulators to split the iPhone locales across (default 3)")
    parser.add_argument("--output", type=Path, help="Output directory; defaults to ASConnectScreenshots/<version>")
    args = parser.parse_args()
    version = re.search(r"^MARKETING_VERSION = (\S+)",
                        (ROOT / "ios/Version.xcconfig").read_text(), re.MULTILINE).group(1)
    output = args.output or ROOT / "ios/ASConnectScreenshots" / version
    iphone = args.iphone or default_device("iPhone 18 Pro Max")
    raw = output / "raw-dark"
    locales = sorted(path.name for path in (ROOT / "ios/fastlane/metadata").iterdir() if path.is_dir())
    capture(copies(iphone, args.iphone_simulators), "iPhone", raw, locales)
    # The 3D render only reads the iPhone captures, so it runs while the iPad captures.
    render = subprocess.Popen(["node", str(ROOT / "scripts/render-3d-screenshots.mjs"),
        str(ROOT / "scripts/assets/app-store/tidex-3d.json"), str(raw), str(output / "3d")], cwd=ROOT)
    try:
        capture([args.ipad or default_device("iPad Pro 13-inch (M5)")], "iPad", raw, ["en-US", "no"])
    finally:
        if render.wait():
            raise SystemExit("3D render failed")
    run("node", str(ROOT / "scripts/render-app-store-screenshots.mjs"), str(output))


if __name__ == "__main__":
    main()
