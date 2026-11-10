# Instructions for the agent continuing Ruin Digger 0.5

You are picking up unfinished work on **Ruin Digger** (Godot 4.6.3, GDScript,
Android-first mining roguelite). A previous agent built almost all of version
0.5 and stopped at a checkpoint with 3 known bugs. Your job is to fix those
bugs, verify, and finish the release steps. **It is a small, narrow job. Do not
redesign anything.**

## 0. Branch rules (do this first, exactly)

```bash
git clone https://github.com/narmanb/ruindigger
cd ruindigger
git fetch origin ccr-79c19570-j1j312
git checkout -b finish-0.5 origin/ccr-79c19570-j1j312
```

* Work **only** on `finish-0.5`. Push only to `finish-0.5`.
* **Never** push to, force-push, rebase, reset or delete
  `ccr-79c19570-j1j312`. It is the backup of all previous work.
* **Never** touch `main`. Do not merge anything. Do not open a pull request
  unless the owner asks.
* Never use `git push --force` on any branch.
* The code checkpoint you are starting from is commit `f571c73`. If you ever
  need to see what you changed: `git diff f571c73 -- src/ tests/`.

## 1. Read before you change anything

In this order:

1. `docs/PHASE4_HANDOFF.md`: status, the failing checks, architecture notes,
   ordered next steps. **This is your main reference.**
2. `AGENTS.md`: project rules. They are binding.
3. `docs/generation-v3.md`, then skim `docs/generation-v2.md`: how generation
   works and why.

## 2. Set up and confirm the starting state

You need Godot **4.6.3** on the path as `godot`. (Python 3 with numpy and
Pillow is only needed if you regenerate art, which this job should not need.)

```bash
godot --headless --import
timeout 900 godot --headless res://tests/test_runner.tscn -- suite=gen seeds=60 2>&1 | grep -E "FAIL|RESULT|repair"
```

You must see **3803 passed, 4 failed** and `seeds needing repair: 0`, with
these failures:

* `seed 103947: no reserved footprints overlap [["terraces_0_16", "floodgate"]]`
* `seed 365274: no sealed pockets (7)`
* `seed 428626: crawler not spawned in rock` (twice)

If you see something different, **stop and report it**. Do not start fixing.

## 3. The work, in order

Do one item at a time. After each fix, rerun the gen suite (command above).

1. **Sealed pockets (seed 365274).** Suspected cause: `_seal_traps` in
   `src/gen/mine_generator.gd` turns trap cells into alloy/bedrock and can
   leave the air above them enclosed. Confirm the cause first, then fix.
2. **Crawler in rock (seed 428626).** Cause unknown. Find which pass puts rock
   on the crawler's cell (or places the crawler in rock). `RD_CELL=x,y` prints
   a cell's material after every pass (see the handoff, section 6).
3. **Floodgate overlap (seed 103947).** In `src/gen/landmarks.gd`,
   `floodgate()` claims a shell that overlaps the chamber it attaches to.
4. Gen suite must now show **0 failed** and `seeds needing repair: 0`.
5. Run everything:
   ```bash
   TEST_TIMEOUT=900 ./tools/run_tests.sh
   timeout 300 godot --headless res://tests/test_runner.tscn -- suite=water_live
   ```
   All suites must pass.
6. Run the sweep (about 13 minutes):
   ```bash
   timeout 3000 godot --headless res://tests/gen_report.tscn -- seeds=125 out=/tmp/report.csv
   ```
   Required: `invalid or repaired: 0` and the `traps` line showing `max 0.00`.
   If `gen_ms` max is over 1500, find that seed in the CSV and profile it with
   `RD_PROFILE=1` (handoff, section 6). Report what you find even if you do
   not fix it.
7. Update the numbers that are now stale: the "Last local run" paragraph in
   `README.md`, the results table in `docs/generation-v3.md` (it has a
   placeholder), and remove "(in progress, not released ...)" from the 0.5.0
   heading in `CHANGELOG.md`. Write only numbers you measured.
8. Build the APK if your environment can:
   `godot --headless --export-debug "Android" build/android/ruin_digger.apk`.
   If it cannot, say so. Do not fake it.
9. Commit and push to `finish-0.5`. Then write the final report (section 6).

## 4. Hard rules

* **Fix the generator, not the tests.** Do not delete, skip, loosen or
  special-case a test to make it pass. Do not hard-code seed numbers into the
  game code. If you believe a test is genuinely wrong, stop and explain why
  instead of changing it.
* **Do not rewrite or restructure.** No renaming files, no "cleanup", no new
  architecture, no new features. If a fix needs more than roughly 60 changed
  lines, stop and explain your plan first.
* **Do not change game design numbers** (world size, zone layout, budgets,
  costs) to get around a bug.
* **Generation must stay deterministic** and must keep
  `seeds needing repair: 0`. The repair fallback existing is not a licence to
  rely on it.
* `MineGenerator` pass order matters. Trap sealing runs inside
  `_validate_and_repair`, **after** enemies and hp are finalised. Any code
  that edits terrain there must also clean up entities, water, ore and hp for
  the cells it touches.
* Use `grid.get_stratum(x, y)` for the zone of a cell, never row arithmetic.
* Tuning numbers go in `src/autoload/balance.gd`. GDScript is typed, with
  tabs; `:=` needs a typed right-hand side.
* Never hand-edit files in `assets/gen` or `assets/sfx`.
* **Never claim a test, sweep, build or benchmark result you did not run and
  see.** Paste the actual result lines. If you skipped a step, say so.
* Nothing has been tested on a phone. Do not write that it has.

## 5. Practical warnings

* Always wrap Godot runs in `timeout`. A scene whose script has a parse error
  never exits on its own.
* Do not run `pkill -f godot`. Kill by process id if you must.
* "ObjectDB instances leaked at exit" at the end of a headless run is
  harmless.
* After adding a new `.gd` file with a `class_name`, run
  `godot --headless --import` before using it.
* To reproduce one test seed: the suite uses seed `1000 + i * 7919` with
  contract index `i % 4`, so `i = (seed - 1000) / 7919`. Then:
  `godot --headless res://tests/gen_dump.tscn -- seed=<seed> contract=<i % 4> out=/tmp/m.png`

## 6. Final report (required)

When done, or if you get stuck, report:

1. Branch and commit hash on `finish-0.5`.
2. For each of the 3 bugs: the confirmed cause, the fix, files changed.
3. The exact result lines of: the gen suite, `run_tests.sh`, `water_live`,
   and the sweep (`combos`, `gen_ms`, `traps`, `invalid or repaired`).
4. Whether the APK was built, and how you verified it.
5. Anything you did not do, and why.
6. Anything that surprised you or looks wrong but was out of scope.

If you cannot fix a bug after a reasonable effort, **commit what works, leave
the failing test failing, and say so plainly.** A truthful partial result is
far more useful than a green suite obtained by weakening a check.
