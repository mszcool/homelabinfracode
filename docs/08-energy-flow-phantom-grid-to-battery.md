# Phantom `grid → battery` readings in the Home Assistant energy flow

> Status: documented limitation, no full software fix possible without
> per-phase power data or hardware reconfiguration.
> Date investigated: 2026-04-27.
>
> **Update 2026-04-27:** A per-phase software correction has been
> implemented using the `evcc/site/grid/currents/{1,2,3}` MQTT topics.
> Two new HA sensors `sensor.evcc_grid_to_battery_corrected` and
> `sensor.evcc_battery_to_grid_corrected` are available alongside the
> originals for A/B comparison. See the "Per-phase software correction"
> section below for details. The original sensors are unchanged so the
> Energy Dashboard / Riemann history is preserved during the comparison
> period.

---

## English

### TL;DR

The Home Assistant template sensor `sensor.evcc_grid_to_battery` (and its
mirror `sensor.evcc_battery_to_grid`) occasionally shows non-zero values
even though both Huawei SUN2000 inverters are configured for **Maximum
Self-Consumption** and FusionSolar reports `0 W` grid-to-battery. This
document explains why this is **not a bug** in EVCC, the Modbus stack, or
the HA template — it is a fundamental limitation of computing energy
flows from **scalar (sum-of-phases) power values** in a setup with
**two independent inverters** and **unbalanced single-phase loads**.

### Setup recap

- **Inverter 1 ("house inverter"):** Huawei SUN2000 hybrid in the house,
  with the LUNA2000 battery and the **Huawei Smart Power Sensor (DTSU666-H)**
  installed at the grid feed-in point. This is the inverter that performs
  self-consumption regulation based on the smart meter reading.
- **Inverter 2 ("garage inverter"):** Huawei SUN2000 in the garage,
  feeding PV into the same household grid. **Not connected to inverter 1**
  (no Modbus/RS485 link, no shared smart meter, no master/slave setup).
  It operates fully independently and only sees its own PV string.
- **EVCC** polls all four meters (`huawei_inv1_grid`, `huawei_inv1_pv`,
  `huawei_inv1_battery`, `huawei_inv2_pv`) directly via the Huawei
  SDongleA on a 60 s tick. The Modbus proxy is not used because the
  SDongleA does not support concurrent connections via the proxy.
- **Home Assistant** subscribes to `evcc/site/{pvPower,gridPower,
  batteryPower,homePower}` over MQTT and decomposes them into seven
  derived flow sensors (PV→house, PV→battery, PV→grid, battery→house,
  grid→house, **grid→battery**, **battery→grid**).

### Symptom

During the afternoon of 2026-04-27, between 15:40 and 16:45, the
dashboard repeatedly showed `evcc_grid_to_battery` values between
~250 W and **1747 W**, while:

- the house inverter was in Max Self-Consumption mode,
- the LUNA2000 battery was charging from PV (`battery 1 power < 0`),
- PV was producing 2.6 – 3.9 kW,
- FusionSolar's daily summary showed `0 kWh` charged from grid.

### Root cause

Two contributing factors, both rooted in **per-phase imbalance**:

#### 1. Two independent inverters → no shared regulation

The garage inverter has no idea what the house inverter, the battery, or
the smart meter are doing. It pushes its PV output into the grid
according to its **own** local logic. The house inverter sees the smart
meter reading (which reflects the **net** of all three phases at the
grid feed-in point) and tries to regulate to ~0 W of grid exchange — but
it can only modulate **its own** PV/battery flow, not the garage
inverter's output. The result: the two inverters' outputs interact
constructively or destructively depending on phase placement, and the
house inverter cannot perfectly null out the smart meter.

#### 2. Single-phase loads + 3-phase inverter

Even with a single inverter, the SUN2000 hybrid balances on the **sum**
of grid power across the three phases — not on each phase
independently. When a strong single-phase load turns on (electric
kettle, oven element, immersion heater, EV charger on a single phase),
that phase imports from the grid even while the other two phases are
exporting PV. The scalar sum can show small or zero net grid power, but
when the imbalance is large enough, the sum goes positive (net import)
**at the same time** as the battery is charging from PV on the DC side.

