#!/usr/bin/env python3
"""Checks for the Duo PNG rejection that protects the upload folder."""
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zlib

spec = importlib.util.spec_from_file_location(
    "capture", Path(__file__).with_name("capture-app-store-screenshots.py"))
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def png(rows):
    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload)))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, len(rows), 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


class DuoCaptureTests(unittest.TestCase):
    def test_black_capture_is_rejected_with_each_png_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "black.png"
            for filter_type in range(5):
                with self.subTest(filter_type=filter_type):
                    path.write_bytes(png([bytes([filter_type, 0, 0, 0])]))
                    with self.assertRaisesRegex(SystemExit, "black screenshot"):
                        capture.reject_black_capture(path)

    def test_visible_capture_with_repeated_rows_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "visible.png"
            # The second row repeats the first through the PNG Up filter.
            path.write_bytes(png([bytes([0, 8, 13, 20]), bytes([2, 0, 0, 0])]))
            capture.reject_black_capture(path)


if __name__ == "__main__":
    unittest.main()
