# Capture Duo screenshots for the App Store

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

4. Inspect the PNGs in `ios/ASConnectScreenshots/<version>/duo/<locale>/`. Each locale has five outer-display and five inner-display images, using the same offline fixture and screen journey as the existing screenshots. The script requires 1398 x 2034 pixels for the folded outer display and 2853 x 2007 or 2007 x 2853 for the unfolded inner display. It preserves the captured app pixels without scaling or adding a phone frame. On this runtime, XCTest trims one pixel from each inner-display dimension. The exporter pads only that known 2006 x 2852 or 2852 x 2006 case with a black canvas edge to meet Apple's exact dimensions.
5. Check that all images show the expected content. Some Duo XCTest captures have been black even when the journey passed. The exporter rejects solid-black RGB captures before publication. Dimension and blank-image checks do not replace visual review. A hinge-angle warning is accepted only for the known runtime read failure; the exported images must still match the selected display dimensions.
6. Upload the reviewed images to the Duo screenshot section of the matching version and language in App Store Connect. Fastlane 2.240.1 does not recognize Duo dimensions, and the existing `upload_screenshots` lane does not stage the `duo` folder. Do not label Duo images as `APP_IPHONE_67`. Capture does not upload or submit a release.
7. Close the T3 Device panel session when finished.

The capture test checks geometry against the rendered window. On the unfolded Duo, XCTest reports portrait dimensions for the application even though the window is landscape. A PNG can store portrait pixel dimensions with orientation metadata for landscape display, so both Apple-approved inner-display dimensions are accepted.

The existing iPhone 3D renderer and iPad renderer do not process Duo captures. Duo uses native app screenshots so the listing shows the layout on each display.

Run the PNG rejection checks with `python3 scripts/test-capture-app-store-screenshots.py`.
