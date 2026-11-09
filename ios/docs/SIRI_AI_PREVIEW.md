# Siri AI developer preview

Apple opened the Siri AI developer preview on 2026-11-03. In the preview, Siri's model can call an app's intents as tools and fill their parameters from what the person said. Tidex adopts it behind a build switch that is off by default, so a normal build contains none of it.

## What Apple allows

- The API is in the iOS 27.3 SDK, which only the Xcode 27.3 beta has. The release Xcode cannot compile it.
- Siri AI runs on an iPhone with iOS 27.3 and Apple Intelligence. It runs in development builds and for internal TestFlight testers. External testers and App Store users do not get it.
- Apple's announcement says App Store submission for Siri AI integrations opens in the spring.
- Supported languages are English, French, Japanese, Korean, Portuguese and Spanish. Apple lists Norwegian as coming soon.
- Apple may change the API and Siri's behavior during the preview.

Apple's pages are the [announcement](https://developer.apple.com/news/?id=gdk2umrf), the [preview overview](https://developer.apple.com/documentation/appintents/siri-ai-developer-preview), [`ToolIntent`](https://developer.apple.com/documentation/appintents/toolintent), [custom actions and content](https://developer.apple.com/documentation/appintents/bringing-custom-actions-and-content-to-siri) and [app skills](https://developer.apple.com/documentation/appintents/orchestrating-complex-actions-with-app-skills). The Xcode 27.3 beta also ships Apple's own agent guidance as plain text. Read it before changing tools or skills:

```bash
ls /Applications/Xcode-27.3.0-beta.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/siri-*
```

## What the preview adds

All of it is in `ios/TidexApp/Features/Assistant/SiriAIPreview/`.

`AssistantToolIntents.swift` makes eleven existing intents tools. Each intent keeps its iOS 26 availability, its confirmation and its sign-in check. The file adds only the `ToolIntent` conformance, marked `@available(iOS 27.3, *)`.

| Tool title | Intent |
| --- | --- |
| Add Shift | `AddShiftIntent` |
| Move Shift | `MoveShiftIntent` |
| Extend Shift | `ExtendShiftIntent` |
| Clock Out | `StopClockIntent` |
| Get Next Shift | `NextShiftIntent` |
| Get Earnings | `EarningsIntent` |
| Get Hours Worked | `HoursWorkedIntent` |
| Get Earned So Far | `EarnedSoFarIntent` |
| Get Friend's Shifts | `FriendScheduleIntent` |
| Open Shift | `OpenShiftIntent` |
| Open Job | `OpenJobIntent` |

The same file gives `FriendEntityQuery` an `allEntities()` method. Siri finds the entity for a tool parameter in Spotlight or through `allEntities()`. It never calls `entities(matching:)` for a tool. Shifts and jobs are in Spotlight. Friends are not, so Siri reads them through `allEntities()`, which returns nothing when the user is signed out.

`Skills.skillsbundle` holds one app skill, `change-shifts`. Siri reads it when a request is about adding, moving, extending or ending a shift. It says which of the four tools fits and tells Siri not to add a second shift to correct an existing one.

Three intents are not tools. `SendFriendMessageIntent` and `DraftFriendMessageIntent` follow the messages schema, which Siri already handles, and the compiler rejects a tool in that schema. `FriendShiftIntent` only configures a widget.

Siri's model reads the same titles and descriptions that Shortcuts shows. There is no separate text for the model, so improve a tool by editing its catalog strings.

## The switch

`ios/SiriAIPreview.xcconfig` defines `TIDEX_SIRI_AI_PREVIEW`, which is `NO` by default. It excludes every file under a folder named `SiriAIPreview` from all targets. Only the exact value `YES` includes those files again. Any other value leaves them out.

- Put code that needs the iOS 27.3 SDK in a `SiriAIPreview` folder, at most four folder levels deep. The patterns in the xcconfig reach no further.
- Code outside the folder must not refer to anything inside it, or the normal build breaks.
- With the switch on, the release Xcode fails with `Cannot find type 'ToolIntent' in scope`. Use the Xcode 27.3 beta.
- A preview build prints the warning `Siri AI preview build` from `AssistantToolIntents.swift`.