### Why the HA template "blames" the battery

The seven decomposed flow sensors only have access to **scalar** values:

```
pv power       (sum of inverter 1 PV + inverter 2 PV)
grid power     (sum across 3 phases at the smart meter)
battery power  (DC-side battery, signed)
home power     (computed by EVCC: pv + bat + grid)
```

Given those scalars and the constraint `pv + bat + grid = house`, if
`grid > 0` (importing) **and** `bat < 0` (charging) **and** PV is not
enough by itself to cover both the house and the battery charge rate,
the only mathematically consistent attribution is:

> *"The grid is helping charge the battery."*

The template has no way of knowing that physically:

- PV (DC) → battery (DC), entirely inside the house inverter
- Garage inverter PV → grid export on phases 2 & 3
- Grid import on phase 1 → single-phase load (e.g. immersion heater)

These three flows can coexist, but their **scalar sum** looks identical
to "grid charges battery". FusionSolar reports `0 W` because it computes
battery-from-grid from the inverter's **internal DC accounting**, not
from a scalar power balance.

### Concrete evidence — the 16:36:25 spike

```
pv 2 power:      968 W      (garage)
pv 1 power:     2570 W      (house)
pv power:       3538 W
grid power:    +1747 W      (importing)
battery power: -2056 W      (charging)
home power:    +3229 W      (computed)
grid currents: [+11.0, +0.97, -4.28] A
```

Per-phase grid view (≈ 230 V × current):

| Phase | Current | Power | Direction |
|------:|--------:|------:|-----------|
| L1    | +11.0 A | +2530 W | **import** (large single-phase load) |
| L2    | +0.97 A |  +223 W | small import |
| L3    | -4.28 A |  -984 W | export (PV) |
| **net** | — | **+1769 W** | matches `grid power: 1747 W` |

A ~2.5 kW load just turned on on L1. The inverter exported almost 1 kW
of PV on L3 (it cannot push that across to L1 — that's the grid's job),
the battery kept charging from PV on the DC side at ~2 kW, and the net
across the meter was +1747 W of grid import. The HA template sees only
the scalar +1747 W with the battery charging at the same time and
attributes it to grid → battery.

### Mitigations already deployed

Implemented in
[`templates_evcc_energyflow.yaml`](../configs/envbase/home_assistant_files/ha_configs/msz_templates/templates_evcc_energyflow.yaml):

1. **Scoped staleness guard (90 s)** on `evcc_grid_to_battery` and
   `evcc_battery_to_grid` so a frozen meter does not produce phantom
   values. (Helps with case 2 of the original analysis — single-meter
   Modbus failures.)
2. **100 W dead-band** on the same two sensors, suppressing noise from
   small per-tick imbalances.

These mitigations help with sensor noise but **cannot eliminate** the
phantoms documented here, because the underlying scalar values are
internally consistent — they are not noise, they are an information
loss artifact.

### Possible deeper fixes (not implemented)

| Option | Effort | Eliminates phantoms? |
|---|---|---|
| Wire a master/slave RS485 link between the two inverters so they regulate jointly via the same smart meter | Medium (cabling + Huawei config) | Reduces case 1 substantially |
| Replace scalar `grid_to_battery` with a per-phase formula using the smart meter's per-phase power readings (already in EVCC log as `grid currents`) | High (template rewrite + new MQTT topics) | Reduces case 2 |
| Subtract a configurable "always-on baseline" (e.g. 700 W on L1) before computing grid → battery | Low | Reduces only the steady-state baseline phantom, not transient spikes |
| Trust FusionSolar for daily/monthly battery-from-grid totals; treat HA dashboard as an approximation for realtime visualisation | Zero | N/A — accept the limitation |

The **status quo decision** is the last one: keep the dead-band and
staleness guard, document the limitation, and rely on FusionSolar for
authoritative battery-source accounting.

### Reproduction artefacts

Both files are kept for future debugging in `/tmp/evcc_phantom/`
(temporary; reproduce by re-running the script against any captured
EVCC site debug log).

#### `analyze.py`

