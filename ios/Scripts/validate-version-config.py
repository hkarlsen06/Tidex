#!/usr/bin/env python3
"""Keep every app and extension on the shared xcconfig version settings."""

import json
from pathlib import Path
import plistlib
import subprocess
import sys


def validate(root):
    project = json.loads(subprocess.check_output([
        "/usr/bin/plutil", "-convert", "json", "-o", "-",
        str(root / "Tidex.xcodeproj/project.pbxproj"),
    ]))
    objects = project["objects"]
    errors = []
    version_keys = {
        "CFBundleShortVersionString": "MARKETING_VERSION",
        "CFBundleVersion": "CURRENT_PROJECT_VERSION",
    }
    managed_settings = set(version_keys.values()) | {
        f"INFOPLIST_KEY_{key}" for key in version_keys
    }
    checked_plists = set()

    for owner in objects.values():
        if owner.get("isa") not in ("PBXProject", "PBXNativeTarget"):
            continue
        configurations = objects[owner["buildConfigurationList"]]["buildConfigurations"]
        for configuration_id in configurations:
            configuration = objects[configuration_id]
            label = f"{owner.get('name', 'Project')} ({configuration['name']})"
            settings = configuration["buildSettings"]
            for key, value in settings.items():
                if key.split("[", 1)[0] in managed_settings and value != "$(inherited)":
                    errors.append(
                        f"{label}: remove {key} = {value}; versions must inherit "
                        "from Version.xcconfig and BuildNumber.xcconfig."
                    )

            plist_path = settings.get("INFOPLIST_FILE")
            if not plist_path or plist_path in checked_plists:
                continue
            checked_plists.add(plist_path)
            with (root / plist_path).open("rb") as source:
                info = plistlib.load(source)
            for key, setting in version_keys.items():
                expected = f"$({setting})"
                if info.get(key) != expected:
                    errors.append(f"{plist_path}: {key} must be {expected}.")

    return errors


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    try:
        errors = validate(root)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: Unable to validate shared version configuration: {error}")
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    sys.exit(bool(errors))
