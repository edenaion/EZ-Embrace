# Embrace

[Embrace](https://www.ricciadams.com/projects/embrace) is a music player designed for the unique challenges of DJing social dance events. It focuses on playing back a single set list without audio glitches or accidental interruptions.

## EZ-Embrace additions

☼ Click or drag the playback bar or Current Track waveform to seek within the playing song. Dragging previews the position and commits on release; Escape cancels. With the control focused, Left/Right seek five seconds, Shift changes the step to fifteen seconds, and Home/End select the boundaries.

☼ Settings > Appearance offers text sizes from 100% to 200% and an independent bold option. Text size also enlarges controls and spacing to keep the layout readable. Existing "Use Larger Text" preferences migrate to 125%.

☼ Settings > Appearance includes a saved Text contrast slider. Raise it for darker text in Light mode or brighter text in Dark mode. Zero restores default text colors. Selected rows retain their native selection colors.

☼ Enable "Scale interface with window size" to enlarge a window's contents uniformly while resizing. Window proportions stay fixed, and each window scales independently. Current Track is temporarily unpinned while this setting is enabled.

☼ Effects > Add > Parametric Equalizer uses EmbraceNG's custom EQ core and editor. It provides four bands, a low-cut filter, and output trim. Gains start flat. Existing Apple effect chains retain their saved settings. The custom EQ supports the same window scaling and bold preferences.

☼ Effects > Add also includes separate Declick and Dehum restoration modules. Declick repairs short impulse damage with a look-ahead autoregressive model. Dehum detects and suppresses steady mains hum or transfer tones, with optional rumble filtering. Both modules expose saved, editable parameters and can be bypassed without losing their current settings.

☼ EQ editors have Violin and Singer preset shortcuts to the left of Flat. The custom Parametric Equalizer ships with both presets ready to recall. Right-click an icon or open Actions to replace it with the current EQ; your replacement takes priority over the bundled preset and survives restart. The 10-band and 31-band EQs have separate slots: click an empty shortcut and choose Save current EQ, then recall it in one click.
☼ The EQ button below the Set List menu enables or bypasses the custom Parametric Equalizer and opens its panel. Blue means on; gray means off, including when the editor has focus. Repeated clicks bring the same panel forward. Existing curves stay intact, other effects are unaffected, and the on/off state survives restart. If none exists, enabling EQ adds one flat parametric equalizer and opens its panel.
☼ The large bold ON/OFF button above the parametric EQ graph enables or bypasses the same EQ as the Set List button. Both show blue when on and gray when off, including changes made through Actions. Toggling keeps the current curve and window dimensions.
☼ The parametric curve previews current settings even while bypassed: gray when off, blue when on. Violin, Singer and Flat buttons turn blue when their settings match and EQ is enabled. Other preset buttons stay gray. Recall while bypassed prepares a curve without enabling processing.
☼ Flat turns low-cut off and sets all EQ gains and output trim to 0 dB for a completely flat response. Frequencies and Q stay stored for later edits. Enabling low-cut clears the Flat highlight even when gains remain at zero.

☼ Current Track is resizable, with the playing title and artist centered above the waveform and below the window controls. Long metadata truncates with the full text available in a tooltip. Metadata clears when playback ends. Pin to Bottom keeps the window across the screen while allowing its height to change.

☼ The Set List seek bar has a 24-point clickable area, an 8-point track, and a larger position marker. A persistent tint and speaker icon identify the playing row. Played and queued counts explain the list's retained history.

☼ Output meters use LED segments: green below -12 dBFS, amber from -12 to -3 dBFS, and red near full scale. A separate red dot marks overload or safety limiter activity. Volume-slider color follows the measured signal. Audio gain and the safety limiter retain their existing behavior.

☼ Window > Music library (Option-Command-4) opens a separate resizable, read-only browser for Music/iTunes playlists. Search the selected playlist, click column headings to sort, or choose additional metadata from Columns. Playlist order restores the source order exposed by Apple's library API. Drag tracks or a playlist into the Set List, or select tracks and click Add to Set List. Music does not need to be open. EZ-Embrace cannot rename, reorder, add or delete Music content. The browser displays no album artwork. Cloud-only, protected and unavailable files cannot be added for playback.

☼ Settings > General enables daily Music library snapshots by default. After the first successful scan each day, EZ-Embrace atomically stores track metadata, playlist hierarchy and ordered membership outside the Music folder. Back Up Now creates a separate recovery point; the app retains 30 daily snapshots, up to 12 older monthly snapshots and the 20 newest manual snapshots. Snapshots contain no songs or artwork and never restore into Music automatically. Use Time Machine or another full backup for audio files and Music's private database.

☼ Settings > General has a separate Audition Output for Music library headphone preview. Choose a second output device, select one local song in the library and click Preview. Preview has its own Pause/Resume, Stop, position and saved volume, initially 25%. Selecting a row does not start audio; double-click still adds it to the Set List. Closing the library stops preview. A missing or conflicting output stops preview without switching to speakers, and reconnecting never starts it automatically. Devices that share aggregate subdevices cannot serve as separate outputs. Channel pairs on one interface are not supported by this selector.

☼ Settings > Appearance offers independent border colors for Set List, Current Track and Music library. Each color well opens the system color wheel. A fine inset edge uses a light vertical gradient and rounded corners. Changes apply immediately and survive restart. Default resets one border; Reset border colors restores all three native borders.

Run the focused native checks using [the feature regression harness](tests/README.md). Tahoe compatibility requires runtime testing on each intended OS and audio-device configuration.

The custom parametric EQ, Declick and Dehum modules, and their regression checks are adapted from [EmbraceNG](https://github.com/shaforostoff/EmbraceNG/tree/1c3b15bf8e56e8b2cfbecbb675c474b0caf45668). Declick and Dehum use the portable DSP cores integrated there from [shellacfilters](https://github.com/shaforostoff/shellacfilters). Apple preset validation and editor teardown fixes come from commits `f01944d4` and `aeaf918a`; the effect-chain reset correction comes from `80a7b8b`. Copyright 2025-2026 EmbraceNG contributors and 2026 Nick Shaforostov, under the [MIT license](LICENSE.EmbraceNG).

Apple N-band EQ presets retain the unit's current band count to avoid a crash in Apple's editor. The custom parametric EQ has a fixed parameter layout and its own preset state.

## Philosophy

Audio programming is hard. macOS audio programming is harder (usually due to sparse documentation). This repository is publicly-viewable in the hopes that its source code can help others.

Embrace is feature-complete and closed to outside contributions.

If you are struggling with an audio or DSP concept, you can contact me via my [contact form](https://www.ricciadams.com) and I can try to point you in the right direction.

## License

I only care about proper attribution in source code. While attribution in binary form is welcomed, it is not necessary.

Hence, unless otherwise noted, all files in this project are licensed under both the [MIT License](https://github.com/iccir/Embrace/blob/main/LICENSE) **or** the [1-clause BSD License](https://opensource.org/license/bsd-1-clause). You may choose either license.

`SPDX-License-Identifier: MIT OR BSD-1-Clause`
