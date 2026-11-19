# Ruin Digger Roadmap

Living document of planned improvements, ordered by theme. Nothing here is
committed to a release -- items move into CHANGELOG.md when they ship.

---

## Contextual Hints (non-intrusive onboarding)

Small text lines that fade in the first time a player encounters something,
then never appear again. No tutorials, no menus, no "press A to continue."

- First time near water: "water flows into open space"
- First time near gas: "gas ignites near fire"
- First time overheating drill: brief overheat tip
- First time seeing ore: ore-value hint
- First time near a contract board / demolitions counter / mission terminal
- Stored in save so hints only show once per player, not once per run

Design rule: tied to the moment the info is relevant, disappears after a few
seconds, never blocks gameplay.

---

## Encounter Design (generation-driven)

Pre-designed small encounter pockets placed during generation, same footprint
system rooms and landmarks already use. Each is a deliberate layout that
showcases a specific enemy or hazard interaction.

Ideas:
- Dead-end chamber with a brute guarding a rich ore vein
- Flooded cave with eels (reward behind the water)
- Burrower nest in a pocket of soft rock
- Gas-filled room near explosive barrels or ore that sparks
- Spore pod cluster blocking a narrow passage
- Bomb-eater lurking near a placed explosive cache

Restraint: 1-2 per zone max so they feel like discoveries, not wallpaper.
Generation must respect existing fairness rules (DigCheck, GenSpace claims).

---

## Economy & Upgrade Pacing

Current upgrades are too easy to buy. The fix is more options at higher prices,
not stretching out the existing ones.

Desired curve:
- **Early upgrades** -- cheap, feel good, hook the player
- **Mid-tier upgrades** -- meaningful choices (blast radius vs. capacity?)
- **Late-tier upgrades** -- expensive aspirational goals that change playstyle

Concrete steps (when ready):
- Audit current upgrade costs vs. average credits-per-run
- Add more upgrade tiers / branches to existing tracks
- Introduce new upgrade tracks for systems that lack them
- Tune contract and mission rewards to match the new price curve
- Make sure no single run can buy everything -- progression should span many runs

---

## Touch Controls Simplification

The current button count (drill, jump, charge, charge2, interact, DIAG) works
for experienced players but may overwhelm newcomers.

Ideas:
- "Simplified controls" preset: hides DIAG and second charge slot by default
- Power users toggle extras on in settings
- Possibly auto-show buttons as players unlock the systems that use them
  (e.g. charge2 only appears after packing a backup explosive)
- Revisit button sizing and spacing based on play-test feedback

---

## Future Ideas (unscheduled)

- Optional tutorials accessible from the main menu (not required)
- Harder mission variants with pressure, deeper lakes, tighter budgets
- More relic variety and relic-driven build diversity
- Enemy encounter escalation tied to depth / zone progression
- Performance optimization pass informed by Perf recorder data
