# Mmolio

Glykemie z Dexcomu G7 na hodinkách Garmin, na starém iPhonu jako displej a v liště Ubuntu.
Tohle repo obsahuje **všechno vlastní**; xDrip4iOS je cizí projekt a žije zvlášť.

```
Dexcom G7 ──BLE──► xDrip4iOS (iPhone) ──┬──► Connect IQ ──► Garmin FR165
       souběžně s CamAPS FX, která řeší léčbu
                                        └──► HTTPS push ──► Cloudflare Worker ──┬──► iPhone XS displej
                                                                                └──► GNOME rozšíření
```

| Složka | Co to je |
|---|---|
| [`garmin/`](garmin/README.md) | Tři aplikace pro Forerunner 165: Bridge, WatchFace, DataField |
| [`worker/`](worker/README.md) | Cloudflare Worker `glykemie` a displej pro iPhone |
| `gnome-extension/` | Rozšíření GNOME – hodnota v docku a alarmy |
| `docs/` | Návrh samostatné aplikace Mmolio a právní texty |

## Kde je co

**Hodinky.** `garmin/MmolioBridge` přijímá měření z telefonu i na pozadí a publikuje je jako
complication. `garmin/MmolioWatchFace` je ciferník, `garmin/MmolioDataField` datové pole pro
aktivity. Build a testy: `garmin/scripts/build-fr165.sh`, podrobnosti v `garmin/README.md`.

**Odesílatel do hodinek není tady.** Je to fork xDrip4iOS
[`sejkoramartin/xdripswift`](https://github.com/sejkoramartin/xdripswift), větev
`feature/garmin-watch`, složka `xDrip/Managers/Garmin/`. Jde o fork cizího GPL projektu,
který se musí synchronizovat s upstreamem, proto zůstává samostatný. Formát zpráv mezi
telefonem a hodinkami je zapsaný v [`garmin/wire-protocol.md`](garmin/wire-protocol.md).

**Worker.** Tváří se jako Nightscout server, přijímá push z xDripu, drží poslední měření
v KV a servíruje displej i `/api/glucose`. Nasazení a obsluha v `worker/README.md`,
kontext a trial-and-error poznatky v `worker/CLAUDE.md`.

## Pravidlo, které platí všude

**Stará hodnota nikdy nesmí vypadat jako aktuální.** Proto se všude počítá stáří ze
skutečného času měření, proto hodinky ukazují `STALE` a proto `/api/glucose` vrátí chybu,
místo aby mlčky servíroval poslední známou hodnotu. V 8–9/2026 worker měsíc nefungoval
a nikdo si toho nevšiml, protože displej dál ukazoval starou hodnotu.

## Historie

Repo se dřív jmenovalo **MedProbe** a byla v něm iOS aplikace, která četla LibreLinkUp
a Medtrum Nano. Od té doby data tečou z Dexcomu G7 přes xDrip4iOS, takže se aplikace
odstranila. Poslední stav včetně jejího kódu je pod tagem `ios-medprobe-final`.

Vnitřní názvy modulů v Monkey C (`MedProbe`, `xDripFace`) zůstaly, aby se nemusely měnit
application ID ani ověřený přenos. Viditelné názvy na hodinkách jsou Mmolio.