## Build a preview

From the command line, select the beta toolchain and pass the switch. Give the beta its own DerivedData folder, because the two Xcode versions cannot share one.

```bash
DEVELOPER_DIR=/Applications/Xcode-27.3.0-beta.app/Contents/Developer \
  ./scripts/xcode-build-agent.sh \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Tidex-siri-ai-preview-beta \
  TIDEX_SIRI_AI_PREVIEW=YES
```

The test wrapper takes the same variable and arguments. On a connected iPhone it leaves the preview build installed.

In the Xcode 27.3 beta app, create the git-ignored file `ios/SiriAIPreview.local.xcconfig` with one line and build the Debug configuration:

```
TIDEX_SIRI_AI_PREVIEW = YES
```

Only `debug.xcconfig` reads that file. A Release build or an archive gets the preview only when `TIDEX_SIRI_AI_PREVIEW=YES` is on the `xcodebuild` command line. Do that for an internal TestFlight build and never for a build that goes to App Review.

## Check the metadata

Apple's analyzer reads a built app and reports how well Siri's model can use it. Run it after every change to a tool, an entity or a catalog string they use.

```bash
DEVELOPER_DIR=/Applications/Xcode-27.3.0-beta.app/Contents/Developer \
  xcrun sirimetadataanalyzer <DerivedData>/Build/Products/Debug-iphonesimulator/Tidex.app
```

A preview build reports `14 intents (11 tools), 7 entities` with no errors and no warnings. Add `--language nb` for the Norwegian strings. Six suggestions remain on purpose:

- Five `SMA203` findings ask for descriptions on the properties of `ShiftEntity`, `JobEntity` and `FriendEntity`. The `description:` argument needs a deployment target of iOS 27.3, and Swift cannot limit a stored property to newer systems. Add the descriptions when the deployment target reaches 27.3.
- `SMA701` says `StopClockIntent` resembles the system's Stop Stopwatch action. It clocks the user out of work, and its title is Clock Out.

A build with the switch off reports `0 tools` and has no `Metadata.appintents/Skills.skillsc`. To check an archive made with the release Xcode, which has no analyzer, count the tool marker. It must print 0:

```bash
grep -c ToolIntent <Tidex.app>/Metadata.appintents/extract.actionsdata
```

The skills compiler checks the skill files without a build:

```bash
/Applications/Xcode-27.3.0-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsskillsprocessor \
  --skillsbundle ios/TidexApp/Features/Assistant/SiriAIPreview/Skills.skillsbundle --output "$TMPDIR"
```

In a preview build, the Xcode 27.3 beta prints `error: the following command failed with exit code 0 but produced no further output` for the skills step. The step succeeds and writes `Skills.skillsc`. Ignore that line while the build reports success.

## Not verified yet

Nobody has spoken to Siri AI with a preview build. The builds, the metadata and the existing assistant tests are checked. What Siri does with the tools and the skill is not. On an iPhone with iOS 27.3, Apple Intelligence and Siri in English, install a preview build, open Tidex once, and try:

- "Add a shift in Tidex tomorrow from eight to twelve." The one-sentence form fails in classic Siri.
- "Move my Friday shift in Tidex to Saturday."
- "I'm staying an hour longer" while a saved shift is ongoing and Tidex is open.
- "How much have I earned this month in Tidex?"
- "When does <friend> work on Friday in Tidex?"

Apple's SiriEvaluations framework can script these requests on a device and grade which tool Siri calls. Tidex has no evaluation suite yet.

## When Apple opens App Store submission

1. Build with a release Xcode that has the iOS 27.3 SDK.
2. Move the files out of `SiriAIPreview/`, delete the `#warning`, and delete `ios/SiriAIPreview.xcconfig` with its two `#include` lines and the `.gitignore` entry.
3. Run the analyzer and the device checks above.
