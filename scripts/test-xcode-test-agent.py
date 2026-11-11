#!/usr/bin/env python3
"""Check result classification without building or running iOS tests."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


wrapper = Path(__file__).with_name("xcode-test-agent.sh").read_text()
parser = wrapper.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]

# The two phases must build and run products for the same platform.
destination_selection = wrapper.split("BUILD_DESTINATION=", 1)[1].split("esac", 1)[0]
for destination, expected in [
    ("", "generic/platform=iOS Simulator"),
    ("platform=iOS Simulator,id=simulator", "generic/platform=iOS Simulator"),
    ("platform=iOS,id=phone", "generic/platform=iOS"),
]:
    result = subprocess.check_output([
        "bash", "-c",
        'DESTINATION="$1"\nSAFE_SELECTION=1\nUNSAFE_SELECTION=0\nBUILD_DESTINATION=' + destination_selection
        + 'esac\nprintf "%s" "$BUILD_DESTINATION"', "test", destination,
    ], text=True)
    assert result == expected, (destination, result, expected)


def issue(message, kind="TestIssueSummary"):
    return {
        "_type": {"_name": kind},
        "issueType": {"_value": "Uncategorized"},
        "message": {"_value": message},
        "testCaseName": {"_value": "ExampleTests.testExample()"},
    }


# queued, compiled, tested, simulator
timings = ["312", "95", "140", "Shared iPhone 2"]


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / "result.json"
    output = root / "parsed.json"
    log = root / "test.log"
    source.write_text(json.dumps({
        "issues": {
            "testWarningSummaries": {"_values": [issue("audio warning")]},
            "testFailureSummaries": {"_values": [
                issue("assertion failed", "TestFailureIssueSummary")
            ]},
            "errorSummaries": {"_values": [issue("build error")]},
        },
        "metrics": {
            "testsCount": {"_value": "2"},
            "testsFailedCount": {"_value": "1"},
        },
    }))
    log.write_text("")
    subprocess.run([
        sys.executable, "-c", parser, "json", "FAILURE", str(source),
        str(output), str(log), "1", "simulator", "App", "result.xcresult", "0",
        *timings,
    ], check=True, stdout=subprocess.DEVNULL)
    result = json.loads(output.read_text())
    assert result["warnings"] == ["ExampleTests.testExample(): audio warning"]
    assert result["test_failures"] == ["ExampleTests.testExample(): assertion failed"]
    assert set(result["errors"]) == {
        "ExampleTests.testExample(): assertion failed",
        "ExampleTests.testExample(): build error",
    }
    assert result["tests_count"] == 2 and result["tests_failed"] == 1
    assert (result["queued"], result["compiled"], result["tested"], result["simulator"]) == (
        312, 95, 140, "Shared iPhone 2")

    # A run that never started testing: no result bundle, only the log.
    source.write_text("")
    log.write_text(
        "2026-10-14 xcodebuild[1:2] Writing error result bundle\n"
        "Testing failed:\n"
        "\tUnable to boot the Simulator.\n"
        "\tlaunchd failed to respond.\n"
        "\n"
        "** TEST FAILED **\n"
    )
    text_output = subprocess.run([
        sys.executable, "-c", parser, "text", "FAILURE", str(source),
        str(output), str(log), "0", "simulator", "App", "result.xcresult", "0",
        *timings,
    ], check=True, capture_output=True, text=True).stdout
    result = json.loads(output.read_text())
    assert result["errors"] == ["Unable to boot the Simulator.", "launchd failed to respond."]
    assert text_output.index("NO TESTS RAN") < text_output.index("ERRORS:")

    # A failure with nothing parseable prints the end of the log instead.
    log.write_text("Something went wrong\n** BUILD FAILED **\n")
    text_output = subprocess.run([
        sys.executable, "-c", parser, "text", "FAILURE", str(source),
        str(output), str(log), "0", "simulator", "App", "result.xcresult", "0",
        *timings,
    ], check=True, capture_output=True, text=True).stdout
    assert "Last lines of the xcodebuild log" in text_output
    assert "** BUILD FAILED **" in text_output
    assert text_output.splitlines()[-1] == (
        'SUMMARY: FAILURE queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"')

print("Result classification passed")
