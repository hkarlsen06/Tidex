#!/usr/bin/env python3
"""Checks that scripts/motion-check flags the motion problems an agent has to act on."""
import contextlib
import importlib.machinery
import importlib.util
import io
import math
from pathlib import Path
import random
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

SCRIPT = Path(__file__).with_name("motion-check")
loader = importlib.machinery.SourceFileLoader("motion_check", str(SCRIPT))
spec = importlib.util.spec_from_loader("motion_check", loader)
motion = importlib.util.module_from_spec(spec)
loader.exec_module(motion)

FRAME = 1 / 60
CLEAN = "snaps=0 jumps=0 jitter=0"

# Recorded on a simulator from the calendar's month slide: a second month change arrives while
# the cards still slide in from the first.
INTERRUPTED_MONTH_CHANGE = """\
month-card	99.000000	0.000000	d
month-card	100.000000	0.000000	d
month-card	100.000000	60.000000	d
month-card	100.000000	60.000000	d
month-card	100.000000	60.000000	a
month-card	100.000000	60.000000	a
month-card	100.483333	53.973608	a
month-card	100.544693	28.631805	a
month-card	100.566666	20.352130	a
month-card	100.583333	15.518996	a
month-card	100.621304	7.873983	a
month-card	100.650000	4.097052	a
month-card	100.650000	0.000000	d
month-card	100.650000	60.000000	d
month-card	100.650000	64.097052	a
month-card	100.650000	60.000000	a
month-card	100.850000	57.206110	a
month-card	100.866666	52.729719	a
month-card	100.883333	44.312443	a
month-card	100.900000	38.399589	a
month-card	100.916666	29.949444	a
month-card	100.933333	23.689119	a
month-card	100.950000	18.309880	a
month-card	100.966666	13.836040	a
month-card	100.983333	10.216157	a
month-card	101.000000	7.358219	a
month-card	101.016666	5.153156	a
month-card	101.033333	3.489834	a
month-card	101.050000	2.263969	a
month-card	101.066666	1.382847	a
month-card	101.083333	0.767244	a
month-card	101.100000	0.351573	a
month-card	101.116666	0.127073	a
month-card	101.133333	-0.080131	a
month-card	101.150000	-0.156423	a
month-card	101.166666	-0.209795	a
month-card	101.183333	-0.218023	a
month-card	101.200000	-0.207024	a
month-card	101.216666	-0.185578	a
month-card	101.233333	-0.159577	a
month-card	101.250000	-0.132799	a
month-card	101.266666	-0.107507	a
month-card	101.283333	-0.084919	a
month-card	101.300000	-0.065550	a
month-card	101.316666	-0.049468	a
month-card	101.333333	-0.038842	a
month-card	101.350000	-0.026232	a
month-card	101.366666	-0.019749	a
month-card	101.383333	-0.012392	a
month-card	101.400000	-0.008782	a
month-card	101.416666	-0.004875	a
month-card	101.433333	-0.002685	a
month-card	101.450000	-0.001209	a
month-card	101.466666	-0.000258	a
month-card	101.483333	0.000317	a
month-card	101.500000	0.000630	a
month-card	101.516666	0.000767	a
month-card	101.533333	0.000792	a
month-card	101.550000	0.000749	a
month-card	101.566666	0.000000	a
"""

