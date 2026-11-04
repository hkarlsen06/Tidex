"""Run the watchdog's capacity checks against temporary cgroup files."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PaeoniaMemoryAlerts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cgroup = self.root / "cgroup" / "docker-container.scope"
        self.cgroup.mkdir(parents=True)
        for name, value in {
            "memory.current": "500",
            "memory.max": "1000",
            "memory.stat": "inactive_file 0\n",
        }.items():
            (self.cgroup / name).write_text(value)
        self.state = self.root / "alerts"
        self.state.write_text("")
        source = Path(__file__).with_name("one-s-watchdog.sh").read_text()
        block = "# Paeonia capacity:" + source.split("# Paeonia capacity:", 1)[1].split("# Tidex Convex", 1)[0]
        self.block = block.replace("/run/", f"{self.root}/").replace(
            "/sys/fs/cgroup/system.slice", str(self.root / "cgroup")
        )

    def check(self, hits, started="first"):
        (self.cgroup / "memory.events").write_text(f"max {hits}\noom 0\noom_kill 0\n")
        script = """
set -u
declare -a PROBLEMS=()
docker() {
  if [ "$1" = inspect ]; then printf 'container %s\\n' "$STARTED_AT"; fi
}
journalctl() { :; }
""" + self.block + "\nprintf 'PROBLEM:%s\\n' \"${PROBLEMS[@]:-}\"\n"
        result = subprocess.run(
            ["bash", "-c", script],
            env={**os.environ, "STATE": str(self.state), "STARTED_AT": started},
            text=True, capture_output=True, check=True,
        )
        self.assertEqual(result.stderr, "")
        return [line.removeprefix("PROBLEM:") for line in result.stdout.splitlines()
                if line.startswith("PROBLEM:") and line != "PROBLEM:"]

    def test_historical_hits_do_not_raise_a_current_incident(self):
        self.assertEqual(self.check(347), [])
        self.assertEqual(self.check(347), [])

    def test_new_hit_alerts_and_then_recovers(self):
        self.check(347)
        problems = self.check(348)
        self.assertEqual(len(problems), 1)
        self.assertIn("since the previous watchdog check", problems[0])
        self.assertNotIn("requests stalled", problems[0])
        self.assertEqual(self.check(348), [])

    def test_continuing_hits_keep_the_incident_active(self):
        self.check(0)
        self.assertTrue(self.check(1))
        self.assertTrue(self.check(2))

    def test_restart_uses_a_new_baseline_even_if_counter_is_larger(self):
        self.check(1)
        self.assertEqual(self.check(5, started="second"), [])
        self.assertTrue(self.check(6, started="second"))

    def test_counter_reset_does_not_alert_but_subsequent_hit_does(self):
        self.check(347)
        self.assertEqual(self.check(0), [])
        self.assertTrue(self.check(1))

    def test_corrupt_saved_counter_is_replaced_by_a_baseline(self):
        (self.root / "supabase-watchdog-paeonia-memory-events.state").write_text(
            "container/first invalid\n"
        )
        self.assertEqual(self.check(347), [])
        self.assertTrue(self.check(348))

    def test_unreadable_counter_raises_a_monitoring_problem(self):
        problems = self.check("invalid")
        self.assertEqual(len(problems), 1)
        self.assertIn("could not read", problems[0])

    def test_sustained_capacity_alert_is_preserved(self):
        self.state.write_text(
            "paeonia: convex-backend-1 memory at or above 70% of its mem_limit for at least 10 minutes\n"
        )
        (self.cgroup / "memory.current").write_text("800")
        self.assertEqual(self.check(347), self.state.read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