```python
#!/usr/bin/env python3
"""
Replays the EVCC site debug log and computes, for each polling tick, what the
HA template `evcc_grid_to_battery` (and `evcc_battery_to_grid`) would have
emitted. Prints any tick where one of these is non-zero, plus the four input
values that were used.

The formulas mirror configs/envbase/home_assistant_files/ha_configs/
msz_templates/templates_evcc_energyflow.yaml exactly.
"""
import re
import sys
from pathlib import Path

LOG = Path(sys.argv[1])

tick_re = re.compile(r"(\d{2}:\d{2}:\d{2}) ----")
val_re  = re.compile(r"(\d{2}:\d{2}:\d{2}) (pv 1 power|pv 2 power|pv power|grid power|battery 1 power|battery 1 soc|site power): (-?\d+)")

ticks = []
current = None
for line in LOG.read_text().splitlines():
    m = tick_re.search(line)
    if m:
        if current:
            ticks.append(current)
        current = {"start": m.group(1)}
        continue
    m = val_re.search(line)
    if m and current is not None:
        ts, key, val = m.group(1), m.group(2), int(m.group(3))
        current.setdefault("ts", {})[key] = ts
        current[key] = val
if current:
    ticks.append(current)


def gridtobat(pv, grid, bat, house):
    bat_chg  = max(-bat, 0)
    grid_imp = max(grid, 0)
    s2h      = max(min(pv, house), 0)
    pv_left  = max(pv - s2h, 0)
    s2b      = min(pv_left, bat_chg)
    chg_left = max(bat_chg - s2b, 0)
    h_left1  = max(house - s2h, 0)
    bat_dis  = max(bat, 0)
    b2h      = min(bat_dis, h_left1)
    h_left2  = max(h_left1 - b2h, 0)
    g2h      = min(grid_imp, h_left2)
    grid_left = max(grid_imp - g2h, 0)
    v = round(min(grid_left, chg_left))
    return 0 if v < 100 else v


def battogrid(pv, grid, bat, house):
    bat_dis  = max(bat, 0)
    grid_exp = max(-grid, 0)
    s2h      = max(min(pv, house), 0)
    pv_left  = max(pv - s2h, 0)
    bat_chg  = max(-bat, 0)
    s2b      = min(pv_left, bat_chg)
    pv_left2 = max(pv_left - s2b, 0)
    s2g      = min(pv_left2, grid_exp)
    h_left1  = max(house - s2h, 0)
    b2h      = min(bat_dis, h_left1)
    dis_left = max(bat_dis - b2h, 0)
    exp_left = max(grid_exp - s2g, 0)
    v = round(min(dis_left, exp_left))
    return 0 if v < 100 else v


print(f"{'tick':>10} {'pv':>6} {'grid':>6} {'bat':>6} {'house':>6} {'g2b':>6} {'b2g':>6}  notes")
print("-" * 90)
for t in ticks:
    pv   = t.get("pv power")
    grid = t.get("grid power")
    bat  = t.get("battery 1 power")
    if pv is None or grid is None or bat is None:
        continue
    house = pv + bat + grid
    g2b = gridtobat(pv, grid, bat, house)
    b2g = battogrid(pv, grid, bat, house)
    if g2b > 0 or b2g > 0:
        ts_grid = t["ts"]["grid power"]
        ts_bat  = t["ts"]["battery 1 power"]
        ts_pv   = t["ts"]["pv power"]
        notes = f"grid_ts={ts_grid} bat_ts={ts_bat} pv_ts={ts_pv}"
        print(f"{t['start']:>10} {pv:>6} {grid:>6} {bat:>6} {house:>6} {g2b:>6} {b2g:>6}  {notes}")
```

#### Sample EVCC log used (`log.txt`, excerpt)

Full file is 275 lines covering 15:20 – 16:45 on 2026-04-27. A few
representative ticks (one normal, one steady-state phantom, the big
spike, one post-spike):

