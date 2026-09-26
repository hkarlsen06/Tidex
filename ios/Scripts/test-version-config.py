#!/usr/bin/env python3
"""Run with python3 ios/Scripts/test-version-config.py from the repository root."""

import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("version_config", SCRIPTS / "validate-version-config.py")
version_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(version_config)


class VersionConfigTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.project_path = self.root / "Tidex.xcodeproj/project.pbxproj"
        self.project_path.parent.mkdir()
        shutil.copyfile(SCRIPTS.parent / "Tidex.xcodeproj/project.pbxproj", self.project_path)
        # Copy only the source plists referenced by the real project.
        for path in (
            "TidexApp/Supporting/Info.plist", "TidexShareExtension/Info.plist",
            "TidexSiriIntents/Info.plist", "TidexNotificationService/Info.plist",
            "TidexShiftWidget/Info.plist",
        ):
            destination = self.root / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SCRIPTS.parent / path, destination)

    def test_project_uses_shared_versions(self):
        self.assertEqual(version_config.validate(self.root), [])

    def test_rejects_original_app_override_in_both_configurations(self):
        project = self.project_path.read_text()
        marker = "\t\t\t\tPRODUCT_NAME = Tidex;"
        self.assertEqual(project.count(marker), 2)
        self.project_path.write_text(project.replace(
            marker, "\t\t\t\tMARKETING_VERSION = 2.7.0;\n" + marker,
        ))
        errors = version_config.validate(self.root)
        self.assertEqual(len(errors), 2)
        self.assertIn("TidexApp (Debug)", errors[0])
        self.assertIn("TidexApp (Release)", errors[1])

    def test_rejects_extension_overrides_including_conditional_settings(self):
        original = self.project_path.read_text()
        marker = "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";"
        for setting in (
            "MARKETING_VERSION", "CURRENT_PROJECT_VERSION",
            "INFOPLIST_KEY_CFBundleShortVersionString", "INFOPLIST_KEY_CFBundleVersion",
            '"MARKETING_VERSION[sdk=iphoneos*]"',
        ):
            with self.subTest(setting=setting):
                self.project_path.write_text(original.replace(
                    marker, f"\t\t\t\t{setting} = 1;\n" + marker, 1,
                ))
                errors = version_config.validate(self.root)
                self.assertEqual(len(errors), 1)
                self.assertIn("TidexShiftWidgetExtension (Debug)", errors[0])

    def test_shipping_targets_and_embedded_extensions_are_ios_only(self):
        project = json.loads(subprocess.check_output([
            "/usr/bin/plutil", "-convert", "json", "-o", "-", str(self.project_path),
        ]))
        objects = project["objects"]
        targets = [objects[target] for target in objects[project["rootObject"]]["targets"]]
        for target in targets:
            configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
            for configuration in configurations:
                settings = objects[configuration]["buildSettings"]
                self.assertEqual(settings.get("SDKROOT", "iphoneos"), "iphoneos", target["name"])

        app = next(target for target in targets if target["name"] == "TidexApp")
        embedded = {
            objects[objects[file]["fileRef"]]["path"]
            for phase in app["buildPhases"]
            if objects[phase]["isa"] == "PBXCopyFilesBuildPhase"
            for file in objects[phase]["files"]
        }
        self.assertEqual(embedded, {
            "TidexShiftWidgetExtension.appex", "TidexNotificationService.appex",
            "TidexShareExtension.appex", "TidexSiriIntents.appex",
        })

    def test_rejects_hardcoded_or_missing_plist_versions(self):
        path = self.root / "TidexShareExtension/Info.plist"
        original = plistlib.loads(path.read_bytes())
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            for value in ("2.7.0", None):
                with self.subTest(key=key, value=value):
                    info = original.copy()
                    if value is None:
                        del info[key]
                    else:
                        info[key] = value
                    path.write_bytes(plistlib.dumps(info))
                    errors = version_config.validate(self.root)
                    self.assertEqual(len(errors), 1)
                    self.assertIn(key, errors[0])


if __name__ == "__main__":
    unittest.main()
