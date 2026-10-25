// swift-tools-version: 6.0
//
// avo_kit: what Avo and Avo Hub share, used by both as a submodule
// (vendor/avo_kit) and a local Swift package.
//
//   AvoInput     the records a game view sends Android (touches, keys,
//                scroll, mouse, gamepad), as Avo's Input channel carries them
//   AvoScreen    samples of the picture and how a part of it moved (the
//                wheel's Automatic scroll, Translate Screen)
//   AvoKeymap    key mapping profiles and the engine that turns keys, the
//                mouse and controllers into touches
//   AvoHazeUI    the haze in small: QuickHaze's colours and type, the Quick*
//                controls, HazeMenu, and FullScreenBars
//   AvoKeymapUI  the key mapping a window runs over its game view: the
//                controller, the editor and its panels, the hints, GamepadHub
//
// Their text is in AvoKitResources (`Bundle.avoSharedKit`). AvoInput,
// AvoScreen and AvoHazeUI's colours, type and SwiftUI controls build for iOS
// too (Avo Hub's iPhone and iPad app); the key mapping and the AppKit menus
// and bars stay macOS.

import PackageDescription

let package = Package(
    name: "avo_kit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "AvoInput", targets: ["AvoInput"]),
        .library(name: "AvoScreen", targets: ["AvoScreen"]),
        .library(name: "AvoKeymap", targets: ["AvoKeymap"]),
        .library(name: "AvoHazeUI", targets: ["AvoHazeUI"]),
        .library(name: "AvoKeymapUI", targets: ["AvoKeymapUI"]),
    ],
    targets: [
        .target(name: "AvoKitResources", resources: [.process("Resources")]),
        .target(name: "AvoInput"),
        .target(name: "AvoScreen"),
        .target(name: "AvoKeymap", dependencies: ["AvoKitResources", "AvoInput", "AvoScreen"]),
        .target(name: "AvoHazeUI", dependencies: ["AvoKitResources"]),
        .target(name: "AvoKeymapUI", dependencies: ["AvoKitResources", "AvoInput", "AvoKeymap", "AvoHazeUI"]),
        .testTarget(name: "AvoKeymapTests", dependencies: ["AvoKeymap", "AvoInput", "AvoScreen"]),
        .testTarget(name: "AvoKeymapUITests", dependencies: ["AvoKeymapUI", "AvoKeymap", "AvoInput"]),
        .testTarget(name: "AvoHazeUITests", dependencies: ["AvoHazeUI"]),
    ],
    swiftLanguageModes: [.v6]
)
