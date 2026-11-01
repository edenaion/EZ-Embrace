# Feature regression checks

Run `bash tests/run-features.sh <audio fixtures...>` from the project directory. Use audio longer than 12 seconds. The harness compiles the production audio source, preference store, and window scaling code. Audio renders into memory without opening an output device. Appearance checks use a separate preferences domain. One temporary translucent window appears briefly for resize regression checks.

☼ Audio: playable-region trims, silence padding, forward/backward seeking, fade endpoints, repeated requests, boundaries, finite output, and mono/stereo conversion at 44.1 and 48 kHz.
☼ Lookahead clock: ordinary pulls, multi-pull Declick lead, output accounting, source-swap reset, completed-seek reset and silent-output underflow protection.
☼ Decoder faults: open/trim/read failures, delayed seek targets, failure after priming, early EOF, and the five-second priming timeout. These use a controlled decoder with the production source and no output device.
☼ Metadata: titles and duration survive parsing and persistence across the supplied formats; decoded strings contain no NUL or control characters.
☼ Effect lifecycle: newly active units are not reset after graph rebuilding; removed units reset once after replacement. The isolated chain-update test does not configure or start an output device.
☼ EQ geometry: knob movement and Option-drag speed remain consistent across manual text presets and 300% window scaling.
☼ Appearance: legacy preference migration, all five size presets with bold on/off, navigation visibility, native window coordinates, uniform transforms, fixed-window policy, oversized-content scrolling, normal resizing, native zoom/restore, preference persistence, and no writes during resizing.
☼ Real app checks still cover mouse gestures, window dragging, menus, queue transitions, effect editors, and visual layout. Offline checks do not establish audio hardware or OS compatibility.

## Single-use track starts

Run `bash tests/run-track-cues.sh` and `bash tests/run-player-cues.sh`. The model harness compiles production `Track.m` and checks cue validation, Music trim changes, persistence, independent duplicate entries and revision-based consumption. The player harness compiles production `Player.m` with a device-free engine and checks the initial offset, completion reset, a newer pending cue, early manual stop and skip. Both isolate their state from the installed app.

Run `bash tests/run-queue-cues.sh` for the production `TracksController.m` drag/drop path with actual `Track.m` entries and a real pasteboard. Forward, backward and multiple-entry moves retain UUIDs and cues; copies receive a new UUID and no cue. Music Library track and playlist representations enter requested top, middle and bottom Up Next positions, preserve playlist order, keep trailing played history available, and create independent cue-free UUIDs for repeated sources. A completed track stays gray in its timeline position across restart. The solid line follows the most recently played row. A played row can still be dragged into a requested Up Next position while history-only, mixed, and active-row drags remain rejected. Saved UUID order and the next queued entry follow every accepted move. Its table and dragging information are controlled inputs; physical mouse dragging still needs app evidence.

Audio checks also exercise the initial offset with and without auto-gap while retaining backward seeking. Supplying fixtures longer than 340 seconds adds a 5:30 start and measures priming against the production five-second limit. UI flags, waveform editing, actual drag ordering and real transitions require the app checks.

The project contains no XCTest target. Stale references to absent upstream test targets have been removed from the shared scheme. Run the CLI harness for these regression checks; Xcode's Test action does not run this suite.

## Custom parametric EQ checks

Run `bash tests/run-parametric-eq.sh`. The adapted EmbraceNG suite checks the portable DSP with optimized code and AddressSanitizer/UndefinedBehaviorSanitizer. Native checks cover Audio Unit registration, parameter ranges, measured response against the editor's curve, concurrent automation, presets, and editor drawing. Production `Effect` checks cover corrupt Apple states and custom EQ persistence. These checks render into memory and do not open a hardware output device.

The source is adapted from EmbraceNG main `1c3b15bf8e56e8b2cfbecbb675c474b0caf45668`; see [the retained license](../LICENSE.EmbraceNG).

EQ slot checks exercise the production preset state path: both bundled custom EQ factory curves, every factory parameter, independent user replacements, empty graphic EQ slots, EQ-type separation, malformed data, and persistence into a second process. Factory recalls must not create user overrides. They run in a small app bundle with the shipping resources, use the isolated `state-tests` preference domain, and remove its settings after the restart check.

The same runner checks the Set List EQ button against real Audio Units with a device-free Player stub. It verifies chain creation, bypass, external state updates, parameter preservation, bypass persistence, other-effect isolation, and geometry across all text sizes, bold states and uniform scaling. Both on/off actions must request the matching custom EQ editor, including when enabling creates a new EQ. Existing-unit toggles must not assign a new chain. Window frames, minimum sizes and control positions must remain unchanged.

Button raster checks cover on/off, pressed/released, focused/inactive and Light/Dark appearances. Blue fill must follow the effect state; a focus change cannot gray out an enabled EQ.

Native Audio Unit view checks verify the large bold ON/OFF label, its position above the graph, synchronous bypass observation and unchanged editor dimensions. The curve checks also drive every numbered point at 100% and 200% scaling, verify logarithmic frequency and gain mapping, adjust Q through a wheel gesture, and render the bottom frequency scale in both Light and Dark appearances.

## Restoration DSP checks