```
[site ] DEBUG 2026/04/27 15:21:25 ----
[site ] DEBUG 2026/04/27 15:21:25 pv 2 power: 1256W
[site ] DEBUG 2026/04/27 15:21:26 grid power: -151W
[site ] DEBUG 2026/04/27 15:21:27 battery 1 power: -2603W
[site ] DEBUG 2026/04/27 15:21:28 pv 1 power: 2603W
[site ] DEBUG 2026/04/27 15:21:33 pv power: 3859W
[site ] DEBUG 2026/04/27 15:21:33 grid currents: [3 -1.74 -1.65]A
[site ] DEBUG 2026/04/27 15:21:34 battery 1 soc: 73%
[site ] DEBUG 2026/04/27 15:21:34 site power: -2754W

[site ] DEBUG 2026/04/27 15:40:25 ----
[site ] DEBUG 2026/04/27 15:40:25 pv 2 power: 1163W
[site ] DEBUG 2026/04/27 15:40:26 battery 1 power: -2302W
[site ] DEBUG 2026/04/27 15:40:27 grid power: 717W
[site ] DEBUG 2026/04/27 15:40:28 pv 1 power: 2587W
[site ] DEBUG 2026/04/27 15:40:32 pv power: 3750W
[site ] DEBUG 2026/04/27 15:40:33 site power: -1585W

[site ] DEBUG 2026/04/27 16:36:25 ----
[site ] DEBUG 2026/04/27 16:36:25 pv 2 power: 968W
[site ] DEBUG 2026/04/27 16:36:26 grid power: 1747W
[site ] DEBUG 2026/04/27 16:36:27 battery 1 power: -2056W
[site ] DEBUG 2026/04/27 16:36:29 pv 1 power: 2570W
[site ] DEBUG 2026/04/27 16:36:32 pv power: 3538W
[site ] DEBUG 2026/04/27 16:36:34 site power: -309W

[site ] DEBUG 2026/04/27 16:44:25 ----
[site ] DEBUG 2026/04/27 16:44:25 pv 2 power: 872W
[site ] DEBUG 2026/04/27 16:44:25 grid power: 813W
[site ] DEBUG 2026/04/27 16:44:26 battery 1 power: 46W
[site ] DEBUG 2026/04/27 16:44:27 pv 1 power: 2448W
[site ] DEBUG 2026/04/27 16:44:30 pv power: 3320W
[site ] DEBUG 2026/04/27 16:44:33 site power: 859W
```

#### Analyzer output for that log

```
      tick     pv   grid    bat  house    g2b    b2g  notes
------------------------------------------------------------------------------------------
  15:40:25   3750    717  -2302   2165    717      0  grid_ts=15:40:27 bat_ts=15:40:26 pv_ts=15:40:32
  15:42:25   3796    535  -2610   1721    535      0  grid_ts=15:42:26 bat_ts=15:42:26 pv_ts=15:42:31
  15:43:25   3814    811  -2268   2357    811      0  grid_ts=15:43:25 bat_ts=15:43:27 pv_ts=15:43:31
  15:44:25   3732    881  -2472   2141    881      0  grid_ts=15:44:25 bat_ts=15:44:26 pv_ts=15:44:31
  15:45:25   3753    856  -2523   2086    856      0  grid_ts=15:45:25 bat_ts=15:45:25 pv_ts=15:45:30
  15:46:25   3792    813  -2635   1970    813      0  grid_ts=15:46:25 bat_ts=15:46:26 pv_ts=15:46:29
  15:47:25   3815    266  -2435   1646    266      0  grid_ts=15:47:25 bat_ts=15:47:27 pv_ts=15:47:30
  16:12:25   3577    726  -2323   1980    726      0  grid_ts=16:12:25 bat_ts=16:12:26 pv_ts=16:12:32
  16:13:25   3375    872  -1964   2283    872      0  grid_ts=16:13:25 bat_ts=16:13:26 pv_ts=16:13:29
  16:14:25   2935    889  -1652   2172    889      0  grid_ts=16:14:25 bat_ts=16:14:26 pv_ts=16:14:26
  16:15:25   2607    897  -1345   2159    897      0  grid_ts=16:15:25 bat_ts=16:15:25 pv_ts=16:15:27
  16:36:25   3538   1747  -2056   3229   1747      0  grid_ts=16:36:26 bat_ts=16:36:27 pv_ts=16:36:32
```

