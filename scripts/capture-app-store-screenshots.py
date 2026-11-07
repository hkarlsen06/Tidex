#!/usr/bin/env python3
"""Capture App Store PNGs using the real UI and offline fixtures.

iPhone captures cover every App Store locale in ios/fastlane/metadata and feed the 3D renderer.
iPad captures cover en-US and no and feed the flat renderer.
Duo captures use both displays, saving raw PNGs in duo/<locale>/ and finished artwork in 3d-duo/<locale>/.

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
import zlib


ROOT = Path(__file__).resolve().parents[1]


def reject_black_capture(source):
    """Reject the solid-black RGB PNGs XCTest sometimes returns on the Duo runtime."""
    data = source.read_bytes()
    if data[24:26] != bytes([8, 2]):
        raise SystemExit(f"Expected an opaque 8-bit RGB screenshot: {source}")
    width, height = struct.unpack(">II", data[16:24])
    compressed = []
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"IDAT":
            compressed.append(data[offset + 8:offset + 8 + length])
        offset += length + 12
    raster = zlib.decompress(b"".join(compressed))
    stride = width * 3 + 1
    if len(raster) != stride * height:
        raise SystemExit(f"Unexpected PNG raster: {source}")
    # Every PNG row filter encodes solid black as zero RGB bytes. Ignore the filter byte.
    if not any(any(raster[row + 1:row + stride]) for row in range(0, len(raster), stride)):
        raise SystemExit(f"XCTest returned a black screenshot: {source}. No Duo set was published.")


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
                    # On the Duo runtime, XCTest truncates the inner window's fractional origin.
                    # Add the missing canvas edge without rescaling the captured app pixels.
                    if family == "Duo-inner" and size in {(2006, 2852), (2852, 2006)}:
                        run("sips", "--padToHeightWidth", str(size[1] + 1), str(size[0] + 1),
                            "--padColor", "000000", str(source), "--out", str(source),
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        size = struct.unpack(">II", source.read_bytes()[16:24])
                    accepted = {"iPhone": {(1260, 2736), (1290, 2796), (1320, 2868)},
                                "iPad": {(2048, 2732), (2064, 2752)},
                                "Duo-outer": {(1398, 2034)},
                                "Duo-inner": {(2853, 2007), (2007, 2853)}}
                    if size not in accepted[family]:
                        raise SystemExit(f"Unexpected {family} screenshot size: {size}")
                    if family.startswith("Duo-"):
                        reject_black_capture(source)
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


def capture_duo(device, agent_device, output, locales):
    known = simulators()
    if device not in known or not known[device].get("isAvailable"):
        raise SystemExit(f"Simulator unavailable: {device}")
    if "iPhone-Duo" not in known[device].get("deviceTypeIdentifier", ""):
        raise SystemExit("--duo must select an iPhone Duo simulator")
    # Open this simulator in the Device panel before running the capture.
    if known[device]["state"] != "Booted":
        raise SystemExit("Open the Duo simulator with T3 device_open first")
    with tempfile.TemporaryDirectory(prefix="tidex-duo-captures-") as temporary:
        staging = Path(temporary)
        for pose, display in [("closed", "outer"), ("open", "inner")]:
            run(str(agent_device), "open", "no.tidex.app")
            fold = subprocess.run([str(agent_device), "fold", pose], cwd=ROOT,
                                  text=True, capture_output=True)
            if fold.returncode:
                if "first hinge-angle read returned no sample" not in fold.stdout + fold.stderr:
                    raise SystemExit(fold.stdout + fold.stderr)
                print(fold.stderr or fold.stdout, flush=True)
                # This runtime can dispatch a fold without reading its angle. Require the selected
                # panel's native dimensions on every test attachment before publishing it.
            capture([device], f"Duo-{display}", staging, locales)
        run("node", str(ROOT / "scripts/render-duo-screenshots.mjs"),
            str(staging), str(output / "3d-duo"), *locales)
        # A failed second display must leave any previous complete set untouched.
        for locale in locales:
            destination = output / "duo" / locale
            destination.mkdir(parents=True, exist_ok=True)
            for source in (staging / locale).glob("Duo-*.png"):
                shutil.copyfile(source, destination / source.name)
    print(f"Duo artwork ready in {output / '3d-duo'}. Raw captures are in {output / 'duo'}.\n"
          "Fastlane 2.240.1 does not recognize Duo sizes; upload these through App Store Connect.",
          flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone", help="iPhone simulator UUID")
    parser.add_argument("--ipad", help="iPad simulator UUID")
    parser.add_argument("--duo", help="Also capture this existing iPhone Duo simulator UUID")
    parser.add_argument("--duo-agent-device", type=Path,
                        help="Exact agent-device command returned by T3 device_open for --duo")
    parser.add_argument("--duo-only", action="store_true", help="Capture Duo without iPhone/iPad renders")
    parser.add_argument("--locales", nargs="+", help="App Store locales to capture; defaults to all")
    parser.add_argument("--iphone-simulators", type=int, default=3,
                        help="Simulators to split the iPhone locales across (default 3)")
    parser.add_argument("--output", type=Path, help="Output directory; defaults to ASConnectScreenshots/<version>")
    args = parser.parse_args()
    if args.duo_only and not args.duo:
        parser.error("--duo-only requires --duo")
    if args.locales and not args.duo_only:
        parser.error("--locales requires --duo-only; existing renderers require all locales")
    if bool(args.duo) != bool(args.duo_agent_device):
        parser.error("--duo and --duo-agent-device must be provided together")
    if args.duo_agent_device and not args.duo_agent_device.is_file():
        parser.error("--duo-agent-device must be the command returned by device_open")
    version = re.search(r"^MARKETING_VERSION = (\S+)",
                        (ROOT / "ios/Version.xcconfig").read_text(), re.MULTILINE).group(1)
    output = args.output or ROOT / "ios/ASConnectScreenshots" / version
    raw = output / "raw-dark"
    available = sorted(path.name for path in (ROOT / "ios/fastlane/metadata").iterdir()
                       if path.is_dir() and path.name != "review_information")
    locales = list(dict.fromkeys(args.locales or available))
    if set(locales) - set(available):
        parser.error(f"Unknown App Store locales: {sorted(set(locales) - set(available))}")
    if args.duo:
        capture_duo(args.duo, args.duo_agent_device.resolve(), output, locales)
    if args.duo_only:
        return
    iphone = args.iphone or default_device("iPhone 18 Pro Max")
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
