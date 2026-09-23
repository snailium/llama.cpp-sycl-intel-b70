# B70 PCIe link rate — read the Intel PCIe switch, not the B70 endpoint

**Rule: the B70's own `LnkCap`/`LnkSta` is NOT the link that matters, and reading it produces a
misleading diagnosis. Read the upstream Intel PCIe switch port instead.**

Recorded 2026-09-23, after a misdiagnosis during the max-context probe (see
[`B70-MAX-CONTEXT.md`](B70-MAX-CONTEXT.md)).

## The topology

The B70 is not connected directly to the CPU root complex. It sits behind an **Intel PCIe switch**,
two levels below the host bridge:

```
CPU root complex
  └─ 03.1-[0a-0d]                       AMD Starship/Matisse PCIe GPP bridge
       └─ 0a:00.0  Intel 8086:e2ff      ┐
          │   PCIe Upstream Port        │  THE INTEL PCIe SWITCH
          │   <<< READ THE LINK HERE >>> │  (link to the host)
          └─ 0b:01.0  Intel 8086:e2f0   ┘  switch downstream port
               └─ 0c:00.0  Intel 8086:e223   Arc Pro B70 (Battlemage G31)
                    └─ 0d:00.0  Intel 8086:e2f7   HDMI/audio function
```

The XTX, by contrast, is behind a plain AMD bridge (`0e:00.0`) with no switch.

## What each port reports

| Port | Role | LnkCap | LnkSta | Meaning |
|---|---|---|---|---|
| **`0a:00.0`** | **Intel switch upstream — the real link** | 32 GT/s x16 | **16 GT/s x8 (downgraded)** | the link that actually carries B70 traffic |
| `0b:01.0` | switch → B70 downstream port | 2.5 GT/s x1 | 2.5 GT/s x1 | internal switch port; **not** the host link |
| `0c:00.0` | B70 endpoint | 2.5 GT/s x1 | 2.5 GT/s x1 | **misleading — do not use** |

**`0c:00.0` reports `LnkCap: Speed 2.5GT/s, Width x1`** — i.e. the endpoint claims it can only ever do
2.5 GT/s x1. That is not a fault and not a degradation; it is simply not the host-facing link, and it
tells you nothing about B70 bandwidth.

### Why the endpoint is misleading

The B70 endpoint sits behind the switch, so its own Link Capabilities/Status describe the
**switch-downstream-port ↔ endpoint** link, which is an internal fabric link inside the switch
complex — not the link between the switch and the CPU. Reading `lspci -vv -s 0c:00.0` and seeing
`2.5GT/s x1` looks like a catastrophically degraded card when in fact the host-facing link is
**16 GT/s x8**.

Worse, the endpoint's `LnkCap2` shows `Crosslink- Retimer- 2Retimers- DRS-` while the switch's
`0a:00.0` shows `Crosslink- Retimer+ 2Retimers+ DRS+` — the endpoint does not even advertise the
retimer capability that the switch does, which is exactly why the endpoint's numbers cannot be
extrapolated to the host link.

## The correct command

```bash
# The link that matters — the Intel PCIe switch upstream port:
sudo lspci -vv -s 0a:00.0 | grep -E 'LnkCap:|LnkSta:'

# Expected on a healthy B450 host:
#   LnkCap:  Port #0, Speed 32GT/s, Width x16, ASPM L1, ...
#   LnkSta:  Speed 16GT/s (downgraded), Width x8 (downgraded)
```

The `16GT/s x8` reading is **normal for this host** — the B450 board's CPU-attached slot provides
Gen4 x8 to the switch, while the switch itself is a Gen5 x16 part. "downgraded" here means
*negotiated below the switch's capability*, not *faulty*. Do not treat it as an error.

For comparison, the XTX on its own AMD bridge reports `LnkCap 16GT/s x16` / `LnkSta 16GT/s x8` — also
x8-negotiated. **x8 on both cards is the expected board behaviour.**

## How this caused a misdiagnosis

During the max-context probe the card wedged and I read `0c:00.0`'s link:

```
LnkCap: Port #0, Speed 2.5GT/s, Width x1
LnkSta: Speed 2.5GT/s, Width x1
```

and concluded "the PCIe link has degraded to a single lane at minimum speed — physical-layer
failure". **That conclusion was wrong.** Those are the endpoint's normal values; the endpoint always
reports 2.5 GT/s x1 on this host. The actual wedge was a driver/GPU hang
(`xe ... CRITICAL: Xe has declared device 0000:0c:00.0 as wedged`), and the switch link was
`16GT/s x8` both before and after — **the link never degraded at all.**

The link-training instability that `b70-backend-test` warns about would have to be diagnosed from
**`0a:00.0`**, and that is the only place a real downgrade (e.g. to 2.5 GT/s or x1) would show up.

## Practical checklist

1. `sudo lspci -vv -s 0a:00.0 | grep LnkSta` — **this** is the B70 link.
2. Expect `16GT/s x8` on this B450 host. Compare against that baseline, not against the switch's
   32GT/s x16 capability.
3. A real link problem looks like `0a:00.0` dropping to **2.5 GT/s** or **x1**, or `Train+` /
   `DLActive-` appearing in its `LnkSta` line.
4. **Ignore `0c:00.0`'s link fields entirely.** They are constant and meaningless for bandwidth.
5. If the link genuinely drops, that is the known PCIe link-training instability on this board —
   reseat/reboot territory, not a software fix.