Note that the per-input timestamps (`grid_ts`, `bat_ts`, `pv_ts`) within
each tick are within ~7 s of each other — i.e. the inputs are **fresh
and consistent**, ruling out a within-tick skew explanation. The
phantoms are real scalar imbalances, not artefacts of meter timing.

---

## Deutsch

### Zusammenfassung

Der Home-Assistant-Template-Sensor `sensor.evcc_grid_to_battery` (und
sein Gegenstück `sensor.evcc_battery_to_grid`) zeigt gelegentlich Werte
ungleich Null an, obwohl beide Huawei-SUN2000-Wechselrichter im Modus
**Maximaler Eigenverbrauch** laufen und FusionSolar `0 W`
Netz-zur-Batterie meldet. Dieses Dokument erklärt, warum dies **kein
Fehler** in EVCC, im Modbus-Stack oder im HA-Template ist — es ist eine
grundsätzliche Limitierung der Energieflussberechnung aus
**skalaren (über alle Phasen summierten) Leistungswerten** in einer
Anlage mit **zwei unabhängigen Wechselrichtern** und **unsymmetrischen
einphasigen Lasten**.

### Aufbau

- **Wechselrichter 1 ("Hauswechselrichter"):** Huawei SUN2000 Hybrid im
  Haus, mit LUNA2000-Batterie und dem **Huawei Smart Power Sensor
  (DTSU666-H)** am Netzeinspeisepunkt. Dieser Wechselrichter führt die
  Eigenverbrauchsregelung anhand des Smart-Meter-Wertes durch.
- **Wechselrichter 2 ("Garagenwechselrichter"):** Huawei SUN2000 in der
  Garage, speist PV in dasselbe Hausnetz ein. **Nicht mit
  Wechselrichter 1 verbunden** (keine Modbus-/RS485-Verbindung, kein
  gemeinsamer Smart Meter, kein Master/Slave-Setup). Er arbeitet
  vollständig unabhängig und sieht nur seinen eigenen PV-String.
- **EVCC** liest alle vier Zähler (`huawei_inv1_grid`, `huawei_inv1_pv`,
  `huawei_inv1_battery`, `huawei_inv2_pv`) direkt über den Huawei
  SDongleA in einem 60-Sekunden-Takt. Der Modbus-Proxy wird nicht
  verwendet, weil der SDongleA über den Proxy keine parallelen
  Verbindungen unterstützt.
- **Home Assistant** abonniert `evcc/site/{pvPower,gridPower,
  batteryPower,homePower}` über MQTT und zerlegt diese in sieben
  abgeleitete Flusssensoren (PV→Haus, PV→Batterie, PV→Netz,
  Batterie→Haus, Netz→Haus, **Netz→Batterie**, **Batterie→Netz**).

### Symptom

Am Nachmittag des 27.04.2026 zeigte das Dashboard zwischen 15:40 und
16:45 wiederholt Werte zwischen ~250 W und **1747 W** für
`evcc_grid_to_battery`, obwohl:

- der Hauswechselrichter im Modus „Maximaler Eigenverbrauch" lief,
- die LUNA2000-Batterie aus PV geladen wurde (`battery 1 power < 0`),
- die PV 2,6 – 3,9 kW lieferte,
- FusionSolar in der Tagesübersicht `0 kWh` aus dem Netz geladen meldete.

### Ursachen

Zwei sich ergänzende Faktoren, beide bedingt durch
**Phasenunsymmetrie**:

#### 1. Zwei unabhängige Wechselrichter → keine gemeinsame Regelung

Der Garagenwechselrichter weiß nichts vom Hauswechselrichter, von der
Batterie oder vom Smart Meter. Er speist seine PV-Leistung gemäß
**eigener** lokaler Logik ins Netz. Der Hauswechselrichter sieht den
Smart-Meter-Wert (der die **Summe** aller drei Phasen am
Einspeisepunkt widerspiegelt) und versucht, auf ~0 W Netzbezug zu
regeln — kann aber nur **seinen eigenen** PV-/Batterie-Fluss
verändern, nicht den des Garagenwechselrichters. Das Resultat: die
Ausgaben beider Wechselrichter überlagern sich konstruktiv oder
destruktiv abhängig von Phasenlage und Zeitpunkt, und der
Hauswechselrichter kann den Smart-Meter-Wert nicht perfekt auf Null
regeln.

