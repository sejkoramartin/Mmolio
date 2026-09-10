# Stav projektu

Zapsáno 10. 9. 2026. Slouží k tomu, aby se dalo navázat bez čtení celé historie.

Nasazeno: **1.0.1 (build 20)**. 181 unit testů, CI zelené.

---

## Co aplikace dělá

```
Libre 2+ senzor ──► oficiální Libre app ──► LibreView ──► LibreLinkUp ──► MedProbe ──► FR165
                                                                             │
                                    heartbeat (BLE, read-only) ──────────────┘
```

Otevře se na glykemii: hodnota, trend, stáří. Diagnostika se zapíná v nastavení.

Data odesílá do Garmin watch-app přes Connect IQ. **Ciferník zatím není** — jen aplikace,
kterou je potřeba na hodinkách otevřít.

---

## Co je hotové a ověřené

### LibreLinkUp — funguje

Follower přístup: MedProbe čte, co oficiální aplikace nahrála. Nesahá na senzor.

Tři věci, které to zpočátku blokovaly a jsou v `LibreLinkUpAPI.swift` okomentované:

- hlavičky musí být **`llu.android`** a aktuální verze; `llu.ios` server odmítá s HTTP 403
- posílá se i `user-agent: LibreLinkUp/4.16.0 (Android; Build 1)` — výchozí od URLSession neprojde
- přihlášení začíná na **`api.libreview.io`** a redirect na region se **následuje**; startovat rovnou
  na regionálním hostu znamená, že špatná volba selže jako chyba přihlášení

Zdroj: funkční Cloudflare worker uživatele (`~/Plocha/projects/glupro/worker.js`).

Přihlašovací údaje jsou v Keychainu, nikdy v UserDefaults ani logu.

### Heartbeat — funguje, ověřeno jako bezpečný

Přihlásí se k `F002` na už připojeném senzoru a použije notifikaci **jen jako pobídku**
k načtení z LibreLinkUp. Payload nedekóduje — je šifrovaný a klíče by se musely brát ze
senzoru. Do `F001` se nikdy nepíše; ta charakteristika se ani neobjevuje.

**Bez něj na pozadí nechodí nic**, protože iOS aplikaci suspenduje i s časovačem.

Ověřeno, že Libre aplikaci neruší: report v Libre za 7 dní ukázal **100 % času senzor aktivní**.

Cyklus `listening=true` → `sensor disconnected` po pár sekundách je **normální** — senzor
vysílá jednou za minutu a mezi tím spí. Není to konflikt o spojení.

### Garmin — funguje

SDK je veřejný Swift package (`garmin/connectiq-companion-app-sdk-ios`), připnutý na 1.8.0.

Watch-app se sestaví lokálním SDK, běží na FR165 a přijímá i zavřená (ServiceDelegate
s `onPhoneAppMessage`).

### Medtrum — funkční, skrytý

Dekodér ověřený proti EasyPatch, testy nedotčené. Skrytý z UI, protože pumpa vysílá jen
v ~5minutových oknech, zhruba dvě čtení za hodinu. Vrátit ho = smazat filtr
v `SelectedSource.selectable`.

Podrobnosti k tomu, co se o Medtrum protokolu zjistilo, jsou v historii commitů kolem
`0f2e25c` a `e632f2d`.

---

## Věci, které stály nejvíc času

Zapsané proto, že se na ně nedá přijít čtením kódu.

**Timer na pozadí neběží.** `asyncAfter` naplánovaný před suspendací se nespustí. Způsobilo
to 25minutovou díru: heartbeat spadl, retry čekal na časovač, a ten mohl vystřelit až
poté, co aplikaci probudilo něco jiného. Řešení je **čekající `connect()`** — ten
suspendaci přežije a iOS aplikaci probudí. Platí pro Libre i Medtrum.

**Connect IQ app id není UUID.** Manifest ho píše jako 32 hex znaků, Foundation chce
`8-4-4-4-12`. `UUID(uuidString:)` vrátí nil, `IQApp` to bez námitek přijme a adresuje
prázdno — projeví se to jako timeout (result 8) o několik sekund později. Převod je
v `ConnectIQAppID`.

**Connect IQ nedovolí jednu aplikaci jako watch-app i ciferník.** Musí to být dva projekty.

**SDK neukládá spárovaná zařízení.** Žádné `retrieveSavedDevices` neexistuje — ukládáme si
uuid, model a jméno sami, jinak se páruje po každém spuštění.

**JSONEncoder `.iso8601` zahazuje milisekundy.** Každý capture měl `.000Z`, a test to
nechytil, protože používal kulatý timestamp.

---

## Kudy dál

1. **Ciferník** — samostatný Connect IQ projekt, čte hodnotu přes complication. Bez něj se
   musíš na hodinkách proklikat do aplikace. Nejbližší smysluplný kus.
2. **Data field pro aktivity** — glykemie během běhu. Sdílel by `GlucoseReading.mc`
   a `Formatter.mc`.
3. **FR255** — chybí definice zařízení v SDK manageru; manifest i jungle mají zakomentované
   řádky připravené, resources hotové.
4. **Přeformulovat `sensor disconnected`** na něco jako `sleeping between transmissions` —
   vypadá to jako chyba, přitom je to normální stav.
5. Medtrum okna — proč pumpa vysílá jen občas, zůstalo nedořešené.

---

## Právní poznámka

Distribuce zatím **interní TestFlight**. Externí vyžaduje Beta App Review a tam přijde
otázka, jestli jde o zdravotnický prostředek — v EU podle MDR software poskytující data
pro rozhodování o léčbě obvykle ano, třída IIa.

Nightscout, xDrip, AndroidAPS ani Loop nejsou v obchodech: distribuují zdrojový kód
a uživatel si aplikaci staví sám. Je to promyšlené obcházení právě tohoto.

LibreLinkUp je navíc nedokumentované API; pro osobní použití to nikdo neřeší, u veřejné
distribuce je to jiná situace.

---

## Poznámky k nástrojům

**Connect IQ SDK** je lokálně v `~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0`,
definice zařízení zatím jen pro fr165. Build:

```bash
export PATH="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0/bin:$PATH"
monkeyc -f garmin/MedProbeWatch/monkey.jungle -d fr165 \
        -o MedProbe.prg -y ~/Stažené/MedProbe-garmin/developer_key.der -w
```

Klíč `developer_key.der` musí zůstat stejný, jinak hodinky berou build jako jinou aplikaci.

Nahrání do hodinek: `cp` přes MTP nefunguje, `gio copy` ano.

```bash
gio copy MedProbe.prg "mtp://<id>/Internal Storage/GARMIN/Apps/MedProbe.prg"
```

**CI** nebudí macOS runner na změny v `garmin/` ani v dokumentaci — ten je desetkrát dražší
než Linux. Garmin kontroly jsou v `.github/scripts/garmin-checks.sh` a jdou spustit lokálně.

**Plný Connect IQ build v CI nejde** — SDK archiv neobsahuje definice zařízení a SDK manager
nemá CLI.

---

## Reference

- `JohanDegraeve/xdripswift` — Medtrum CGM formát, watchdog a backoff
- `nightscout/AndroidAPS` — `pump/medtrum/`, notification packet a CRC-8
- `robberwick/pylibrelinkup` — funkční LibreLinkUp hlavičky
- `garmin/connectiq-companion-app-sdk-ios` — iOS SDK jako Swift package
