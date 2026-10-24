# avo_kit

Swift packages that [Avo](https://github.com/nizwar/avo) and Avo Hub share, so a change lands in both.

| Module | What it is |
| --- | --- |
| `AvoKeymap` | Key mapping profiles (JSON) and the engine that turns keys, the mouse and controllers into multitouch: taps, joysticks, the eye, MOBA controls, scroll bars, click areas and zones, modes and actions. |
| `AvoKeymapUI` | The key mapping a window runs over its game view: the controller, the editor and its panel, the hints over the game, the controller panel and `GamepadHub`. A host gives it its view and store (`KeymapHost.swift`). |
| `AvoHazeUI` | The haze in small: QuickHaze's colours and type, the Quick* controls, and `HazeMenu`, the menu shown in place of macOS's. |
| `AvoInput` | The records a game view sends Android (touches, keys, scroll, mouse, gamepad), as Avo's Input channel carries them. |
| `AvoScreen` | Samples of the picture and how part of it moved (the wheel's Automatic scroll, Translate Screen). |

Their text, in English and Indonesian, is in `Sources/AvoKitResources/Resources/Localizable.xcstrings` (`Bundle.avoSharedKit`).

## Use

Each project has it as a submodule at `vendor/avo_kit` and depends on it as a local package:

```swift
.package(path: "../../vendor/avo_kit")
```

```bash
git submodule update --init vendor/avo_kit
```

## Develop

```bash
swift test
```

Requires macOS 15 and Xcode 16 or newer. Change it here, commit, then move the submodule in Avo and Avo Hub to the new commit.
