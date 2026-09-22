# App Store screenshots

Raw captures for the App Store listing, 1320 x 2868 (6.9 inch, iPhone 17 Pro
Max simulator, iOS 26.4). App Store Connect accepts this size for every
iPhone slot. Not framed or captioned; that is a design pass on top of these.

| file | screen | seed |
|---|---|---|
| 01-today.png | Today, a lift day with line-art rows | `--seed-plan-demo` |
| 02-week.png | Week view (the seed repeats "Push day" on every day; reshoot on a real plan before using) | `--seed-plan-demo` |
| 03-library.png | Library tiles, 580 exercises | `--seed-plan-demo` |
| 04-library-core.png | Core list with animated thumbnails | `--seed-plan-demo` |
| 05-exercise-detail.png | Exercise detail, line-art hero and muscle chips | `--seed-plan-demo` |
| 06-log.png | Log screen mid-session with the Apple Music card | `--seed-supersets-demo --ui-test-fake-now-playing` |
| 07-progress.png | Progress, last 8 weeks | `--seed-progress-demo` |

## Regenerate

```
MAX=$(xcrun simctl create "iPhone 17 Pro Max" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max \
  com.apple.CoreSimulator.SimRuntime.iOS-26-4)
xcodebuild test -project PhaseTraining.xcodeproj -scheme PhaseTraining \
  -destination "id=$MAX" -derivedDataPath .build/DerivedData \
  -only-testing:PhaseTrainingUITests/StoreScreenshotUITests \
  -resultBundlePath /tmp/store.xcresult
xcrun xcresulttool export attachments --path /tmp/store.xcresult --output-path /tmp/store_att
```

`manifest.json` in the output maps each attachment's `suggestedHumanReadableName`
(`01-today_...png`) to its exported file; copy them here under the short name.
