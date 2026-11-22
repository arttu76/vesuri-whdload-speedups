# Open work

Aquaventura Enhanced 2.0b (22.11.2026) on Bored Seal's and StingRay's v1.3 slave. CUSTOM1
(Enhanced framerate) runs the game's code from fast memory, steps the game every 6 fields
(the A500's average pace, CUSTOM2) and draws frames between the steps with the movement
scaled to their time ([internals](internals.md#enhanced-framerate-custom1)). It needs a
68020 or better and 108 KB of ExpMem. Without CUSTOM1 the slave is v1.3. `make dist`
builds `AquaventuraEnhanced-2.0b-20261122.lha`. The release is not published.

Tested in the emulator only: the pace and the frame rates on five setups
([internals](internals.md#measurements)), the frames between over levels 1 to 7 with
`tools/verify.sh`, the release build's intro and title. Not tested: play with a joystick,
the tunnel by eye, real hardware.

## Before a first release

1. Play-test on the owner's A600 with a Furia (68020 at about 37 MHz): the 3D levels, the
   tunnel, a level end, a game over and a new game, the pause key, the options. Look for
   wrong colours or missing objects (code that changes itself, in the copy), for objects
   that jump once per step, and for sound effects that play twice.
2. Play-test on a 68030 or better with an MMU, where WHDLoad caches the ExpMem.
3. Compare the game's speed with an A500 by feel, and decide the default step (6 fields).
4. Publish with a tag and a release archive as the other games (`docs/releasing.md`).

## Candidates

- The Furia-like setup needs 2.3 fields of work per pass and so draws every third field.
  Under 2 fields it would draw 25 frames a second. Candidates: the vertex buffer (`$1368`)
  in fast memory, the text plotters and the sprite draw in the copy (they change their own
  code: one loop per colour as for the span fill, or a cache flush), the level 3 handler's
  sound driver in the copy, saving only the objects that are active.
- Frames between in the tunnel (`$b0`).
- The beam-position random numbers the same in a frame between and its step.
- Find the routine that animates model data, and save what it writes instead of the fixed
  ranges.