Run `bash tests/run-restoration-core.sh`. The portable EmbraceNG Declick and Dehum cores are built independently with optimized code and with AddressSanitizer/UndefinedBehaviorSanitizer. The checks cover parameter clamping, 44.1/48 kHz configuration, sample-exact bypass, finite streaming output, injected-click repair, manual 60 Hz removal, allocation-free live retuning, seek flushing and adoption of an asynchronously scouted hum line. These checks do not open an audio device.

Run `bash tests/run-restoration-audio-unit.sh` for the native wrapper. It checks in-process registration, all sixteen parameter definitions and help strings, hostile parameter writes, saved-state round trips, the generic parameter form and reset gesture, matching bus formats, mono/stereo renders at 44.1/48 kHz, malformed and oversized renders, Declick read-ahead alignment/tail reset/repair, and Dehum removal/bypass/seek reset. It renders into memory and does not open an audio output device.

## Playback presentation checks

Run `bash tests/run-presentation.sh [optional-meter-image-path.png]`. The harness loads the production Current Track nib and UI classes with an isolated player and preference domain. It checks title and artist changes, missing metadata, stopped state, all text-size/bold combinations, uniform window scaling, the full seek hit area, meter headroom colors and LED pixels, overload feedback, and playing-row state. It opens no audio output device. Real app input and hardware checks remain separate.

## Playback capture for stability QA

Build the local capture utility with `bash tests/build-qa-capture.sh [output-directory]`. It uses an ad hoc signature unless `EZ_EMBRACE_QA_SIGN_IDENTITY` names a local signing identity. Run the resulting app's `Contents/MacOS/ez-embrace-qa-capture` executable with `PID ACTIVE_SECONDS EVIDENCE_DIRECTORY [DEVICE_UID [BUNDLE_ID [STARTUP_TIMEOUT_SECONDS]]]`.

☼ The utility restricts capture to the Embrace process. It creates a private, temporary Core Audio tap and aggregate, leaves playback unmuted, and does not change the system's default audio route.
☼ Without a device UID it records the process mix in stereo. An exact device UID records that endpoint's native channels, including silence on all channels. Device taps retain the initializer's endpoint routing; forcing a stereo mixdown would combine outputs. Recordings use Apple Lossless CAF from 16-bit PCM source samples, plus per-second signal statistics and Embrace memory snapshots. Audio callbacks use a preallocated ring; conversion, disk writes and reporting happen outside the callback.
☼ It records capture overruns, nonfinite/clipped samples, and completed silent intervals. Leading and trailing silence are excluded from the completed-silence maximum. A finished capture is not a playback test pass; compare signal span and runtime logs against the required duration and expected transitions.
☼ Setup and active states are distinct. A stopped process may supply no tap callbacks, so setup may wait up to the requested timeout. The recording duration and elapsed statistics begin at the first non-empty callback, whose clock is retained separately from setup. Require measured signal coverage and normal playback completion; do not count pre-callback setup time as output.
☼ The build and capture both preserve the 10 GiB free-space reserve. The capture utility is local QA infrastructure and requires macOS 14.2 or later; it is not part of the shipped player.

Apple's [Core Audio tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) documents the system audio permission and usage-description requirement. The local helper contains that description. No microphone or other app capture is requested by this utility.

## Music library and window borders

Run `bash tests/run-music-library.sh`. The native harness uses synthetic metadata and existing disposable WAV/AIFF files. It verifies playlist order and duplicates, accent-insensitive search, numeric/text sorting, unavailable-file handling, actual drag representations, no artwork views, saved color reload/reset, hit testing and typography scaling. Its settings use a separate QA bundle domain. `--interactive` opens the same production browser controller with synthetic fixtures for app-scoped desktop QA. It does not modify the Music library.

Border rendering checks draw the production edge at 1x and Retina resolution in Light and Dark appearances. They check the gradient, transparent content/corners, fine edge coverage and pointer pass-through.

## Independent audition playback

Run `bash tests/run-audition.sh` on the local QA Mac with built-in speakers and BlackHole 2ch available. The test uses its own preferences domain and the retained five quiet baseline fixtures. It plays preview only through BlackHole, creates/removes its own disposable aggregate, and leaves system defaults and existing aggregates untouched.

☼ Production-player checks cover five formats, pause/resume, seeking and EOF, natural completion, missing/corrupt files, rapid replacement and Stop during decoder preparation.
☼ Exact-UID routing rejects disabled, missing, same and shared-aggregate devices. Repeated active/paused output loss must release the player without automatic restart after reconnection.
☼ Audition preferences must not notify main output reconfiguration. Separate main configuration preserves preview; a conflicting main configuration releases preview hardware synchronously.
☼ Start-point preview checks cover absolute offset playback, track-end bounds and request ownership. The popover contract sends its unsaved draft to Audition Output without saving or consuming the one-shot cue.
☼ Music-library checks also cover selection without autoplay, unavailable/multiple selection gating, unchanged double-click Add behavior and preview layout through 200% text. Installed-app interactions, endpoint recordings, physical hardware and long dual playback remain separate checks.

## Track appearance and contrast

Run `bash tests/run-track-appearance.sh`. It triggers production track-cell refreshes before a window update to detect temporary loss of bold text. It checks both size presets and bold states, cells created while bold is enabled, and the compact-history hover guard. Contrast checks cover Light/Dark appearance, reset, cell reuse, repeated redraws, selection colors, clamping and saved settings. The harness uses a separate preferences domain and no audio device. App input and playback checks remain separate.
