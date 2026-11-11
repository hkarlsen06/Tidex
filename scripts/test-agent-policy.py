#!/usr/bin/env python3
"""Exercise wrapper scheduling and destination selection with fake Apple tools."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


SOURCE = Path(__file__).resolve().parent
REPO = "Paeonia" if (SOURCE / "lib/paeonia-xcode.sh").exists() else "Tidex"


def executable(path, content):
    path.write_text(content)
    path.chmod(0o755)


with tempfile.TemporaryDirectory(prefix="ios-agent-policy-") as directory:
    root = Path(directory)
    scripts = root / "scripts"
    scripts.mkdir()
    (scripts / "lib").mkdir()
    for name in ("xcode-test-agent.sh", "xcode-build-agent.sh", "lock"):
        shutil.copy2(SOURCE / name, scripts / name)
    if REPO == "Paeonia":
        shutil.copy2(SOURCE / "scenario-screenshot", scripts / "scenario-screenshot")
    shutil.copy2(SOURCE / "lib/xcode-agent-throttle.sh", scripts / "lib/xcode-agent-throttle.sh")
    (scripts / "lib/paeonia-xcode.sh").write_text(":\n")
    executable(scripts / "generate-ios-build-number.sh", "#!/bin/sh\nexit 0\n")
    executable(scripts / "install-git-hooks.sh", "#!/bin/sh\nexit 0\n")
    (root / "ios" / (REPO + "AppUITests")).mkdir(parents=True)
    tools = root / "bin"
    tools.mkdir()
    log = root / "commands.jsonl"
    common = '''#!/usr/bin/python3
import json, os, pathlib, sys, time
args = sys.argv[1:]
with open(os.environ["POLICY_LOG"], "a") as stream:
    stream.write(json.dumps([pathlib.Path(sys.argv[0]).name, *args]) + "\\n")
'''
    executable(tools / "git", common + '''
if "--git-common-dir" in args:
    print(os.environ["POLICY_ROOT"] + "/.git")
elif "--show-toplevel" in args:
    print(os.environ["POLICY_ROOT"])
''')
    executable(tools / "ios-agent", common + '''
if args == ["devices", "--json"]:
    print('{"devices": [{"name": "spare", "allowed": true}]}')
elif args == ["physical-destination"]:
    if os.environ.get("POLICY_DISCOVERY_FAIL") == "1":
        sys.exit(1)
    print(os.environ.get("POLICY_PHYSICAL", ""))
elif args and args[0] == "simulator-lease":
    pass
elif args and args[0] == "xcodebuild":
    status = pathlib.Path(os.environ["IOS_AGENT_STATUS_FILE"])
    if os.environ.get("POLICY_STOP") == "1":
        print("[ios-agent] stopped after 45m00s because other agents are waiting", file=sys.stderr)
        sys.exit(124)
    if os.environ.get("POLICY_QUEUE") and "test-without-building" not in args:
        status.write_text("queued\\tbuild: position 2 of 2; running now: Other/worktree build since 12:00:00\\n")
        time.sleep(float(os.environ["POLICY_QUEUE"]))
    status.write_text("running\\t" + str(int(time.time())) + "\\n")
    os.environ["POLICY_CONTROLLER"] = "1"
    os.execv(os.environ["POLICY_ROOT"] + "/bin/xcodebuild", ["xcodebuild", *args[1:]])
else:
    sys.exit(2)
''')
    executable(tools / "xcodebuild", common + '''
if os.environ.get("POLICY_CONTROLLER", "") != os.environ["POLICY_EXPECT_CONTROLLER"]:
    print("error: xcodebuild ran outside the host controller, or the controller ran where none is installed")
    sys.exit(8)
if os.environ.get("POLICY_BUILD_FAIL") == "1":
    print("error: mock compile failed")
    sys.exit(9)
if os.environ.get("POLICY_BUILD_BLOCK") == "1":
    pathlib.Path(os.environ["POLICY_ROOT"], "build-pid").write_text(str(os.getpid()))
    time.sleep(30)
if "-resultBundlePath" in args:
    pathlib.Path(args[args.index("-resultBundlePath") + 1]).mkdir()
if "-derivedDataPath" in args:
    app = pathlib.Path(args[args.index("-derivedDataPath") + 1], "Build/Products/Debug-iphonesimulator/PaeoniaApp.app")
    app.mkdir(parents=True, exist_ok=True)
print("Executed 1 test, with 0 failures")
''')
    executable(tools / "xcrun", common + '''
if args[:4] == ["simctl", "list", "devices", "available"]:
    print(json.dumps({"devices": {"runtime": [
        {"name": "Shared iPhone" + suffix, "udid": "sim" + str(i), "state": "Shutdown", "isAvailable": True}
        for i, suffix in [(1, ""), (2, " 2"), (3, " 3")]
    ]}}))
elif args[:3] == ["simctl", "list", "devices"]:
    print("Booted")
elif args and args[0] == "xcresulttool":
    print(json.dumps({"metrics": {"testsCount": {"_value": "1"}, "testsFailedCount": {"_value": "0"}}}))
elif args[:2] == ["simctl", "uninstall"]:
    assert args[2].startswith("sim") or args[2].startswith("Shared iPhone"), "physical data was uninstalled"
elif args[:2] == ["simctl", "io"] and "screenshot" in args:
    pathlib.Path(args[-1]).write_bytes(b"mock screenshot")
''')
    executable(tools / "sleep", "#!/usr/bin/python3\nimport time\ntime.sleep(0.01)\n")
    base_env = {key: value for key, value in os.environ.items()
                if not key.startswith(("XCODE_", "IOS_AGENT_", "AGENT_SIMULATOR_", "PAEONIA_LOCK_"))}
    base_env.update(PATH=str(tools) + ":/usr/bin:/bin", HOME=str(root), POLICY_ROOT=str(root), POLICY_LOG=str(log),
                    AGENT_SIMULATOR_LOCK_ROOT=str(root / "sim-locks"), XCODE_AGENT_NICE="0",
                    TMPDIR=str(root), POLICY_PHYSICAL="platform=iOS,id=spare", POLICY_EXPECT_CONTROLLER="1")
    # A machine without the host controller, such as CI.
    bare_tools = root / "bare-bin"
    bare_tools.mkdir()
    for tool in tools.iterdir():
        if tool.name != "ios-agent":
            (bare_tools / tool.name).symlink_to(tool)
    bare = dict(PATH=str(bare_tools) + ":/usr/bin:/bin", POLICY_EXPECT_CONTROLLER="")

    def run(script, *arguments, expected=0, **overrides):
        log.write_text("")
        result = subprocess.run(["bash", str(scripts / script), *arguments], cwd=root,
                                env=dict(base_env, **overrides), capture_output=True, text=True, timeout=10)
        assert result.returncode == expected, (script, arguments, result.returncode, result.stdout, result.stderr)
        commands = [json.loads(line) for line in log.read_text().splitlines()]
        return result, commands

    def builds(commands):
        return [command[1:] for command in commands if command[0] == "xcodebuild"]

    def check_test(arguments=(), expected_physical=True, **overrides):
        result, commands = run("xcode-test-agent.sh", "--json", *arguments, **overrides)
        phases = builds(commands)
        assert len(phases) == 2, commands
        expected = "generic/platform=iOS" if expected_physical else "generic/platform=iOS Simulator"
        assert phases[0][phases[0].index("-destination") + 1] == expected, phases
        if expected_physical:
            assert not any(command[0] == "xcrun" and command[1:3] in (["simctl", "uninstall"], ["simctl", "bootstatus"])
                           for command in commands), commands
        assert json.loads(result.stdout.splitlines()[-1])["status"] == "SUCCESS", result.stdout
        return commands

    def check_cancel(script, *arguments):
        (root / "build-pid").unlink(missing_ok=True)
        process = subprocess.Popen(["bash", str(scripts / script), *arguments], cwd=root,
                                   env=dict(base_env, POLICY_BUILD_BLOCK="1"),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 5
        while not (root / "build-pid").exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert (root / "build-pid").exists(), "mock compile never started"
        child = int((root / "build-pid").read_text())
        process.send_signal(signal.SIGTERM)
        _, stderr = process.communicate(timeout=5)
        assert process.returncode == 143, (script, process.returncode, stderr)
        try:
            os.kill(child, 0)
        except ProcessLookupError:
            pass
        else:
            raise AssertionError(script + ": cancellation orphaned the compile")

    safe_selection = ("--", "-only-testing:" + REPO + "AppTests/ISO8601TimestampTests")
    check_test(expected_physical=False)
    check_test(safe_selection)
    check_test(("--", "-only-testing:" + REPO + "AppTests/Example"), expected_physical=False)
    check_test(safe_selection + ("-only-testing:" + REPO + "AppTests/LocalPrivacyPurgeTests",), expected_physical=False)
    commands = check_test(safe_selection, expected_physical=False, POLICY_PHYSICAL="")
    assert any(command[:3] == ["xcrun", "simctl", "bootstatus"] and command[3] == "sim1" for command in commands)
    check_test(safe_selection, expected_physical=False, POLICY_DISCOVERY_FAIL="1")
    for selection in ("-only-testing:" + REPO + "AppUITests/Fixture", "-testPlan", "-skip-testing:Example"):
        commands = check_test(("--", selection), expected_physical=False)
        assert ["ios-agent", "physical-destination"] not in commands, commands
    if REPO == "Paeonia":
        commands = check_test(("--ui",), expected_physical=False)
        assert ["ios-agent", "physical-destination"] not in commands
    commands = check_test(safe_selection, XCODE_TEST_AGENT_DESTINATION="platform=iOS,id=explicit")
    assert ["ios-agent", "physical-destination"] not in commands
    commands = check_test(safe_selection + ("-destination", "platform=iOS,id=explicit"))
    assert ["ios-agent", "physical-destination"] not in commands
    result, commands = run("xcode-test-agent.sh", "--json", expected=2, XCODE_TEST_AGENT_DESTINATION="platform=iOS,id=explicit")
    assert "device-safe" in result.stderr and not builds(commands), (result.stderr, commands)
    check_test(XCODE_TEST_AGENT_DESTINATION="platform=iOS Simulator,id=sim1", expected_physical=False)
    for wrapper, phases in (("xcode-test-agent.sh", 2), ("xcode-build-agent.sh", 1)):
        result, commands = run(wrapper, "--json", POLICY_QUEUE="2.2")
        assert "[" + wrapper[:-3] + "] queued for build: position 2 of 2; running now: Other/worktree build since 12:00:00 (" in result.stderr, result.stderr
        summary = json.loads(result.stdout.splitlines()[-1])
        assert summary["status"] == "SUCCESS" and 2 <= summary["queued"] <= 4 and summary["compiled"] <= 1, summary
        result, _ = run(wrapper, expected=124, POLICY_STOP="1")
        assert "[ios-agent] stopped after 45m00s because other agents are waiting" in result.stderr, result.stderr
        result, commands = run(wrapper, "--json", **bare)
        summary = json.loads(result.stdout.splitlines()[-1])
        assert summary["status"] == "SUCCESS" and summary["queued"] <= 1, summary
        assert len(builds(commands)) == phases and all(build[build.index("-jobs") + 1] == "2" for build in builds(commands)), commands
    for wrapper in ("xcode-test-agent.sh", "xcode-build-agent.sh"):
        result, commands = run(wrapper, "--devices")
        assert json.loads(result.stdout)["devices"][0]["allowed"] is True
        assert not builds(commands), commands

    result, _ = run("lock", "pool")
    assert result.stdout.splitlines() == ["Shared iPhone", "Shared iPhone 2", "Shared iPhone 3"], result.stdout
    for count, expected in (("1", 1), ("2", 2), ("3", 3)):
        result, _ = run("lock", "pool", IOS_AGENT_SIMULATORS=count)
        assert len(result.stdout.splitlines()) == expected
    result, _ = run("lock", "pool", IOS_AGENT_SIMULATORS="0", expected=2)
    assert "IOS_AGENT_SIMULATORS" in result.stderr
    for name in ("Shared iPhone 2", "Shared iPhone 3", "simulator-2", "simulator-3"):
        result, commands = run("lock", "acquire", name, expected=2, IOS_AGENT_SIMULATORS="1")
        assert not any(command[0] == "xcrun" for command in commands), commands

    # An extra simulator boots only while the ones before it are busy.
    busy = dict(POLICY_ROOT=str(root / "busy"))
    run("lock", "acquire", "simulator", **busy)
    result, commands = run("lock", "acquire", "simulator")
    assert result.stdout.strip() == "Shared iPhone 2", result.stdout
    assert ["ios-agent", "simulator-lease", "Shared iPhone 2", "600"] in commands, commands
    _, commands = run("lock", "release", "simulator")
    assert ["xcrun", "simctl", "shutdown", "Shared iPhone 2"] in commands, commands
    run("lock", "release", "simulator", **busy)
    result, _ = run("lock", "acquire", "simulator")
    assert result.stdout.strip() == "Shared iPhone", result.stdout
    run("lock", "release", "simulator")
    _, commands = run("lock", "run", "Shared iPhone 2", "--", "true", IOS_AGENT_SIMULATORS="2")
    assert ["xcrun", "simctl", "shutdown", "Shared iPhone 2"] in commands
    assert not (root / "sim-locks/simulator-2").exists()
    _, commands = run("lock", "run", "simulator", "--", "true")
    assert not any(command[:3] == ["xcrun", "simctl", "shutdown"] for command in commands)
    assert not (root / "sim-locks/simulator").exists()
    run("lock", "acquire", "Shared iPhone 2", IOS_AGENT_SIMULATORS="2")
    _, commands = run("lock", "run", "Shared iPhone 2", "--", "true", IOS_AGENT_SIMULATORS="2")
    assert ["ios-agent", "simulator-lease", "Shared iPhone 2", "600"] in commands, commands
    _, commands = run("lock", "release", "simulator")
    assert ["xcrun", "simctl", "shutdown", "Shared iPhone 2"] in commands
    assert not (root / "sim-locks/simulator-2").exists()

    # The line is easiest to watch on a pool of one.
    base_env["IOS_AGENT_SIMULATORS"] = "1"
    order = root / "order"
    line = root / "sim-locks/.waiting"

    def places():
        return [place for place in line.glob("*") if place.suffix != ".reserved"]

    def wait_in_line(name, **overrides):
        waiting = len(places())
        process = subprocess.Popen(["bash", str(scripts / "lock"), "run", "simulator", "--", "sh", "-c", f"echo {name} >>{order}"],
                                   cwd=root, env=dict(base_env, POLICY_ROOT=str(root / name), **overrides),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 5
        while len(places()) <= waiting:
            assert time.monotonic() < deadline, name + " never joined the line"
            time.sleep(0.01)
        return process

    def finish(process):
        _, stderr = process.communicate(timeout=20)
        assert process.returncode == 0, stderr

    run("lock", "acquire", "simulator")
    waiters = []
    for name in ("first", "second", "third"):
        waiters.append(wait_in_line(name))
        time.sleep(1.1)  # places in the line are named by the second of arrival
    run("lock", "release", "simulator")
    for process in waiters:
        finish(process)
    assert order.read_text().split() == ["first", "second", "third"], order.read_text()

    session = {REPO.upper() + "_LOCK_SESSION_MINUTES": "0"}
    run("lock", "acquire", "simulator")
    result, _ = run("lock", "acquire", "simulator", **session)
    assert "goes to the agents waiting" not in result.stderr, result.stderr
    waiter = wait_in_line("fourth")
    result, _ = run("lock", "acquire", "simulator", **session)
    assert "goes to the agents waiting" in result.stderr and result.stdout.strip() == "Shared iPhone", (result.stdout, result.stderr)
    finish(waiter)
    assert order.read_text().split()[-1] == "fourth"
    run("lock", "release", "simulator")

    gone = line / "1-1"
    gone.write_text("gone|simulator")
    os.utime(gone, (1, 1))
    run("lock", "run", "simulator", "--", "true")
    assert not places(), places()

    # A waiter that a tool timeout stops keeps its place for the same request.
    run("lock", "acquire", "simulator")
    stopped = wait_in_line("early")
    time.sleep(1.1)
    late = wait_in_line("late")
    stopped.terminate()
    _, stderr = stopped.communicate(timeout=5)
    assert stopped.returncode == 143, (stopped.returncode, stderr)
    again = wait_in_line("early")
    run("lock", "release", "simulator")
    finish(again)
    finish(late)
    assert order.read_text().split()[-2:] == ["early", "late"], order.read_text()

    # With two slots enabled, a request for any simulator waits in the same line.
    two = dict(IOS_AGENT_SIMULATORS="2")
    run("lock", "acquire", "simulator")
    run("lock", "acquire", "Shared iPhone 2", POLICY_ROOT=str(root / "second-slot"), **two)
    any_slot = wait_in_line("any-slot", **two)
    run("lock", "release", "simulator")
    finish(any_slot)
    run("lock", "release", "simulator", POLICY_ROOT=str(root / "second-slot"), **two)
    result, _ = run("lock", "status")
    assert "waiting" not in result.stdout and not (root / "sim-locks/simulator").exists(), result.stdout

    if REPO == "Paeonia":
        scratch = Path("/tmp/paeonia-scenario-" + hashlib.sha1(str(root).encode()).hexdigest()[:10])
        try:
            image = root / "scenario.png"
            _, commands = run("scenario-screenshot", "example", "--wait", "0", "--out", str(image))
            assert image.read_bytes() == b"mock screenshot"
            assert not (root / "sim-locks/simulator").exists()
            result, _ = run("scenario-screenshot", "example", "--wait", "0", "--out", str(image), POLICY_QUEUE="2.2")
            assert "[scenario-screenshot] queued for build: position 2 of 2" in result.stderr, result.stderr
            result, _ = run("scenario-screenshot", "example", expected=1, POLICY_STOP="1")
            assert "[ios-agent] stopped after 45m00s" in result.stderr, result.stderr
            _, commands = run("scenario-screenshot", "example", expected=1, POLICY_BUILD_FAIL="1")
            assert not any(command[:3] == ["xcrun", "simctl", "install"] for command in commands)
            check_cancel("scenario-screenshot", "example")
        finally:
            shutil.rmtree(scratch, ignore_errors=True)
    check_cancel("xcode-build-agent.sh")
    check_cancel("xcode-test-agent.sh")

    for jobs in ("0", "-2", "x", "1.5", "01"):
        result = subprocess.run(["bash", "-c", 'source "$1"', "test", str(scripts / "lib/xcode-agent-throttle.sh")],
                                env=dict(base_env, XCODE_AGENT_JOBS=jobs), capture_output=True, text=True)
        assert result.returncode == 2 and "positive integer" in result.stderr, (jobs, result)

print(REPO + " agent policy passed (mock Apple tools only)")
