# Phone → watch wire protocol v1

The contract between the sender on the phone and the three Garmin apps. The sender lives
in a separate repository — the xDrip4iOS fork `sejkoramartin/xdripswift`, branch
`feature/garmin-watch`, `xDrip/Managers/Garmin/`. Because the two sides are released
independently, the version field exists so a watch can refuse a message it cannot read
rather than misread it.

    version = 1

| Key | Meaning |
|---|---|
| `v` | protocol version, `1` |
| `g` | whole mg/dL |
| `t` | trend `0`–`7`; `0` unknown, `4` steady |
| `m` | time of measurement, Unix seconds — never the time of receipt |
| `s` | source: `1` Medtrum, `2` LibreLinkUp, `3` xDrip |
| `q` | sequence number |

Both receivers (Mmolio Bridge and Mmolio DataField) parse this with the same file,
`garmin/MmolioBridge/source/GlucoseReading.mc`, and apply the same ordering rules from
`GlucoseStore.mc`: a message that is a duplicate, out of order or older than the stored
one is refused.

Changing any meaning here means bumping the version on both sides.
