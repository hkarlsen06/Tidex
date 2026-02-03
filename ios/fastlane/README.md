fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload App Store metadata (no binary or screenshots)

### ios generate_metadata

```sh
[bundle exec] fastlane ios generate_metadata
```

Generate metadata files without uploading

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload existing metadata files (no generation)

### ios validate_metadata

```sh
[bundle exec] fastlane ios validate_metadata
```

Validate metadata files (check lengths and required files)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
