#!/usr/bin/env python3
"""Check result classification without building or running iOS tests."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


wrapper = Path(__file__).with_name("xcode-test-agent.sh").read_text()
parser = wrapper.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]


def issue(message, kind="TestIssueSummary"):
    return {
        "_type": {"_name": kind},
        "issueType": {"_value": "Uncategorized"},
        "message": {"_value": message},
        "testCaseName": {"_value": "ExampleTests.testExample()"},
    }


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
    ], check=True, stdout=subprocess.DEVNULL)
    result = json.loads(output.read_text())
    assert result["warnings"] == ["ExampleTests.testExample(): audio warning"]
    assert result["test_failures"] == ["ExampleTests.testExample(): assertion failed"]
    assert set(result["errors"]) == {
        "ExampleTests.testExample(): assertion failed",
        "ExampleTests.testExample(): build error",
    }
    assert result["tests_count"] == 2 and result["tests_failed"] == 1

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
    ], check=True, capture_output=True, text=True).stdout
    result = json.loads(output.read_text())
    assert result["errors"] == ["Unable to boot the Simulator.", "launchd failed to respond."]
    assert text_output.index("NO TESTS RAN") < text_output.index("ERRORS:")

    # A failure with nothing parseable prints the end of the log instead.
    log.write_text("Something went wrong\n** BUILD FAILED **\n")
    text_output = subprocess.run([
        sys.executable, "-c", parser, "text", "FAILURE", str(source),
        str(output), str(log), "0", "simulator", "App", "result.xcresult", "0",
    ], check=True, capture_output=True, text=True).stdout
    assert "Last lines of the xcodebuild log" in text_output
    assert "** BUILD FAILED **" in text_output

print("Result classification passed")
