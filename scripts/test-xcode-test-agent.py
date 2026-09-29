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

print("Result classification passed")
