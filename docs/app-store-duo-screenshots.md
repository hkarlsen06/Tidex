# Build Duo screenshots for the App Store

Apple enables the Duo badge when you submit Duo screenshots in App Store Connect. See [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/) and [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

1. Open an existing iPhone Duo simulator with T3 `device_list` and `device_open`. Keep exclusive ownership for the capture run. Do not create a simulator or download a runtime.
2. Install a current simulator build if Tidex is missing. Use `scripts/xcode-build-agent.sh` to build and `simctl install` to install. The capture workflow builds and runs the screenshot UI test itself.
3. Run this command from the repository root, using the UUID and exact executable path returned by `device_open`:

```sh
bun run screenshots --duo-only \
  --duo <simulator-uuid> \
  --duo-agent-device <path-returned-by-device_open> \
  --locales en-US no
```

Omit `--locales` to capture every App Store locale. Omit `--duo-only` to run the existing iPhone and iPad workflow after Duo. The existing iPhone and iPad capture defaults require simulator models that are no longer installed on this Mac and create simulator copies. Use the Duo-only command above for this task.

4. Inspect the finished artwork in `ios/ASConnectScreenshots/<version>/3d-duo/<locale>/`. The five-image story starts with earnings on the closed Duo, unfolds for the calendar, adding a shift and the pay breakdown, then closes for progress over time. Every finished image uses the same 2853 x 2007 landscape canvas, with filenames `Duo-01.png` through `Duo-05.png`. The frames follow the actual open or closed capture proportions. The images reuse the iPhone renderer's Poppins headings, cyan emphasis, gradient, lighting and 3D metal frames. English and Norwegian have Duo-specific copy; other locales retain the existing translated feature copy in the new story order. All ten raw captures remain in `duo/<locale>/`.
5. Check that all images show the expected content. Some Duo XCTest captures have been black even when the journey passed. The exporter rejects solid-black RGB captures before publication. Dimension and blank-image checks do not replace visual review. A hinge-angle warning is accepted only for the known runtime read failure; the exported images must still match the selected display dimensions.
6. Preview the upload with `bun run app-store screenshots --device duo --locales en-US,no`. Add `--replace` to replace the older ten-image gallery, then `--apply` to upload to an editable version. The asc uploader uses `APP_IPHONE_DUO`, validates the five ordered story files, and preserves the iPhone and iPad sets. Five is the current story length; Apple's limit is ten images in the Duo group. See [App Store Connect](../ios/app-store/README.md) for setup and version selection. Capture does not upload or submit a release.
7. Close the T3 Device panel session when finished.

The capture test checks geometry against the rendered window. On the unfolded Duo, XCTest reports portrait dimensions for the application even though the window is landscape. A PNG can store portrait pixel dimensions with orientation metadata for landscape display, so both Apple-approved inner-display dimensions are accepted.

To rebuild artwork from existing captures without launching a simulator, run:

```sh
bun run screenshots:duo
```

To render selected locales or another version, pass the capture and output folders:

```sh
bun run screenshots:duo ios/ASConnectScreenshots/3.1.1/duo ios/ASConnectScreenshots/3.1.2/3d-duo en-US no
```

`scripts/assets/app-store/tidex-duo-3d.json` extends `tidex-3d.json` for the shared brand styling and defines the Duo sequence, copy and per-phone captures and frames. `scripts/render-duo-screenshots.mjs` stages the whole story beside the destination, removes stale artwork for the selected locales, then replaces the finished directory with rollback if publication fails. Unselected locales are preserved. Install the project Playwright browser with `bunx playwright install chromium` if rendering reports a missing executable.

The raw exporter pads only the known 2006 x 2852 or 2852 x 2006 XCTest inner-display crop with a one-pixel canvas edge. The 3D renderer preserves the captured layout and adds no traditional iPhone Dynamic Island over the Duo UI.

Run the PNG rejection checks with `python3 scripts/test-capture-app-store-screenshots.py`.
