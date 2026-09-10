// LuminaVaultClient/LuminaVaultClientTests/HermieMascotPlaybackTests.swift
//
// `HermieMascotView` drives a Rive state machine. Every other clock-driven
// decoration (halo drift, logo breathing, sparkle field) already freezes
// under `\.lvAmbientMotionEnabled == false`, which the snapshot suites set;
// the mascot did not, so `think-empty-dark` captured a different Rive frame
// on different CI runs and disagreed with itself. The decision is a pure
// function so it can be pinned here without a Rive runtime.

import XCTest
@testable import LuminaVaultClient

final class HermieMascotPlaybackTests: XCTestCase {
    func testPlaysByDefaultWhenActiveAndMotionAllowed() {
        XCTAssertTrue(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false,
                ambientMotionEnabled: true,
                sceneActive: true,
                hostTab: nil,
                activeTab: ""
            )
        )
    }

    func testAmbientMotionOffFreezesTheMascot() {
        XCTAssertFalse(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false,
                ambientMotionEnabled: false,
                sceneActive: true,
                hostTab: nil,
                activeTab: ""
            ),
            "snapshot suites set lvAmbientMotionEnabled = false and expect a static frame"
        )
    }

    func testReduceMotionStillWins() {
        XCTAssertFalse(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: true,
                ambientMotionEnabled: true,
                sceneActive: true,
                hostTab: nil,
                activeTab: ""
            )
        )
    }

    func testBackgroundedSceneDoesNotPlay() {
        XCTAssertFalse(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false,
                ambientMotionEnabled: true,
                sceneActive: false,
                hostTab: nil,
                activeTab: ""
            )
        )
    }

    func testHostTabGatesPlaybackOnlyWhenATabIsKnown() {
        XCTAssertTrue(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false, ambientMotionEnabled: true, sceneActive: true,
                hostTab: "think", activeTab: ""
            ),
            "no active tab published yet → play"
        )
        XCTAssertTrue(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false, ambientMotionEnabled: true, sceneActive: true,
                hostTab: "think", activeTab: "think"
            )
        )
        XCTAssertFalse(
            HermieMascotPlayback.shouldPlay(
                reduceMotion: false, ambientMotionEnabled: true, sceneActive: true,
                hostTab: "think", activeTab: "home"
            ),
            "TabView keeps sibling tabs mounted; only the visible host plays"
        )
    }
}
