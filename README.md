# hkrr-autosplitter
LiveSplit autosplitter for Hello Kitty: Roller Rescue on Dolphin (Windows, NTSC-U)

# Hello Kitty: Roller Rescue Autosplitter

A LiveSplit autosplitter for speedrunning **Hello Kitty: Roller Rescue** on Dolphin. It starts the timer when the first mission finishes loading, pauses Game Time between missions, and splits at **Mission Clear**.

**v0.3 Beta** was tested on a complete Any% run. LiveSplit recorded all 16 splits automatically and stopped at **53:00.09 Game Time**. Testing on more Windows and Dolphin setups is welcome.

## Requirements

- Windows with 64-bit Windows PowerShell
- Dolphin Emulator
- LiveSplit with the built-in TCP server
- The NTSC-U GameCube version of Hello Kitty: Roller Rescue (`GH6EAF`, revision `0`)
- A LiveSplit Any% split file with 16 segments and a zero start offset

## Setup

1. Download `HKRR-Autosplitter-v0.3-beta.zip` from [Releases](../../releases) and extract the entire archive into one folder.
2. Open LiveSplit and load your Any% splits. For beta testing, use a copy of your splits. Reset the timer and disable any other autosplitter attached to the run.
3. In LiveSplit, open **Control → Start TCP Server**. The autosplitter connects to `127.0.0.1` on port `16834` by default.
4. Open the game in Dolphin. Once you are in Kitty's house, pause emulation using Dolphin's **Pause** command.
5. Run `Start-LiveSplit.cmd` and press **Enter** in the console. Resume emulation and start your first mission.
6. When you're done, focus the autosplitter console and press **Q**. The script saves a diagnostic ZIP next to the launcher.

To check game-state detection without controlling LiveSplit, follow the same Dolphin steps and run `Start-Preview.cmd` instead. The console will show the timer commands it would send.

## How timing works

- **Start:** LiveSplit starts when the first mission finishes loading.
- **Between missions:** Game Time stays paused in Kitty's house, at the door prompt, on the mission selection screen, and during loading. It resumes once the next mission finishes loading.
- **Mission Clear:** The autosplitter pauses Game Time as the game transitions to the results screen and sends one split when it detects Mission Clear.
- **Failure and retry:** A failed mission does not trigger a split. Game Time pauses during the retry transition and resumes when the mission finishes loading again.
- **Finish:** LiveSplit ends the run when the final split fills the last segment.

## Known limitations

- Pausing Dolphin during an active mission can leave Game Time running.
- Restarting the game or loading a save state during an active run is unsupported.
- A completed or reset run may need a fresh autosplitter session. Close the script with **Q** and launch it again before starting another attempt.
- The script reads Dolphin's memory periodically. Frame-perfect timing and compatibility with other game regions or revisions are unverified.

## Beta feedback

Short tests are welcome. In particular, try completing two missions in one session, failing and retrying a mission, or running the autosplitter on a different Dolphin version.

If you encounter a problem, open an issue with your **Dolphin version**, **LiveSplit version**, the **mission or screen** where it happened, and what you expected the timer to do. Attach the diagnostic ZIP if available.

## Credits

Original author: xperimenting0_0/2muchKuromiPlushies/Carti

## License

The source is available under the MIT License. See LICENSE for the terms.
