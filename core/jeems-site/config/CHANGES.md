# 2x4 Brain — revised config: what changed

A rewrite of your ESPHome crop-steering config based on your notes. Files:

- `2x4-brain.yaml` — the main config (one file, as you prefer).
- `fragments/vpd.yaml` — reusable VPD + leaf-VPD sensors (the de-dup example).
- `fragments/shot_calc.yaml` — reusable P1/P2 irrigation-time + shot-volume calc.

> **Before flashing:** run `esphome config 2x4-brain.yaml` on your machine (you
> have the u-fire external component + secrets; I don't, so I validated syntax
> against the ESPHome source and a YAML parse, not a full compile). Keep the
> `fragments/` folder next to the yaml so the `!include` paths resolve.

Everything is tagged in the yaml with `# >>> CHANGED` / `# >>> NEW` so you can
diff against your original.

---

## Your requests → what I did

**1. Run as much as possible without the HA API, and don't reboot on disconnect.**
- `api: reboot_timeout: 0s` and `wifi: reboot_timeout: 0s`. Those default to
  **15 min** — that default is what reboots the board when HA/Wi-Fi drops. Now it
  never reboots on a disconnect; it just keeps running.
- Timekeeping moved off HA: `platform: sntp` (internet time) + your existing
  `ds1307` RTC for holdover. `on_boot` reads the RTC into system time so the clock
  is valid before Wi-Fi/HA even connect; SNTP re-writes the RTC whenever it syncs.
- Sensing, dosing (local relays), phase tracking and the clock now all run with HA
  absent. The one thing that still needs HA is the **irrigation pump** (it's on an
  HA-controlled plug). See the pump note at the bottom for making that local too.

**2. P1-frequency crash — already fixed by you.** I also set `p1_frequency`
`min_value: 1` and guard `freq > 0` in the tick, so 0 can't sneak back in.

**3. Maintenance / lights-on / lights-off / P2-window-close as ESPHome entities.**
- **Maintenance mode** is now a local `switch` (`maintenance_mode`), not an HA
  input_boolean. Every guard uses it, fail-safe (unknown = not-dosing).
- **Lights-on / lights-off / P2-window-close** are now local `datetime` **time**
  entities — settable from the dashboard/web UI and restored across reboots.
- The scripts fire on a **minute match** (not the old exact-second string compare).
- **Boot / re-sync catch-up:** the once-a-minute tick checks, if it's already past
  lights-on and today's run was missed (reboot, offline, etc.), it runs lights-on;
  if it's outside the light window and not already in P3, it settles into P3.

**4. Cleaned P1/P2 scripts (+ HA checks, loops, delays) and added P3.**
- The hanging `while ipump …` pump-confirm loops are **gone** — those were what
  wedged the controller (and could leave the pump on) when HA hiccuped.
- All watering goes through one parameterized `shot(seconds)` script: pump on →
  wait → pump off. No confirm loop, so it can't hang. If HA drops mid-shot, the
  turn-off may not land, but your plug + HA auto-off is the stuck-pump safety net.
- P1/P2/P3 events guard `api.connected` and **skip cleanly** (log + move on)
  instead of blocking when HA is down.
- The phase logic is now mostly in lambdas (you said that's fine) — shorter and
  easier to follow than the nested YAML action trees.
- **New `p3event`**: during P3, if VWC drops to the low limit, it gives one
  emergency shot. Previously P3 had no watering at all and the low-VWC "alarm" was
  never acted on.
- P2 frequency is now a proper time gate (`millis()` deadline) instead of holding
  the script open with a multi-minute blocking `delay` (which dropped needed shots
  and was lost on reboot).
- Fixed the `startP3` end-of-day shot: it no longer double-counts as a P1 shot, and
  it reuses the shared `shot` script.
- Field-capacity detection now ignores the `0` baseline on a fresh/reset device
  (the old guard `field_capacity - VWC <= 10` was always true at FC=0).

**5. Example of replacing the copy-pasted calcs with includes.**
- The **6** VPD/leaf-VPD lambdas → one `fragments/vpd.yaml`, pulled in 3× as
  `packages:` (once per air sensor). This also fixed a real bug: the copies had
  **drifted constants** (ambient used `0.6108/17.27/237.3`, leaf used
  `0.61078/17.2694/237.3`) — now one canonical set, plus NaN guards.
- The **4** P1/P2 shot-math lambdas → one `fragments/shot_calc.yaml`, pulled in 2×.
- Kept to **two** fragment files; everything else stays in the main yaml, per your
  preference. Packages are the trick that lets a shared file's sensors merge into
  the main `sensor:` list (list values concatenate on merge).

**6. Flash life.**
- `flash_write_interval: 60min` kept (that part was already correct).
- `restore_value` removed from the churny per-cycle counters (`p1_shot_count`,
  `daily_irrigation_events`, `ph_dose_counter`, `ec_dose_counter`) — they reset
  each morning anyway, so persisting them only wore the flash.
- Config values (targets, tolerances, shot sizes, steering phase, the new
  datetimes) still restore.

**7. Unused things kept; dimmers are for lights.**
- `rs232`, the `spi` bus, the TDS sensors and `relay_6` are all left in place for
  later. The DAC `Dimmer 1/2` lights are untouched (note: `gamma_correct: 2` warps
  the curve for perceived-brightness; if your 0-10V light drivers want a linear
  ramp, set `gamma_correct: 1.0` — left as-is since that's your call).

**8. Redundant pump auto-off.** Noted — because your plug and HA both auto-off a
stuck pump, the on-device side just needs to not hang and not require HA, which is
what the new `shot` script does. No on-device watchdog added (your two external
ones cover it); easy to add if you ever want a third belt.

---

## Left as-is (flagged, not changed — your call)

- **Nutrient dosing** still regulates on `EC2` (a *soil* probe, not reservoir EC)
  and never pulses `relay_5` (Pump C). I only swapped its maintenance guard to the
  local switch. Wire a reservoir EC sensor and add a Pump-C step when ready.
- **pH dosing** now waits a full 15 s (one sensor update) after each dose before
  re-deciding, to avoid overshoot on a stale reading.

## Making watering fully HA-independent (optional)

The pump is the last HA dependency. To cut it: wire the pump to a board relay
(e.g. the spare `relay_6`) and, in the `shot` script, replace the two
`homeassistant.service` calls with `- switch.turn_on: relay_6` /
`- switch.turn_off: relay_6`. Then watering works with HA completely offline.