#### 2. Einphasige Lasten + dreiphasiger Wechselrichter

Selbst mit nur einem Wechselrichter regelt der SUN2000 Hybrid auf die
**Summe** der Netzleistung über alle drei Phasen — nicht auf jede
Phase einzeln. Wenn eine starke einphasige Last einschaltet
(Wasserkocher, Backofen-Heizelement, Heizstab, einphasiges
Wallbox-Laden), bezieht diese Phase Strom aus dem Netz, während die
anderen beiden Phasen gleichzeitig PV einspeisen. Die skalare Summe
kann klein oder null sein, aber bei großer Schieflage wird die Summe
positiv (Netzbezug) — **gleichzeitig** lädt die Batterie auf der
DC-Seite aus PV.

### Warum das HA-Template die Batterie „beschuldigt"

Die sieben abgeleiteten Flusssensoren haben nur Zugriff auf
**skalare** Werte:

```
pv power       (Summe aus WR1 PV + WR2 PV)
grid power     (Summe über 3 Phasen am Smart Meter)
battery power  (DC-seitige Batterie, vorzeichenbehaftet)
home power     (von EVCC berechnet: pv + bat + grid)
```

Mit diesen Skalaren und der Bedingung `pv + bat + grid = haus`: wenn
`grid > 0` (Bezug) **und** `bat < 0` (Laden) **und** PV alleine nicht
ausreicht, gleichzeitig Haus und Batterie zu versorgen, ist die
einzige mathematisch konsistente Zuordnung:

> *„Das Netz hilft beim Laden der Batterie."*

Das Template hat keine Möglichkeit zu erkennen, dass physikalisch:

- PV (DC) → Batterie (DC), komplett innerhalb des Hauswechselrichters
- Garagenwechselrichter PV → Netzeinspeisung auf Phasen 2 & 3
- Netzbezug auf Phase 1 → einphasige Last (z. B. Heizstab)

passieren. Diese drei Flüsse können koexistieren, ihre **skalare
Summe** sieht aber identisch aus zu „Netz lädt Batterie". FusionSolar
meldet `0 W`, weil es den Netz-zur-Batterie-Wert aus der **internen
DC-Buchführung** des Wechselrichters berechnet, nicht aus einer
skalaren Leistungsbilanz.

### Konkreter Beleg — der 16:36:25-Peak

```
pv 2 power:      968 W      (Garage)
pv 1 power:     2570 W      (Haus)
pv power:       3538 W
grid power:    +1747 W      (Bezug)
battery power: -2056 W      (Laden)
home power:    +3229 W      (berechnet)
grid currents: [+11.0, +0.97, -4.28] A
```

Phasenweise Netzsicht (≈ 230 V × Strom):

| Phase | Strom | Leistung | Richtung |
|------:|------:|---------:|----------|
| L1    | +11,0 A | +2530 W | **Bezug** (große einphasige Last) |
| L2    | +0,97 A |  +223 W | kleiner Bezug |
| L3    | -4,28 A |  -984 W | Einspeisung (PV) |
| **netto** | — | **+1769 W** | passt zu `grid power: 1747 W` |