# Recorded on a simulator from the chat reply swipe: the finger lets go while it still moves.
REPLY_SWIPE_RELEASE = """\
reply-swipe	100.000000	0.000000	a
reply-swipe	119.683334	21.333333	d
reply-swipe	119.700000	26.000000	d
reply-swipe	119.716667	30.333333	d
reply-swipe	119.733334	34.666667	d
reply-swipe	119.766667	39.000000	d
reply-swipe	119.766667	43.333333	d
reply-swipe	119.783334	47.333333	d
reply-swipe	119.800000	51.000000	d
reply-swipe	119.816667	54.333333	d
reply-swipe	119.833334	57.333333	d
reply-swipe	119.850000	57.333333	a
reply-swipe	119.883334	48.781034	a
reply-swipe	119.900000	40.868842	a
reply-swipe	119.916667	33.498393	a
reply-swipe	119.933334	26.669468	a
reply-swipe	119.950000	20.412249	a
reply-swipe	119.966667	14.779336	a
reply-swipe	119.983334	9.847059	a
reply-swipe	120.000000	5.721545	a
reply-swipe	120.016667	2.551244	a
reply-swipe	120.033334	0.549398	a
reply-swipe	120.050000	0.000000	a
"""


def frames(seconds, start=0.0):
    return [start + i * FRAME for i in range(round(seconds / FRAME) + 1)]


def tsv(name, points, source="a"):
    return "".join(f"{name}\t{t:.6f}\t{v:.6f}\t{source}\n" for t, v in points)


def ramp(start=10.0, seconds=1.0, low=0.0, high=100.0):
    times = frames(seconds, start)
    return [(t, low + (high - low) * i / (len(times) - 1)) for i, t in enumerate(times)]


def spring(damping, response=0.5, seconds=2.0, start=10.0):
    """Unit step response of a spring released from rest, like SwiftUI's .spring."""
    omega = 2 * math.pi / response
    damped = omega * math.sqrt(1 - damping ** 2)
    points = []
    for t in frames(seconds, start):
        x = t - start
        decay = math.exp(-damping * omega * x)
        value = 1 - decay * (math.cos(damped * x)
                             + damping / math.sqrt(1 - damping ** 2) * math.sin(damped * x))
        points.append((t, value))
    points[-1] = (points[-1][0], 1.0)
    return points


def ease_out(start, seconds, first, last, until=1.0):
    times = frames(seconds, start)
    count = len(times) - 1
    return [(t, first + (last - first) * (1 - (1 - i / count) ** 3))
            for i, t in enumerate(times) if i / count <= until]


def report(text, *options):
    with tempfile.TemporaryDirectory() as directory:
        log = Path(directory) / "motion-probe.tsv"
        log.write_text(text)
        out = io.StringIO()
        code = motion.main(["report", "--log", str(log), *options], out=out)
    return code, out.getvalue()


def summary(output):
    return output.strip().splitlines()[-1]


