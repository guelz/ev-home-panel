# EV Home Panel

<!-- Motivation and pictures go here. -->

A wall-mounted home and EV-charging dashboard for ESPHome + LVGL on an ESP32-P4
with a portrait 800 × 1280 touch display. All data comes from **Home Assistant**
over ESPHome's native API; the panel never talks to the wallbox, the car cloud
or the energy system directly. Charging is managed by **[evcc](https://evcc.io)**,
which reaches HA through a small MQTT bridge (in [`home-assistant/`](home-assistant/)).

This is not a ready-to-go product: it's the author's working configuration, cleaned
up and parametrized so it makes a good starting point for your own panel.

## What it shows

**Page 1 — Laden**
- **Schnellladen** button: toggles evcc between *Schnell* (now) and *Smart*.
- **Bis morgen früh voll laden** button: sets an evcc charge plan (default 90 % by
  the next 07:00) through an HA script; tap again to cancel it.
- Both buttons refuse to *switch on* while no cable is detected and flash
  "Bitte Kabel einstecken!" instead — so nobody assumes the car will charge.
- **Wallbox card**: state (no car / waiting for sun / paused / charging / error),
  the charging power split into **"x kW Netz"** + **"x kW PV"** (evcc's solar share),
  and a gear that opens **"Laden im Normalbetrieb"**: *only with PV surplus* vs.
  *slowly from the grid + PV surplus* (evcc "Dauerhaft laden" / always charge).
- **Vehicle card**: battery icon, SoC, range.
- **Lock** + **Fenster auf / zu** buttons, **Vorklimatisieren** toggle.

**Page 2 — Energie**: PV, house, heat pump, EV, grid and battery gauges with an LED
"comet" flow animation, self-sufficiency (Eigenversorgungsanteil) and a
"Strom heute" table with daily kWh and grid cost.
Sign convention: grid **+** = import, battery **+** = charging; plus always draws clockwise.

**Page 3**: 5-day weather forecast and a rain-water cistern (fill level with a
moving waterline, litres, daily use, pump, last rain).

**Every page**: status bar (HA / evcc / radar connection dots, clock), an air-quality
banner (CO₂ / humidity), presence-based wake/dim with day/night brightness, beeps.

## Hardware

| Part | Used here |
|------|-----------|
| Board | Waveshare **ESP32-P4-NANO** (ESP32-P4 rev1.3, 32 MB PSRAM), Ethernet (IP101), ESP32-C6 Wi-Fi co-processor as fallback |
| Display | Waveshare **10.1" DSI-TOUCH-B**, 800 × 1280, MIPI-DSI (`WAVESHARE-P4-NANO-10.1` preset), GT911 touch |
| Audio | on-board ES8311 codec + speaker (beeps via RTTTL) |
| Presence | HLK-**LD2412** mmWave radar on UART (GPIO20/21) |
| Climate | SHT41 + SCD40 on a second I²C bus (GPIO22/33 — GPIO24-27 are USB lines) |

Other boards work if you replace the hardware blocks of the device YAML and keep the
universal IDs (see [Porting](#porting-to-other-hardware)).

## Software

Tested with **ESPHome 2026.9.1**, **Home Assistant 2026.9**, **evcc 0.317**
(needs ≥ 0.316 for the *Smart* / *always charge* mode names).

HA integrations the example uses — see [`home-assistant/README.md`](home-assistant/README.md):
evcc via **MQTT**, a **WARP3** charger (its MQTT + HA discovery), **kia_uvo**
(vehicle), **huawei_solar** (PV / battery / grid), a **Shelly Pro 3EM** (heat pump),
Met.no **weather**, and an ESPHome cistern controller. Swap any of them for your own:
the panel only sees HA entity IDs.

## Repository layout

```
ev-home-panel/
├── ev-home-panel_waveshare-p4-nano-10.1.yaml   device config: hardware + all substitutions
├── secrets.example.yaml                        copy to secrets.yaml
├── ev-panel/
│   ├── common/        packages: fonts, images, globals, HA subscriptions, scripts, audio
│   ├── sections/      LVGL widget trees (one file per card / popup)
│   ├── texts_de.yaml  every visible text + the glyph sets of the cut-down fonts
│   └── icons/         PNGs, served by HA from /config/www/ev-panel/icons/
├── _fonts/            Crimson Pro (static weights, SIL OFL 1.1)
├── home-assistant/    HA packages, templates, script and helpers the panel reads
└── scripts/           deploy + checks
```

ESPHome composition: top-level keys come in via `packages:` (lists merge across files);
the LVGL widget trees sit deep in `lvgl.pages[].widgets` and come in via `!include`.

## Setup

1. **Home Assistant** — install what you need from [`home-assistant/`](home-assistant/)
   and adapt entity IDs (details in its README).
2. **Icons** — copy `ev-panel/icons/` to `/config/www/ev-panel/icons/`. The panel loads
   them at runtime with `online_image` (keeps them out of the firmware).
3. **Secrets** — copy `secrets.example.yaml` to `secrets.yaml` next to the device YAML
   and fill in the API key, the panel's network settings and `ev_panel_asset_base`
   (`http://<HA address the panel can reach>:8123/local/ev-panel/icons`).
4. **Substitutions** — the top of the device YAML lists **every HA entity** the panel
   reads or writes, grouped by type and in screen order. Point them at your entities.
5. **Build** — put the device YAML, `ev-panel/`, `_fonts/` and `secrets.yaml` into your
   ESPHome config dir (e.g. `/config/esphome/`) and install from the ESPHome dashboard.
   `scripts/deploy.sh` does that for a Samba-mounted HA config dir
   (`EV_PANEL_DEPLOY_DIR=…`; the default path is the author's).

## Substitutions

There are **no defaults** in `ev-panel/` — everything lives in the device YAML (or
`texts_de.yaml`). Note that `esphome config` only *warns* about an undefined
substitution and then shows the raw `${key}` on screen; `scripts/config_snapshot.sh`
turns that into an error.

| Group | Keys | Notes |
|-------|------|-------|
| HA entities | `ha_*` | complete list at the top of the device YAML |
| evcc options | `evcc_mode_off/smart/now` = `Aus`/`Smart`/`Schnell`, `evcc_always_off/on` = `Aus`/`Ein` | **must match** the select options of the HA bridge |
| Charge plan | `ha_plan_script`, `plan_target_soc` (`"90"`), `plan_target_time` (`"07:00"`) | |
| Vehicle | `vehicle_section_title`, `vehicle_watermark_filename` | car name + watermark PNG |
| Cistern | `cistern_wl_{100,50,0}_{x,y}` | waterline position (px from the tank image's top-left) at 100 / 50 / 0 %, interpolated in between |
| Display | `dim_timeout_s` | presence/touch timeout before dimming |
| Assets | `asset_base` (from secrets), `icons_path` | |
| Air banner | `co2_warn_ppm`, `humidity_warn_pct`, `scd40_altitude_m` | |
| Colours | `paper`, `paper_tint`, `paper_edge`, `ink`, `ink_soft`, `ink_mute`, `ink_faint`, `warn_red`, `ok_green` | |

## Texts and translation

All visible texts are in [`ev-panel/texts_de.yaml`](ev-panel/texts_de.yaml) (German),
merged into the device substitutions with `<<: !include`. To translate, copy it to
`texts_<lang>.yaml`, change that include line, and follow the file's header:
keep the printf placeholders listed under `# args:`, respect `# max N bytes`, and
update the glyph sets (`default_glyphs`, `glyphs_kw`, `glyphs_wb_power`) to cover
every character you use. Then run `python3 scripts/check_glyphs.py ev-panel/texts_<lang>.yaml`.

## Checks

| Script | Catches |
|--------|---------|
| `scripts/check_literals.sh` | an HA entity or visible text hard-coded instead of a substitution |
| `scripts/check_glyphs.py <texts file>` | undefined `txt_*` keys, characters missing from a glyph set, broken printf placeholders, texts too long for their buffer, `"` / `\` / line breaks that would break C code |
| `scripts/config_snapshot.sh <device> <out>` | any undefined substitution; writes the resolved config (sorted) for before/after diffs |
| `scripts/test_checks.sh [--slow]` | regression tests for the three checks |

Lambda changes need a full `esphome compile` — `esphome config` doesn't compile them.

## HA action

The device exposes `esphome.<name>_blink_warning(headline, duration)`: flashes the
wallbox status line with a red headline and beeps for `duration` seconds.

## Porting to other hardware

1. Copy the device YAML and replace its hardware blocks (`esp32:`, `psram:`, `i2c:`,
   `display:`, `touchscreen:`, `light:`, networking, radar).
2. Keep the universal IDs `ev_display`, `ev_touchscreen`, `backlight`, `homeassistant_time`.
3. No presence sensor? Leave out the radar; `sb_radar_dot` just stays faint. With one,
   define a `refresh_radar_dot` script in the device YAML.
4. Include exactly one of `common/audio.yaml` (ES8311 speaker chain) or
   `common/audio_stub.yaml` (no speaker) — both provide `beep_click` / `beep_warn`.

## License

Code, configuration and icons: [MIT](LICENSE). Crimson Pro fonts: [SIL Open Font
License 1.1](_fonts/OFL.txt). Roboto is fetched from Google Fonts at build time.