Eine Last von ~2,5 kW wurde gerade auf L1 eingeschaltet. Der
Wechselrichter speiste fast 1 kW PV auf L3 ein (er kann das nicht zu
L1 „transportieren" — das ist Aufgabe des Netzes), die Batterie wurde
aus PV auf der DC-Seite mit ~2 kW weitergeladen, und am Zähler ergab
sich netto +1747 W Netzbezug. Das HA-Template sieht nur die skalaren
+1747 W bei gleichzeitig ladender Batterie und ordnet das als
Netz → Batterie zu.

### Bereits umgesetzte Mitigationen

In
[`templates_evcc_energyflow.yaml`](../configs/envbase/home_assistant_files/ha_configs/msz_templates/templates_evcc_energyflow.yaml)
implementiert:

1. **Eingegrenzter Frische-Check (90 s)** auf `evcc_grid_to_battery`
   und `evcc_battery_to_grid`, damit ein eingefrorener Zähler keine
   Phantomwerte produziert.
2. **100-W-Totband** auf denselben beiden Sensoren, um Rauschen aus
   kleinen Pro-Tick-Imbalances zu unterdrücken.

Diese Maßnahmen helfen gegen Sensorrauschen, können die hier
dokumentierten Phantome aber **nicht eliminieren**, weil die
zugrundeliegenden skalaren Werte in sich konsistent sind — sie sind
kein Rauschen, sondern ein Informationsverlust-Artefakt.

### Mögliche tiefergehende Lösungen (nicht umgesetzt)

| Option | Aufwand | Eliminiert Phantome? |
|---|---|---|
| RS485-Master/Slave-Verbindung zwischen den beiden Wechselrichtern, damit beide gemeinsam über den Smart Meter regeln | Mittel (Verkabelung + Huawei-Konfiguration) | Reduziert Ursache 1 deutlich |
| Skalares `grid_to_battery` durch eine phasenweise Formel ersetzen (Smart-Meter-Phasenleistungen, sind im EVCC-Log bereits als `grid currents` vorhanden) | Hoch (Template-Neuschrieb + neue MQTT-Topics) | Reduziert Ursache 2 |
| Eine konfigurierbare „Grundlast" (z. B. 700 W auf L1) vom Netzbezug abziehen, bevor `grid → battery` berechnet wird | Niedrig | Reduziert nur das stationäre Grundphantom, nicht transiente Peaks |
| FusionSolar als verbindliche Quelle für tägliche/monatliche Netz-zur-Batterie-Summen nutzen; HA-Dashboard als Annäherung für Echtzeit-Visualisierung | Null | Limitierung akzeptieren |

Die **aktuelle Entscheidung** ist die letzte: Totband und Frische-Check
beibehalten, Limitierung dokumentieren, FusionSolar als Referenz für
die Batterie-Quellen-Buchführung verwenden.

### Reproduktions-Artefakte

Skript und Beispiel-Log oben im englischen Teil; sie liegen während
der Untersuchung temporär unter `/tmp/evcc_phantom/`. Zur Reproduktion
das Skript einfach gegen ein beliebiges aufgezeichnetes EVCC
`[site] DEBUG`-Log laufen lassen.

Hinweis zu den Eingangs-Zeitstempeln (`grid_ts`, `bat_ts`, `pv_ts`)
in der Analyzer-Ausgabe: Sie liegen pro Tick innerhalb von ~7 s
auseinander — die Eingaben sind also **frisch und konsistent**, was
die Erklärung „Skew innerhalb eines Ticks" ausschließt. Die Phantome
sind reale skalare Imbalances, keine Artefakte des Zählertimings.

---

## Per-phase software correction (implemented 2026-04-27)

EVCC publishes per-phase grid currents on `evcc/site/grid/currents/{1,2,3}`
(signed: `+` import / `-` export). These are now also exposed as Home
Assistant MQTT sensors and used to compute a corrected grid power signal.

### Idea: balanced (symmetric) component of grid power

The Huawei SUN2000 hybrid can only exchange energy with the DC battery
through its 3-phase AC port. Any battery charge from grid (or discharge
to grid) must therefore be **balanced across all three phases at once**.
Per-phase imbalance is, by construction, **inter-phase load** —
typically a single-phase appliance importing on one phase while PV (own
or the garage inverter's) exports on another. It cannot be exchanged
with the battery.

With assumed phase voltage `V = 230 V`:

```
Pi = V * Ii        (signed per-phase grid power, i = 1..3)

if sign(P1) == sign(P2) == sign(P3) and not all zero:
    P_balanced = sign * 3 * min(|P1|, |P2|, |P3|)
else:
    P_balanced = 0
```

`P_balanced` is the part of grid power that flows in the same direction
on all three phases simultaneously. Substituting it for the raw scalar
grid power in the existing flow decomposition zeroes out the phantom
`grid → battery` whenever the cause is per-phase imbalance, while
preserving correct attribution if grid genuinely charges the battery
(e.g. a forced TOU schedule pulling balanced power from the grid).

### Empirical validation

Re-running [`analyze.py`](#analyzepy) with a `grid currents` line added
for the 16:36:25 spike and a synthetic "real grid charge" tick at 17:00:

| tick | scenario | currents (A) | raw `g2b` | corrected `g2b` |
|---|---|---|---:|---:|
| 16:36:25 | the actual phantom | `[+11.0, +0.97, -4.28]` (mixed signs) | 1747 W | **0 W** ✅ |
| 17:00:25 | synthetic real grid-charge | `[+5, +5, +5]` (all positive) | 3000 W | **3000 W** ✅ |

The mixed-sign condition collapses `P_balanced` to 0 → the corrected
flow sensor reports 0. The all-same-sign synthetic test passes
through correctly.

### New entities

In [`mqtt_evcc_sensors.yaml`](../configs/envbase/home_assistant_files/ha_configs/msz_mqtt_sensors/mqtt_evcc_sensors.yaml):

- `sensor.evcc_evcc_grid_current_l1` (`evcc/site/grid/currents/1`, A)
- `sensor.evcc_evcc_grid_current_l2` (`evcc/site/grid/currents/2`, A)
- `sensor.evcc_evcc_grid_current_l3` (`evcc/site/grid/currents/3`, A)

In [`templates_evcc_energyflow.yaml`](../configs/envbase/home_assistant_files/ha_configs/msz_templates/templates_evcc_energyflow.yaml):

- `sensor.evcc_grid_power_balanced` — the symmetric component (W,
  signed), with a 90 s staleness guard on all three current inputs.
- `sensor.evcc_grid_to_battery_corrected` — same decomposition logic as
  `evcc_grid_to_battery`, but reads `evcc_grid_power_balanced` instead
  of the raw `evcc_evcc_grid_power`. Keeps the 100 W dead-band.
- `sensor.evcc_battery_to_grid_corrected` — symmetric mirror.

The originals are **untouched** — same `entity_id`, same `unique_id`,
same history, same Riemann integrators in
[`sensors_evcc_riemann.yaml`](../configs/envbase/home_assistant_files/ha_configs/msz_sensors/sensors_evcc_riemann.yaml).
The dashboard ([`lovelace.energy_custom.json`](../configs/envbase/home_assistant_files/ha_dashboards/lovelace.energy_custom.json))
also still references the originals.

### Next steps (suggested, not yet executed)

1. Observe the corrected vs. raw sensors in HA history for ~3 days.
   Verify the corrected sensor stays at 0 in all situations where
   FusionSolar reports 0 grid → battery, and matches the raw sensor
   when both are non-zero.
2. If validation passes, switch the dashboard's
   `grid_to_battery_entity` / `battery_to_grid_entity` to the
   `_corrected` versions.
3. Optionally also re-point the Riemann integrators to the corrected
   sensors so the Energy Dashboard's "Energy from grid into battery"
   stops accumulating phantom kWh going forward. Past kWh remains in
   the original entity's statistics — acceptable since the Energy
   Dashboard does not retroactively recompute totals.

### Limitations of the correction

- Voltage is hard-coded at 230 V (no per-phase voltage topic used).
  Mains drift of ±5 % maps to ≤ ±5 % magnitude error, well below the
  100 W dead-band that already absorbs cosmetic noise.
- The correction is conservative: any mixed-sign tick collapses to 0,
  even if a small genuine balanced component is present underneath.
  Consequence: in the rare case of a real, slow grid-charge happening
  *simultaneously* with a strong single-phase load the corrected
  sensor will under-report. The dead-band already drops sub-100 W
  noise so this is unlikely to matter in practice.
- This only fixes Cause 2 of the original analysis (per-phase
  imbalance from independent inverters + single-phase loads). It does
  not change anything for Cause 1 of the *original* document (within-
  tick meter skew), which is already handled by the 90 s staleness
  guard on the originals.
- No replacement for the deeper hardware fix: a true RS485 master/
  slave link between the two SUN2000 inverters would let them
  cooperatively regulate to zero net grid exchange and eliminate the
  *physical* root cause, not just its dashboard symptom.
