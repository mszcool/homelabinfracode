# Onboarding a New Tasmota Power Switch

Step-by-step procedure to onboard a Tasmota-flashed power switch (e.g. Sonoff, Shelly w/ Tasmota) into the homelab, including MQTT integration, static IP assignment and (optional) power-measurement calibration.

> Scope: applies to any Tasmota device acting as a relay/switch (with or without energy monitoring). Assumes the device is already flashed with Tasmota firmware.

---

## 1. Initial Wi-Fi Provisioning

Tasmota boots into AP mode (`tasmota_XXXX`) on first start. To configure it on the **same Wi-Fi network it will later live on**, use a **staging Raspberry Pi** that mirrors the target Wi-Fi.

- **Edge / outdoor devices** (e.g. pool pump switch in the maintenance shaft):
  - Use the staging Pi that is preconfigured with the **exact SSID + PSK** of the target outdoor Wi-Fi (e.g. *Pool Maintenance Shaft Wi-Fi*).
  - This allows full indoor configuration before physically deploying the device outside.
- **Indoor IoT devices**: use the staging Pi with the **House IoT Wi-Fi** SSID/PSK.

### Steps

1. Power on the staging Pi (it should bridge / re-broadcast the target Wi-Fi, or simply be on that Wi-Fi so the Tasmota can reach it).
2. Power on the Tasmota device.
3. Connect a laptop to the `tasmota_XXXX` AP.
4. Browse to `http://192.168.4.1`.
5. Enter the **target Wi-Fi SSID and password** (the one matching the deployment location).
6. Save — device reboots and joins the target Wi-Fi.
7. Find its DHCP-assigned IP (router lease table or staging Pi `arp -a`).

---

## 2. MQTT Configuration

Open the Tasmota web UI → **Configuration → Configure MQTT**.

Use values from the homelab inventory:

| Field | Source |
|---|---|
| **Host** | IP of the MQTT broker from `configs.private/envprod/inventory/group_vars/mainrouter/networking-foundation.yaml` (the mosquitto broker entry) |
| **Port** | `1883` (default, unless overridden in inventory) |
| **User** | MQTT user defined in `apps-mosquitto-configuration.yaml` |
| **Password** | Corresponding password from 1Password / vault |
| **Topic** (device topic) | Unique device identifier, e.g. `pool-pump`, `garage-light` — this becomes `%topic%` |
| **Full Topic** | `%topic%/%prefix%/` |

> **Important**: the full-topic pattern `%topic%/%prefix%/` (device first, then `cmnd`/`stat`/`tele`) is the convention used by the homelab MQTT topics translator. Do not change it.

Click **Save** — the device reboots and connects to the broker. Verify with:

```bash
mosquitto_sub -h <broker-ip> -u <user> -P <pass> -t '<device-topic>/tele/#' -v
```

---

## 3. Secure the Device

In the Tasmota web UI → **Configuration → Configure Other**:

- Set **Web Admin Password** (`WebPassword`) to a strong password.
- Store the password in **1Password** (or the configured vault) under the device entry.
- Optional: set a friendly device name and template if not auto-detected.

---

## 4. Static IP + Inventory Registration

Assign a **static DHCP reservation** by MAC address (preferred over Tasmota-side static IP).

1. Read the device MAC from Tasmota → **Information** page (`STA MAC`).
2. Open `configs.private/envprod/inventory/group_vars/mainrouter/networking-foundation.yaml`.
3. Add an entry under the `iot-devices` group with:
   - `name`: device topic / hostname
   - `mac`: MAC address
   - `ip`: chosen static IP from the IoT subnet range
4. Re-run the relevant networking playbook to push the reservation to the router/DHCP server.
5. Reboot the Tasmota — confirm it now holds the static IP.

---

## 5. Power-Measurement Calibration (Optional)

Only for switches with built-in energy monitoring (e.g. Sonoff POW, Shelly Plug). Calibrate against an **external reference power meter** and a **known resistive load** (incandescent light bulb is ideal).

### Required tools

- External plug-in power meter (showing **V**, **A** or **mA**, **W**).
- Two light bulbs of **different wattages** (e.g. 40 W and 100 W) for cross-validation.

### Calibration procedure

1. Plug the **reference power meter** into the wall, plug the bulb into the meter, switch the bulb **ON**.
2. Record from the reference meter:
   - **Voltage** (V)
   - **Current** (mA — if the meter shows A, multiply by `1000`)
   - **Power** (W)
3. Move the bulb to the **Tasmota switch**, leave it **ON**.
4. Open Tasmota → **Console** and run (one per line):
   ```
   VoltageSet <Volts>
   CurrentSet <Milliamps>
   PowerSet <Watts>
   ```
5. Verify calibration:
   ```
   Status 8
   ```
   Toggle the bulb on/off and confirm Tasmota's reported values match the reference meter.
6. **Cross-check**: swap to the second (different-wattage) bulb. Compare Tasmota readings vs. reference meter — values should match within a small tolerance. If not, repeat calibration with the new load and pick a midpoint.

---

## 6. Power-On Behavior (`PowerOnState`)

If the switch turns on unexpectedly after a power cycle, adjust `PowerOnState` via the Tasmota Console.

| Value | Behavior |
|---|---|
| `0` | **OFF** after power restored *(recommended for pool pumps, heaters, anything that must not auto-start)* |
| `1` | **ON** after power restored |
| `2` | **Restore previous state** before power loss |
| `3` | **Invert** previous state (toggle) |

Set with:

```
PowerOnState 0
```

> **Recommendation**: use `PowerOnState 0` for safety-sensitive loads (pool pump, water heater). Use `2` only when intentional auto-resume is desired.

---

## 7. Verification Checklist

- [ ] Device joined target Wi-Fi and reachable on its static IP.
- [ ] MQTT `tele/STATE` messages visible on the broker.
- [ ] Web admin password set and stored in vault.
- [ ] MAC + static IP entry added to `networking-foundation.yaml` under `iot-devices`.
- [ ] (If applicable) `Status 8` readings match reference meter for two different loads.
- [ ] `PowerOnState` set appropriately for the load type.

---

## References

- Broker / network inventory: [configs.private/envprod/inventory/group_vars/mainrouter/networking-foundation.yaml](../configs.private/envprod/inventory/group_vars/mainrouter/networking-foundation.yaml)
- Mosquitto user config: `apps-mosquitto-configuration.yaml` (inventory)
- MQTT topic translation: [homelab.mqtt-topics-translator](../../homelab.mqtt-topics-translator/README.md)
- Tasmota commands reference: https://tasmota.github.io/docs/Commands/