class AnalysisTests(unittest.TestCase):
    def test_linear_ramp_passes(self):
        code, output = report(tsv("bar", ramp()))
        self.assertEqual(code, 0, output)
        self.assertEqual(summary(output),
                         f"SUMMARY: PASS episodes=1 static=0 {CLEAN} stalls=0")
        self.assertIn("bar  t=0.000s  0 -> 100", output)

    def test_underdamped_spring_reports_overshoot_and_reversal(self):
        code, output = report(tsv("card", spring(0.5)))
        self.assertEqual(code, 0, output)
        overshoot = float(re.search(r"overshoot=([\d.]+)%", output).group(1))
        reversals = int(re.search(r"reversals=(\d+)", output).group(1))
        self.assertAlmostEqual(overshoot, 16.3, delta=0.5)
        self.assertGreaterEqual(reversals, 1)

    def test_fast_springs_and_curves_from_rest_are_not_breaks(self):
        for points in (spring(0.5, response=0.15), spring(0.85, response=0.2),
                       spring(0.6, response=0.2), ease_out(10.0, 0.18, 80, 0)):
            code, output = report(tsv("card", [(9.0, points[0][1])] + points))
            self.assertEqual(code, 0, output)
            self.assertIn(CLEAN, summary(output))

    def test_spring_tail_does_not_count_toward_settling(self):
        _, output = report(tsv("card", spring(0.85, response=0.35)))
        settled = float(re.search(r"settled=([\d.]+)s", output).group(1))
        duration = float(re.search(r"duration=([\d.]+)s", output).group(1))
        self.assertLess(settled, 0.5)
        self.assertGreater(duration, 1.5)

    def test_snap_back_mid_flight_is_one_snap(self):
        first = ease_out(10.0, 0.47, 60, 0, until=0.5)
        second = ease_out(first[-1][0] + FRAME, 0.47, 60, 0)
        text = tsv("month-card", [(9.0, 60.0)] + first + second)
        code, output = report(text)
        self.assertEqual(code, 1, output)
        self.assertIn("snaps=1 jumps=0 jitter=0", summary(output))
        self.assertEqual(output.count("  SNAP at"), 1)
        code, output = report(text, "--allow", "month-card=1")
        self.assertEqual(code, 0, output)
        self.assertIn("unexplained=0", summary(output))

    def test_snap_a_frame_before_its_animation_is_one_break(self):
        slide = [(11.0 + (i + 1) * FRAME, 60.0 - i - 1) for i in range(20)]
        text = tsv("card", [(10.0, 0.0), (11.0, 60.0)], "d") + tsv("card", slide)
        code, output = report(text)
        self.assertEqual(code, 1, output)
        self.assertIn("snaps=1 jumps=0 jitter=0", summary(output))
        code, output = report(text, "--allow", "card=1")
        self.assertEqual(code, 0, output)

    def test_release_at_the_finger_speed_that_then_speeds_up_passes(self):
        drag = [(10.0 + i * FRAME, float(i)) for i in range(6)]
        position, release = 5.0, []
        for i, step in enumerate([1, 1.5, 2, 2.5, 3, 3.5, 4]):
            position += step
            release.append((drag[-1][0] + (i + 1) * FRAME, position))
        code, output = report(tsv("sheet", drag, "d") + tsv("sheet", release))
        self.assertEqual(code, 0, output)
        self.assertIn(CLEAN, summary(output))

    def test_long_stall_in_the_middle_of_a_motion_is_a_stall(self):
        points = [(10.0 + i * FRAME, float(i)) for i in list(range(11)) + list(range(28, 34))]
        code, output = report(tsv("bar", points))
        self.assertEqual(code, 0, output)
        self.assertIn("bar  t=0.000s  0 -> 33", output)
        self.assertEqual(summary(output), f"SUMMARY: PASS episodes=1 static=0 {CLEAN} stalls=1")

    def test_one_frame_speed_spike_is_one_jump(self):
        values = [0, 5, 10, 15, 20, 35, 40, 45, 50, 55]
        points = [(10.0 + i * FRAME, float(value)) for i, value in enumerate(values)]
        code, output = report(tsv("card", points))
        self.assertEqual(code, 1, output)
        self.assertIn("snaps=0 jumps=1 jitter=0", summary(output))

    def test_bad_expectations_are_usage_errors(self):
        for options in (["--allow", "card=nan"], ["--allow", "card=-1"], ["--allow", "card=1.5"],
                        ["--end", "card=inf"], ["--max-duration", "card=-2"]):
            with self.assertRaises(SystemExit) as raised, \
                    contextlib.redirect_stderr(io.StringIO()):
                report(tsv("card", ramp()), *options)
            self.assertEqual(raised.exception.code, 2, options)

    def test_value_set_with_no_animation_is_a_snap(self):
        code, output = report(tsv("card", [(10.0, 0.0)]) + tsv("card", [(11.0, 60.0)], "d"))
        self.assertEqual(code, 1, output)
        self.assertIn("card  t=1.000s  0 -> 60  SNAP: set with no animation", output)
        self.assertIn("snaps=1", summary(output))

    def test_finger_that_still_moves_at_release_is_one_jump(self):
        drag = [(10.0 + i * FRAME, 3.0 * i) for i in range(21)]
        decay = ease_out(drag[-1][0], 0.4, 60, 0)[1:]
        code, output = report(tsv("reply-swipe", drag, "d") + tsv("reply-swipe", decay))
        self.assertEqual(code, 1, output)
        self.assertIn("snaps=0 jumps=1 jitter=0", summary(output))
        self.assertIn("when the animation took over from the finger", output)

    def test_finger_that_rests_before_release_is_not_a_jump(self):
        drag = [(10.0 + i * FRAME, 3.0 * i) for i in range(21)]
        hold = [(drag[-1][0] + (i + 1) * FRAME, 60.0 + 0.01 * (i + 1)) for i in range(6)]
        decay = ease_out(hold[-1][0], 0.4, hold[-1][1], 0)[1:]
        code, output = report(tsv("reply-swipe", drag + hold, "d") + tsv("reply-swipe", decay))
        self.assertEqual(code, 0, output)
        self.assertIn(CLEAN, summary(output))

    def test_uneven_finger_is_not_a_break(self):
        noise = random.Random(3)
        position, drag = 0.0, []
        for i in range(60):
            position += noise.uniform(0.5, 7.0)
            drag.append((10.0 + i * FRAME, position))
        code, output = report(tsv("sheet", drag, "d"))
        self.assertEqual(code, 0, output)
        self.assertIn(CLEAN, summary(output))

    def test_speed_that_alternates_every_frame_is_jitter(self):
        steps = [6, 6, 6, 3, 9, 3, 9, 3, 9, 6, 6, 6, 6]
        position, points = 0.0, [(10.0, 0.0)]
        for i, step in enumerate(steps):
            position += step
            points.append((10.0 + (i + 1) * FRAME, position))
        code, output = report(tsv("card", points))
        self.assertEqual(code, 1, output)
        self.assertIn("snaps=0 jumps=0 jitter=1", summary(output))

    def test_missing_frames_are_a_stall_and_not_a_failure(self):
        points = ramp()
        del points[30:33]
        code, output = report(tsv("bar", points))
        self.assertEqual(code, 0, output)
        self.assertIn(f"{CLEAN} stalls=1", summary(output))
        self.assertIn("dropped=3", output)
        self.assertIn("(4 frames)", output)

    def test_identical_copies_under_one_name_match_a_single_copy(self):
        series = spring(0.5)
        copies = [point for point in series for _ in range(40)]
        _, single = report(tsv("card", series))
        _, merged = report(tsv("card", copies))
        self.assertEqual(merged, single)

    def test_last_value_of_a_frame_wins(self):
        slide = ease_out(10.0, 0.47, 60, 0, until=0.5)
        again = slide[-1][0] + FRAME
        burst = tsv("month-card", [(again, 0.0), (again, 60.0)], "d") \
            + tsv("month-card", [(again, 64.0), (again, 60.0)])
        rest = ease_out(again, 0.47, 60, 0)[1:]
        _, output = report(tsv("month-card", [(9.0, 60.0)] + slide) + burst + tsv("month-card", rest))
        self.assertEqual(output.count("SNAP"), 1)
        self.assertRegex(output, r"SNAP at \+0\.\d+s: value [\d.]+ -> 60 in one frame")

    def test_idle_pause_splits_episodes_and_a_resting_value_is_static(self):
        text = tsv("bar", ramp(10.0)) + tsv("bar", ramp(12.0, low=100, high=0)) \
            + tsv("bar", [(15.0, 0.0), (15.1, 0.00001)])
        code, output = report(text)
        self.assertEqual(code, 0, output)
        self.assertEqual(summary(output),
                         f"SUMMARY: PASS episodes=2 static=1 {CLEAN} stalls=0")

    def test_name_prefix_limits_the_report(self):
        text = tsv("month-card", ramp(10.0)) + tsv("payroll-progress", ramp(11.0, low=0, high=40))
        _, output = report(text, "--name", "payroll")
        self.assertIn("payroll-progress  t=1.000s", output)
        self.assertNotIn("month-card", output)

    def test_end_expectation(self):
        text = tsv("bar", ramp())
        code, output = report(text, "--end", "bar=100.2")
        self.assertEqual(code, 0, output)
        self.assertIn("expectations_failed=0", summary(output))
        code, output = report(text, "--end", "bar=99")
        self.assertEqual(code, 1, output)
        self.assertIn("expectations_failed=1", summary(output))
        code, output = report(text, "--end", "missing=0")
        self.assertEqual(code, 1, output)
        self.assertIn("missing should end at 0", output)

    def test_max_duration_expectation_uses_the_settling_time(self):
        text = tsv("card", spring(0.85, response=0.35))
        code, output = report(text, "--max-duration", "card=0.5")
        self.assertEqual(code, 0, output)
        code, output = report(text, "--max-duration", "card=0.1")
        self.assertEqual(code, 1, output)
        self.assertIn("expectations_failed=1", summary(output))

    def test_recorded_interrupted_month_change(self):
        code, output = report(INTERRUPTED_MONTH_CHANGE)
        self.assertEqual(code, 1, output)
        self.assertIn("month-card  t=1.000s  0 -> 60  SNAP: set with no animation", output)
        self.assertIn("SNAP at +0.15s: value 7.87 -> 60 in one frame", output)
        # The uneven frames follow a 200 ms stall, so they are a hint and not a failure.
        self.assertEqual(output.count("PACING at"), 1)
        self.assertNotIn("JITTER at", output)
        self.assertIn("snaps=2 jumps=0 jitter=0", summary(output))

    def test_recorded_reply_swipe_release(self):
        code, output = report(REPLY_SWIPE_RELEASE)
        self.assertEqual(code, 1, output)
        self.assertIn("SNAP at +0.00s: value 0 -> 21.33 in one frame", output)
        self.assertIn("JUMP at +0.17s: speed 180/s -> -257/s when the animation took over", output)
        self.assertIn("snaps=1 jumps=1 jitter=0", summary(output))

    def test_log_without_the_source_column_still_reads(self):
        code, output = report("".join(f"bar\t{t:.6f}\t{v:.6f}\n" for t, v in ramp()))
        self.assertEqual(code, 0, output)
        self.assertIn("bar  t=0.000s  0 -> 100", output)

    def test_empty_log_fails_with_launch_hint(self):
        code, output = report("garbage\n\n")
        self.assertEqual(code, 1, output)
        self.assertIn("Skipped 1 malformed line.", output)
        self.assertIn("-motion-probe", output)
        self.assertIn(".motionProbe(", output)
        self.assertEqual(summary(output), f"SUMMARY: FAIL episodes=0 static=0 {CLEAN} stalls=0")

    def test_missing_log_fails_with_launch_hint(self):
        out = io.StringIO()
        code = motion.main(["report", "--log", "/nonexistent/motion-probe.tsv"], out=out)
        self.assertEqual(code, 1)
        self.assertIn("-motion-probe", out.getvalue())

    def test_help_explains_the_loop(self):
        result = subprocess.run([str(SCRIPT), "--help"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("motion-check report", result.stdout)


def read_png(path):
    data = path.read_bytes()
    width, height = struct.unpack(">II", data[16:24])
    position, idat = 8, b""
    while position < len(data):
        length = struct.unpack(">I", data[position:position + 4])[0]
        if data[position + 4:position + 8] == b"IDAT":
            idat += data[position + 8:position + 8 + length]
        position += 12 + length
    raw = zlib.decompress(idat)
    stride = width * 3 + 1
    rows = [raw[y * stride + 1:(y + 1) * stride] for y in range(height)]
    return width, height, rows


@unittest.skipUnless(shutil.which("ffmpeg"), "ffmpeg is not installed")
class SlitScanTests(unittest.TestCase):
    def video(self, directory, seconds=1):
        path = Path(directory) / "box.mp4"
        subprocess.run(
            ["ffmpeg", "-v", "error",
             "-f", "lavfi", "-i", f"color=c=black:s=64x48:d={seconds}:r=30",
             "-f", "lavfi", "-i", "color=c=white:s=8x16:r=30",
             "-filter_complex", "[0][1]overlay=x='t*40':y=16:shortest=1",
             "-c:v", "mpeg4", "-q:v", "2", str(path)],
            check=True)
        return path

    def test_row_scan_stacks_one_row_per_frame_and_shows_the_box_moving(self):
        with tempfile.TemporaryDirectory() as directory:
            video = self.video(directory)
            out = io.StringIO()
            code = motion.main(["report", "--no-log", "--video", str(video), "--row", "0.5"], out=out)
            self.assertEqual(code, 0, out.getvalue())
            image = Path(directory) / "box-slitscan.png"
            self.assertIn(str(image), out.getvalue())
            self.assertIn("SUMMARY: PASS image-only", out.getvalue())
            width, height, rows = read_png(image)
            self.assertEqual((width, height), (64, 60 * 4))

            def box_x(row):
                bright = [x for x in range(width) if row[x * 3] > 128]
                return sum(bright) / len(bright)
            self.assertGreater(box_x(rows[-1]), box_x(rows[0]) + 20)

    def test_column_scan_places_frames_left_to_right(self):
        with tempfile.TemporaryDirectory() as directory:
            video = self.video(directory)
            out = io.StringIO()
            code = motion.main(["report", "--no-log", "--video", str(video), "--column", "0.5",
                                "--from", "0.25", "--seconds", "0.5"], out=out)
            self.assertEqual(code, 0, out.getvalue())
            width, height, _ = read_png(Path(directory) / "box-slitscan.png")
            # ffmpeg rounds the window edges to whole frames, so 0.5 s gives 29 to 31 frames.
            self.assertEqual(height, 48)
            self.assertEqual(width % 4, 0)
            self.assertAlmostEqual(width / 4, 30, delta=1)

    def test_video_without_a_log_still_makes_the_image_and_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            video = self.video(directory)
            out = io.StringIO()
            code = motion.main(["report", "--log", str(Path(directory) / "none.tsv"),
                                "--video", str(video), "--row", "0.5"], out=out)
            self.assertEqual(code, 1, out.getvalue())
            self.assertTrue((Path(directory) / "box-slitscan.png").is_file())

    def test_scan_picks_the_stretch_where_the_screen_changed(self):
        with tempfile.TemporaryDirectory() as directory:
            video = Path(directory) / "box.mp4"
            # Like a simulator recording: frames exist only while the box moves, from 6 s to 7 s.
            subprocess.run(
                ["ffmpeg", "-v", "error",
                 "-f", "lavfi", "-i", "color=c=black:s=64x48:d=14:r=30",
                 "-f", "lavfi", "-i", "color=c=white:s=8x16:r=30",
                 "-filter_complex",
                 "[0][1]overlay=x='if(between(t,6,7),(t-6)*40,if(lt(t,6),0,40))':y=16:shortest=1,"
                 "mpdecimate",
                 "-fps_mode", "vfr", "-c:v", "mpeg4", "-q:v", "2", str(video)],
                check=True)
            out = io.StringIO()
            code = motion.main(["report", "--no-log", "--video", str(video), "--row", "0.5"], out=out)
            self.assertEqual(code, 0, out.getvalue())
            self.assertIn("Showing 5.97s to 7.10s", out.getvalue())
            _, height, _ = read_png(Path(directory) / "box-slitscan.png")
            # About one second of motion at 60 fps, out of 14 seconds of video.
            self.assertAlmostEqual(height / 4, 60, delta=10)

    def test_long_video_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            video = self.video(directory, seconds=11)
            out = io.StringIO()
            code = motion.main(["report", "--no-log", "--video", str(video), "--row", "0.5"], out=out)
            self.assertEqual(code, 2, out.getvalue())
            self.assertIn("--from and --seconds", out.getvalue())


if __name__ == "__main__":
    unittest.main()
