# MedProbe pro Garmin

Connect IQ aplikace, která přijímá glykemii z MedProbe na iPhonu a zobrazuje ji na
Forerunner 255 a Forerunner 165.

## Architektura

Ciferník na Garminu **nemůže** přijímat zprávy z telefonu — Connect IQ to watch face API
nedovoluje. A jedna aplikace nemůže být zároveň watch-app a ciferník. Cílový tvar je proto:

```
iPhone (MedProbe)
   │  Connect IQ zpráva
   ▼
watch-app (tento projekt)      ← registruje se pro zprávy, ukládá poslední hodnotu
   │  complication
   ▼
ciferník (samostatný projekt)  ← přihlásí se k complication a kreslí ji
```

Hotová je zatím první část. Hodnota se ukládá do `Storage`, ne jen do paměti, protože
Connect IQ aplikaci mezi zprávami běžně restartuje.

## Struktura

```
manifest.xml                 aplikace, podporovaná zařízení, oprávnění
monkey.jungle                build konfigurace, device-specific resource paths
source/
  GlucoseReading.mc          wire formát a pravidla přijetí zprávy
  GlucoseStore.mc            uložení poslední hodnoty, práh zastarání
  Formatter.mc               hodnota, šipka, stáří, jednotky
  MedProbeApp.mc             příjem zpráv z telefonu
  MedProbeView.mc            obrazovka s glykemií
resources/                   sdílené texty a nastavení
resources-fr255/             layout pro FR255 (připraveno, čeká na definici zařízení)
resources-fr165/             layout pro FR165 (ověřeno)
```

FR255 a FR165 se liší **jen** rozměry v `layouts.xml`. Logika je sdílená.

## Stav

`fr165` je **ověřený** — projekt se sestaví lokálním SDK 9.2.0 do `.prg`.

`fr255` zatím ne: chybí jeho definice zařízení. Je zakomentovaný v `manifest.xml`
i `monkey.jungle`, protože monkeyc validuje **každý** qualifier v jungle, i když buduješ
pro jediné zařízení — takže nesplněný odkaz shodí build úplně. Až stáhneš definici pro
fr255 v SDK manageru, odkomentuj obojí. Resources pro něj už připravené jsou.

Ciferník v tomhle projektu **není**. Connect IQ nedovolí, aby jedna aplikace byla zároveň
`watch-app` a `watchface` — musí to být dva samostatné projekty. Tenhle je watch-app:
přijme zprávu z telefonu, uloží ji a zobrazí. Ciferník, který ji přečte přes complication,
je další krok.

## Build

**CI plný build spustit nemůže.** Connect IQ SDK archiv obsahuje kompilátor a dokumentaci,
ale ne definice jednotlivých zařízení — ty stahuje SDK manager, desktopový nástroj bez CLI.
Bez nich `monkeyc` odmítne každý device qualifier:

```
ERROR: 'fr255' is not a valid device / family qualifier.
```

CI proto kontroluje vše ostatní: strukturu projektu, validitu XML, deklaraci obou zařízení,
shodu wire protokolu s iOS stranou a přítomnost kontroly zastaralých hodnot.

### Lokální build

1. Stáhni [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/)
2. V něm stáhni SDK a **device definice pro fr255 a fr165**
3. Vygeneruj vývojářský klíč:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER \
  -in developer_key.pem -out developer_key.der -nocrypt
```

4. Build:

```bash
monkeyc -f garmin/MedProbeWatch/monkey.jungle \
        -d fr255 \
        -o MedProbe-fr255.prg \
        -y developer_key.der \
        -w

monkeyc -f garmin/MedProbeWatch/monkey.jungle \
        -d fr165 \
        -o MedProbe-fr165.prg \
        -y developer_key.der \
        -w
```

Nejjednodušší cesta je rozšíření **Monkey C** pro VS Code — obsahuje SDK manager,
simulátor i nasazení na hodinky.

## Formát zprávy

Definován na iOS v `MedProbe/Garmin/GarminMessage.swift`, na hodinkách
v `source/GlucoseReading.mc`. CI kontroluje, že se obě strany neshodly rozejít.

| klíč | význam |
|---|---|
| `v` | verze protokolu |
| `g` | glykemie, celé číslo v mg/dL |
| `t` | trend, 0–7 |
| `m` | čas měření, Unix sekundy |
| `s` | zdroj, 1 = Medtrum, 2 = LibreLinkUp |
| `q` | pořadové číslo |

Klíče jsou jednoznakové, protože Connect IQ přenos má omezenou velikost a stojí baterii na
obou stranách. Glykemie je celé číslo v mg/dL — Monkey C zachází s float nešikovně
a rozlišení senzoru desetiny neospravedlňuje; na mmol/L se převádí až při zobrazení.

Zprávu s neznámou verzí hodinky **ignorují**. Zobrazit špatně přečtenou hodnotu je horší
než ukázat předchozí i s jejím stářím.

## Zastaralé hodnoty

Hodinky nikdy nevydávají starou hodnotu za aktuální:

- zašedne
- doplní se stáří (`stale 23m`)
- **trendová šipka zmizí úplně** — směr odvozený ze staré hodnoty je horší než žádný směr

Práh je uživatelské nastavení, výchozí 15 minut. Oba zdroje dávají hodnotu každou
1–2 minuty, takže 15 minut znamená několik zmeškaných cyklů.

Chybějící trend se kreslí jako `?`, nikdy jako vodorovná šipka.

---

# Odesílání do hodinek

Connect IQ Companion App SDK je Garminem publikovaný **veřejný Swift package**:

<https://github.com/garmin/connectiq-companion-app-sdk-ios>

Je zapsaný v `project.yml` jako závislost, připnutý na verzi 1.8.0. Nic se nestahuje ručně
a CI si ho vyřeší samo — žádný framework v repozitáři, žádné přihlašování.

```yaml
packages:
  ConnectIQ:
    url: https://github.com/garmin/connectiq-companion-app-sdk-ios
    exactVersion: 1.8.0
```

`ConnectIQTransport.swift` je za `#if canImport(ConnectIQ)`, takže projekt se přeloží
i kdyby se package někdy nevyřešil — jen by spadl zpět na neaktivní transport.

## Co ještě zbývá

**1. Identifikátor aplikace musí souhlasit.** `ConnectIQTransport.watchAppID` a `id`
v `garmin/MedProbeWatch/manifest.xml` se hledají navzájem a musí být shodné. Teď:

```
a1b2c3d4e5f647589a0b1c2d3e4f5061
```

Vlastní vygeneruješ přes `uuidgen | tr -d '-' | tr 'A-Z' 'a-z'`, ale pak ho změň na
**obou** místech.

**2. Watchapp musí být v hodinkách.** Bez ní není kam posílat. Sestav `.prg` podle
postupu výše a nahraj přes VS Code rozšíření Monkey C nebo zkopíruj do `GARMIN/APPS`
na připojených hodinkách.

**3. Spárování v telefonu:** MedProbe → Settings → Garmin watch → vyber hodinky
(otevře se Garmin Connect, potvrdíš, vrátí tě to zpět) → **Send a test reading**.

Když se hodnota neobjeví, kontroluj v tomhle pořadí: je watchapp nainstalovaná, souhlasí
`watchAppID` s manifestem, jsou hodinky připojené v Garmin Connect, ukazuje Settings stav
*Connected*.
