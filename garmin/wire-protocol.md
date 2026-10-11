# Phone → watch wire protocol v1

The contract between the sender on the phone and the three Garmin apps. The sender lives
in a separate repository — the xDrip4iOS fork `sejkoramartin/xdripswift`, branch
`feature/garmin-connectiq-upstream`, `xDrip/Managers/Garmin/`. Because the two sides are released
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
| `u` | optional display unit: `0` mg/dL, `1` mmol/L |

Both receivers (Mmolio Bridge and Mmolio DataField) parse this with the same file,
`garmin/MmolioBridge/source/GlucoseReading.mc`, and apply the same ordering rules from
`GlucoseStore.mc`: a message that is a duplicate, out of order or older than the stored
one is refused.

`g` always stays in mg/dL. Updated xDrip sends its existing display preference in
`u`; there is no separate Garmin unit toggle. A unit change increments `q` while
preserving `g` and `m`, so it does not make an old measurement fresh. Units are
stored with accepted readings; rejected packets cannot change them. Bridge passes
the unit to WatchFace through its existing private complication; DataField uses
its own accepted phone packet.

Missing/null `u` retains the legacy local `useMmol` setting (default mmol/L).
A non-null value other than the integer 0 or 1 rejects the packet. Older receivers
ignore `u` and retain their own unit setting. Both phone and receiver must be
updated for automatic units. After upgrading, wait for a newly accepted reading;
an unchanged resend may be ignored as a duplicate.

The optional `u` extension leaves all required v1 fields unchanged. Changing the
meaning of an existing field requires bumping the version on both sides.
