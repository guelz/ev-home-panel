# Home Assistant side

Everything the panel reads or writes is a plain HA entity. Some come straight from
integrations, the rest from the files in this folder. They are the author's live
configuration: use them as examples and adapt the entity IDs to your setup — then
point the panel's `ha_*` substitutions at the result.

Expected `configuration.yaml` includes:

```yaml
homeassistant:
  packages: !include_dir_named packages
template: !include_dir_merge_list templates/
utility_meter: !include_dir_merge_named utility_meter/
script: !include scripts.yaml
```

## Files

| File | Provides (panel substitution → entity) | Needs |
|------|-----------------------------------------|-------|
| `packages/evcc_wallbox.yaml` | `ha_wb_mode_select` → `select.evcc_lademodus` (Aus/Smart/Schnell), `ha_wb_always_charge_select` → `select.evcc_dauerhaft_laden`, `ha_en_ev_daily` → `sensor.evcc_heute_geladen`, `ha_plan_soc` → `sensor.evcc_ladeplan_ziel`, `ha_wb_green_share` → `sensor.evcc_solaranteil_ladepunkte`, `ha_statusbar_evcc_online` → `binary_sensor.evcc_online` (+ a few more evcc sensors) | HA MQTT integration on the same broker as evcc; evcc's MQTT enabled (topic root `evcc`). evcc sends **no** HA discovery, so the entities are declared by hand. Loadpoint 1 = the EV charger — change the topics if yours differs. |
| `scripts/evcc_ladeplan_bis_morgen.yaml` | `ha_plan_script` → `script.evcc_ladeplan_bis_morgen` | Set `vehicle:` to your evcc vehicle **name** (`db:<n>` for UI-created vehicles, see `/api/state`). |
| `packages/ev_panel_helpers.yaml` | `ha_wb_idle_soc_threshold`, `ha_wb_blink_soc_threshold` → two `input_number`s | — |
| `templates/ev_panel_weather.yaml` | `ha_we_d{0..4}_{high,low,cond}` → `sensor.evp_weather_d*`, `ha_ci_rain_text` → `sensor.evp_letzter_regen_text` | a `weather.*` entity with daily forecasts (`weather.forecast_home` = Met.no default); `binary_sensor.regen` (rain sensor) for "letzter Regen" |
| `templates/dash_power_sensors.yaml` | `ha_en_*_power`, `ha_en_line_*` → `sensor.dash_*` (W) | **huawei_solar**: `sensor.inverter_input_power`, `sensor.inverter_active_power`, `sensor.power_meter_active_power`, `sensor.batteries_charge_discharge_power` — map these to your inverter |
| `packages/dash_energy_sensors.yaml` | `ha_en_*_daily` → `sensor.dash_*_energy_daily` (kWh, daily reset) | the `dash_*` power sensors above |
| `packages/dash_cost_sensors.yaml` | `ha_en_price_import`, `ha_en_price_export` → `sensor.dash_price_*` (CHF/kWh) | your tariff in the `input_number`s (the header shows how the example price is derived); PV/battery LCOE uses example install costs |
| `utility_meter/waermepumpe.yaml` | `ha_en_wp_daily` → `sensor.daily_energy_warmepumpe` | an energy counter of the heat pump (here a Shelly Pro 3EM channel) |

## Straight from integrations

| Panel substitution | Example entity | Integration |
|--------------------|----------------|-------------|
| `ha_wb_cable`, `ha_wb_charging`, `ha_wb_error`, `ha_wb_power` | `binary_sensor.warp3_<id>_cable` …, `sensor.warp3_<id>_powernow` (W) | WARP3 charger, MQTT + HA discovery enabled in its web UI |
| `ha_range_sensor`, `ha_soc_sensor`, `ha_lock_entity`, `ha_climate_entity`, `ha_lock_windows_*_button` | `sensor.niro_ev_range`, `sensor.niro_ev_battery_level`, `lock.niro_door_lock`, `climate.niro_climate_control`, `button.*_open_all_windows` | kia_uvo (Kia / Hyundai) — any car integration with SoC + range works |
| `ha_en_batt_soc` | `sensor.batteries_state_of_capacity` | huawei_solar |
| `ha_en_wp_power` | `sensor.<shelly>_energy_meter_0_power` | Shelly |
| `ha_ci_*` | `sensor.cistern_controller_zisterne_fill` … | ESPHome cistern controller (optional page) |
| `ha_sun` | `sun.sun` | built-in — picks day/night backlight brightness |

The panel needs permission to call HA actions: Settings → Devices & Services →
ESPHome → the panel → *Configure* → "Allow the device to perform Home Assistant actions".

`retain: false` on every MQTT command topic matters: a retained command would be
replayed after each broker reconnect and silently override settings.
