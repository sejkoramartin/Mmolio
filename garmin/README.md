# MedProbe pro Garmin

Connect IQ aplikace, která přijímá glykemii z MedProbe na iPhonu a zobrazuje ji na
Forerunner 255 a Forerunner 165.

## Proč je to rozdělené na dvě části

Ciferník na Garminu **nemůže** přijímat zprávy z telefonu — Connect IQ to watch face API
nedovoluje. Architektura je proto:

```
iPhone (MedProbe)
   │  Connect IQ zpráva
   ▼
watchapp (MedProbeApp.mc)      ← registruje se pro zprávy, ukládá poslední hodnotu
   │  complication
   ▼
ciferník (MedProbeFaceView.mc) ← přihlásí se k complication a kreslí ji
```

Watchapp běží jako background service a přežívá restarty, které Connect IQ mezi zprávami
běžně dělá — proto se hodnota ukládá do `Storage`, ne jen do paměti.

## Struktura

```
manifest.xml                 aplikace, podporovaná zařízení, oprávnění
monkey.jungle                build konfigurace, device-specific resource paths
source/
  GlucoseReading.mc          wire formát a pravidla přijetí zprávy
  GlucoseStore.mc            uložení poslední hodnoty, práh zastarání
  Formatter.mc               hodnota, šipka, stáří, jednotky
  MedProbeApp.mc             příjem zpráv, publikace complication
  MedProbeView.mc            obrazovka v aplikaci
  MedProbeFaceView.mc        ciferník
resources/                   sdílené texty a nastavení
resources-fr255/             layout pro FR255
resources-fr165/             layout pro FR165
```

FR255 a FR165 se liší **jen** rozměry v `layouts.xml`. Logika je sdílená.

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
