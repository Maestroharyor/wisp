import XCTest

@testable import WispCore

final class AppVolumeTests: XCTestCase {
    // MARK: Levels

    func testAnAppStartsAtFullVolume() {
        let settings = AppVolumeSettings()
        XCTAssertEqual(settings.level(for: "com.spotify.client"), 1)
        XCTAssertFalse(settings.isMuted("com.spotify.client"))
        XCTAssertEqual(settings.gain(for: "com.spotify.client"), 1)
        XCTAssertFalse(settings.needsTap("com.spotify.client"))
    }

    func testLevelsAreClamped() {
        var settings = AppVolumeSettings()
        settings.setLevel(1.7, for: "a")
        XCTAssertEqual(settings.level(for: "a"), 1)
        settings.setLevel(-0.3, for: "a")
        XCTAssertEqual(settings.level(for: "a"), 0)
        settings.setLevel(.nan, for: "a")
        XCTAssertEqual(settings.level(for: "a"), 1)
    }

    func testNearlyFullSnapsBackAndForgetsTheApp() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.5, for: "a")
        XCTAssertEqual(settings.levels, ["a": 0.5])
        settings.setLevel(0.995, for: "a")
        XCTAssertEqual(settings.levels, [:])
        XCTAssertFalse(settings.needsTap("a"))
    }

    func testGainFollowsASquaredCurve() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.5, for: "a")
        XCTAssertEqual(settings.gain(for: "a"), 0.25, accuracy: 0.0001)
        XCTAssertTrue(settings.needsTap("a"))
        settings.setLevel(0, for: "a")
        XCTAssertEqual(settings.gain(for: "a"), 0)
    }

    func testMuteSilencesWithoutLosingTheLevel() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.6, for: "a")
        settings.setMuted(true, for: "a")
        XCTAssertEqual(settings.gain(for: "a"), 0)
        XCTAssertTrue(settings.needsTap("a"))
        settings.setMuted(false, for: "a")
        XCTAssertEqual(settings.level(for: "a"), 0.6)
        XCTAssertEqual(settings.gain(for: "a"), 0.36, accuracy: 0.0001)
    }

    func testAMutedAppAtFullLevelStillNeedsATap() {
        var settings = AppVolumeSettings()
        settings.setMuted(true, for: "a")
        XCTAssertTrue(settings.needsTap("a"))
        XCTAssertEqual(settings.tappedApps, ["a"])
    }

    func testResetForgetsLevelAndMute() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.2, for: "a")
        settings.setMuted(true, for: "a")
        settings.reset("a")
        XCTAssertEqual(settings, AppVolumeSettings())
    }

    func testSettingsSurviveARoundTrip() throws {
        var settings = AppVolumeSettings()
        settings.setLevel(0.4, for: "com.google.Chrome")
        settings.setMuted(true, for: "com.tinyspeck.slackmacgap")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppVolumeSettings.self, from: data), settings)
    }

    func testDecodingClampsStoredValues() throws {
        let json = Data(#"{"levels":{"a":4,"b":0.3,"c":1},"muted":[]}"#.utf8)
        let settings = try JSONDecoder().decode(AppVolumeSettings.self, from: json)
        XCTAssertEqual(settings.levels, ["b": 0.3])
    }

    // MARK: Grouping

    func testHelpersFoldIntoTheirApp() {
        XCTAssertEqual(AudioAppGrouping.appID(process: "com.google.Chrome.helper", ancestors: []), "com.google.Chrome")
        XCTAssertEqual(
            AudioAppGrouping.appID(process: "com.google.Chrome.helper.renderer", ancestors: []), "com.google.Chrome")
        XCTAssertEqual(
            AudioAppGrouping.appID(process: "com.tinyspeck.slackmacgap.helper", ancestors: []),
            "com.tinyspeck.slackmacgap")
        XCTAssertEqual(AudioAppGrouping.appID(process: "com.hnc.Discord.Helper", ancestors: []), "com.hnc.Discord")
    }

    func testWebKitPlaysForSafari() {
        XCTAssertEqual(AudioAppGrouping.appID(process: "com.apple.WebKit.GPU", ancestors: []), "com.apple.Safari")
    }

    func testTheNearestAppAncestorWins() {
        XCTAssertEqual(
            AudioAppGrouping.appID(process: "org.mozilla.plugincontainer", ancestors: ["org.mozilla.firefox"]),
            "org.mozilla.firefox")
    }

    func testAnAppIsItsOwnGroup() {
        XCTAssertEqual(AudioAppGrouping.appID(process: "com.spotify.client", ancestors: []), "com.spotify.client")
    }

    func testUnnamedAndSystemProcessesAreLeftOut() {
        XCTAssertNil(AudioAppGrouping.appID(process: "", ancestors: []))
        XCTAssertNil(AudioAppGrouping.appID(process: "systemsoundserverd", ancestors: []))
        XCTAssertNil(AudioAppGrouping.appID(process: "com.apple.controlcenter", ancestors: []))
    }

    // MARK: Rows

    private func process(_ id: UInt32, _ app: String?, playing: Bool) -> AudioProcess {
        AudioProcess(objectID: id, appID: app, isPlaying: playing)
    }

    func testRowsGroupProcessesAndLeaveOutWisp() {
        let rows = AppVolumeList.rows(
            processes: [
                process(1, "com.google.Chrome", playing: false),
                process(2, "com.google.Chrome", playing: true),
                process(3, "com.ayomideodewale.wisp", playing: true),
                process(4, nil, playing: true),
            ],
            settings: AppVolumeSettings(), ownAppID: "com.ayomideodewale.wisp", names: ["com.google.Chrome": "Chrome"])
        XCTAssertEqual(rows.map(\.id), ["com.google.Chrome"])
        XCTAssertEqual(rows.first?.processes, [1, 2])
        XCTAssertEqual(rows.first?.isPlaying, true)
        XCTAssertEqual(rows.first?.name, "Chrome")
    }

    func testQuietAppsShowOnlyWithACustomLevel() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.3, for: "com.apple.Music")
        let rows = AppVolumeList.rows(
            processes: [
                process(1, "com.apple.Music", playing: false),
                process(2, "com.apple.Podcasts", playing: false),
            ],
            settings: settings, ownAppID: nil, names: [:])
        XCTAssertEqual(rows.map(\.id), ["com.apple.Music"])
        XCTAssertEqual(rows.first?.level, 0.3)
        XCTAssertEqual(rows.first?.name, "com.apple.Music")
    }

    func testPlayingAppsComeFirstThenByName() {
        let rows = AppVolumeList.rows(
            processes: [
                process(1, "b", playing: false), process(2, "a", playing: true), process(3, "c", playing: true),
            ],
            settings: {
                var settings = AppVolumeSettings()
                settings.setLevel(0.5, for: "b")
                return settings
            }(), ownAppID: nil, names: ["a": "Zed", "b": "Alpha", "c": "Music"])
        XCTAssertEqual(rows.map(\.name), ["Music", "Zed", "Alpha"])
    }

    // MARK: Taps

    func testTapsAreWantedForPlayingOrPausedAppsBelowFull() {
        var settings = AppVolumeSettings()
        settings.setLevel(0.5, for: "a")
        settings.setMuted(true, for: "b")
        let wanted = AppVolumeTaps.wanted(
            processes: [
                process(1, "a", playing: false), process(2, "a", playing: true), process(3, "b", playing: false),
                process(4, "c", playing: true),
            ], settings: settings, ownAppID: nil)
        XCTAssertEqual(wanted, ["a": [1, 2], "b": [3]])
    }

    func testPlanRebuildsOnlyWhatChanged() {
        let plan = AppVolumeTaps.plan(
            current: ["a": [1], "b": [2], "c": [3]], wanted: ["a": [1], "b": [2, 5], "d": [4]])
        XCTAssertEqual(plan.remove, ["b", "c"])
        XCTAssertEqual(plan.create, ["b": [2, 5], "d": [4]])
    }

    // MARK: Arming

    func testArmsOnceRealSoundArrives() {
        var arming = TapArming()
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 1), .listening)
        XCTAssertEqual(arming.observe(peak: 0.2, appPlaying: true, seconds: 0.25), .armed)
        // Silence while the app is paused never disarms.
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: false, seconds: 60), .armed)
    }

    func testAnArmedTapOnAQuietOpenStreamStaysArmed() {
        // A paused tab or a call on hold keeps its stream open with nothing in it.
        var arming = TapArming()
        _ = arming.observe(peak: 0.3, appPlaying: true, seconds: 0.5)
        XCTAssertEqual(arming.observe(peak: 0.000_001, appPlaying: true, seconds: 120), .armed)
    }

    func testAnArmedTapReadingExactZerosWhilePlayingStaysArmed() {
        var arming = TapArming()
        _ = arming.observe(peak: 0.3, appPlaying: true, seconds: 0.5)
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 60), .armed)
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 600), .armed)
    }

    func testATapBuiltOnceWispCanHearStartsArmed() {
        var arming = TapArming(heard: true)
        XCTAssertEqual(arming.state, .armed)
        // Built armed on another tap's word, so it proves nothing about the permission itself.
        XCTAssertFalse(arming.hasHeard)
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 10), .armed)
        XCTAssertEqual(TapArming(heard: false), TapArming())
    }

    // MARK: Start failures

    func testThreeFailedStartsInARowGiveUp() {
        var starts = TapStarts()
        XCTAssertFalse(starts.record(success: false))
        XCTAssertFalse(starts.record(success: false))
        XCTAssertTrue(starts.record(success: false))
    }

    func testASuccessfulStartResetsTheCount() {
        var starts = TapStarts()
        _ = starts.record(success: false)
        _ = starts.record(success: false)
        XCTAssertFalse(starts.record(success: true))
        XCTAssertFalse(starts.record(success: false))
        XCTAssertFalse(starts.record(success: false))
        XCTAssertTrue(starts.record(success: false))
    }

    func testOnlyTheFirstFailureIsLogged() {
        var starts = TapStarts()
        _ = starts.record(success: false)
        XCTAssertTrue(starts.shouldLog)
        _ = starts.record(success: false)
        XCTAssertFalse(starts.shouldLog)
    }

    func testAnArmedTapNeverCountsAsSilent() {
        var arming = TapArming()
        _ = arming.observe(peak: 0.3, appPlaying: true, seconds: 0.5)
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 5), .armed)
        XCTAssertTrue(arming.hasHeard)
    }

    // MARK: IO

    func testAListeningTapReadsWhileTheAppIsActive() {
        XCTAssertTrue(TapIO.needsIO(armed: false, gain: 0, active: true))
        XCTAssertFalse(TapIO.needsIO(armed: false, gain: 0.5, active: false))
    }

    func testAnArmedTapAtZeroNeedsNoIO() {
        // The tap mutes the app by itself once armed, so silence costs nothing.
        XCTAssertFalse(TapIO.needsIO(armed: true, gain: 0, active: true))
    }

    func testAnArmedTapPlaysOnlyWhileTheAppIsActive() {
        XCTAssertTrue(TapIO.needsIO(armed: true, gain: 0.25, active: true))
        XCTAssertFalse(TapIO.needsIO(armed: true, gain: 0.25, active: false))
    }

    // MARK: Hearing

    func testHearingNeedsOneArmedTapOrSeveralSilentOnes() {
        XCTAssertEqual(SystemAudioHearing.status(armed: 1, silent: 3), true)
        XCTAssertNil(SystemAudioHearing.status(armed: 0, silent: 1))
        XCTAssertEqual(SystemAudioHearing.status(armed: 0, silent: 2), false)
        XCTAssertNil(SystemAudioHearing.status(armed: 0, silent: 0))
    }

    // MARK: Activity

    func testIORunsWhilePlayingAndStopsAfterTheGrace() {
        var activity = TapActivity()
        XCTAssertTrue(activity.observe(appPlaying: true, seconds: 0.5))
        XCTAssertTrue(activity.observe(appPlaying: false, seconds: 3))
        XCTAssertFalse(activity.observe(appPlaying: false, seconds: 2))
        XCTAssertTrue(activity.observe(appPlaying: true, seconds: 0.5))
        XCTAssertTrue(activity.observe(appPlaying: false, seconds: 4.9))
    }

    func testAQuietAppStartsWithIOOff() {
        var activity = TapActivity()
        XCTAssertFalse(activity.observe(appPlaying: false, seconds: 0))
    }

    // MARK: App cache

    func testTheCacheResolvesEachProcessOnce() {
        var cache = AudioAppCache()
        var calls = 0
        let resolve: (Int32) -> String? = { _ in
            calls += 1
            return "com.google.Chrome"
        }
        XCTAssertEqual(cache.appID(object: 5, pid: 100, resolve: resolve), "com.google.Chrome")
        XCTAssertEqual(cache.appID(object: 5, pid: 100, resolve: resolve), "com.google.Chrome")
        XCTAssertEqual(calls, 1)
        _ = cache.appID(object: 5, pid: 101, resolve: resolve)
        XCTAssertEqual(calls, 2)
    }

    func testTheCacheRemembersSystemProcessesToo() {
        var cache = AudioAppCache()
        var calls = 0
        let resolve: (Int32) -> String? = { _ in
            calls += 1
            return nil
        }
        XCTAssertNil(cache.appID(object: 1, pid: 1, resolve: resolve))
        XCTAssertNil(cache.appID(object: 1, pid: 1, resolve: resolve))
        XCTAssertEqual(calls, 1)
    }

    func testTheCacheForgetsGoneProcesses() {
        var cache = AudioAppCache()
        _ = cache.appID(object: 1, pid: 10) { _ in "a" }
        _ = cache.appID(object: 2, pid: 20) { _ in "b" }
        cache.keep(objects: [2])
        XCTAssertEqual(cache.count, 1)
    }

    func testSilenceWhilePlayingMeansWispCantHearTheApp() {
        var arming = TapArming()
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 2), .listening)
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: true, seconds: 2), .silent)
        XCTAssertEqual(arming.observe(peak: 0.5, appPlaying: true, seconds: 0.25), .armed)
    }

    func testAPausedAppDoesNotCountAsSilent() {
        var arming = TapArming()
        XCTAssertEqual(arming.observe(peak: 0, appPlaying: false, seconds: 30), .listening)
    }

    func testNoiseFloorDoesNotArm() {
        var arming = TapArming()
        XCTAssertEqual(arming.observe(peak: 0.000_01, appPlaying: true, seconds: 0.25), .listening)
    }

    // MARK: Rendering

    func testRenderScalesAndRampsAcrossTheBuffer() {
        let source: [Float] = [1, 1, 1, 1, 1, 1, 1, 1]
        var destination = [Float](repeating: 9, count: 8)
        source.withUnsafeBufferPointer { input in
            destination.withUnsafeMutableBufferPointer { output in
                AudioGain.render(
                    input, channels: 2, into: output, channels: 2, frames: 4, from: 0, to: 1)
            }
        }
        XCTAssertEqual(destination, [0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1, 1])
    }

    func testRenderZeroesExtraOutputChannels() {
        let source: [Float] = [0.5, -0.5, 0.5, -0.5]
        var destination = [Float](repeating: 9, count: 8)
        source.withUnsafeBufferPointer { input in
            destination.withUnsafeMutableBufferPointer { output in
                AudioGain.render(input, channels: 2, into: output, channels: 4, frames: 2, from: 1, to: 1)
            }
        }
        XCTAssertEqual(destination, [0.5, -0.5, 0, 0, 0.5, -0.5, 0, 0])
    }

    func testRenderMixesStereoDownToMono() {
        let source: [Float] = [1, 0, 0.5, 0.5]
        var destination = [Float](repeating: 9, count: 2)
        source.withUnsafeBufferPointer { input in
            destination.withUnsafeMutableBufferPointer { output in
                AudioGain.renderMono(input, channels: 2, into: output, frames: 2, from: 1, to: 1)
            }
        }
        XCTAssertEqual(destination, [0.5, 0.5])
    }

    func testRenderFillsALaterBufferFromItsFirstChannel() {
        let source: [Float] = [0.1, 0.2, 0.3, 0.4]
        var right = [Float](repeating: 9, count: 2)
        source.withUnsafeBufferPointer { input in
            right.withUnsafeMutableBufferPointer { output in
                AudioGain.render(
                    input, channels: 2, into: output, channels: 1, firstChannel: 1, frames: 2, from: 1, to: 1)
            }
        }
        XCTAssertEqual(right, [0.2, 0.4])
    }

    func testRenderNeverReadsPastAShortInput() {
        let source: [Float] = [1, 1]
        var destination = [Float](repeating: 9, count: 8)
        source.withUnsafeBufferPointer { input in
            destination.withUnsafeMutableBufferPointer { output in
                AudioGain.render(input, channels: 2, into: output, channels: 2, frames: 4, from: 1, to: 1)
            }
        }
        XCTAssertEqual(destination, [1, 1, 0, 0, 0, 0, 0, 0])
    }

    func testPeakIsTheLoudestSample() {
        let samples: [Float] = [0.1, -0.7, 0.3]
        XCTAssertEqual(samples.withUnsafeBufferPointer { AudioGain.peak($0) }, 0.7)
    }
}
