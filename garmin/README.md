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

# Zapnutí odesílání do hodinek

MedProbe zatím do hodinek nic neposílá. Chybí jediná věc: **Connect IQ Mobile SDK pro
iOS**, binárka, kterou Garmin distribuuje za přihlášením a kterou CI nemůže stáhnout.

Všechno ostatní je hotové. `ConnectIQTransport.swift` je napsaný a schovaný za
`#if canImport(ConnectIQ)`, takže se projekt kompiluje i bez frameworku a po jeho přidání
ožije sám. Info.plist už má URL schéma i dotaz na Garmin Connect.

## 1. Stáhni SDK

<https://developer.garmin.com/connect-iq/sdk/> → sekce **Mobile SDK** → **iOS**

Potřebuješ Garmin účet (zdarma). Stáhne se ZIP, v něm je `ConnectIQ.xcframework`.

Jde to i z Linuxu — je to obyčejný ZIP, Mac k tomu není potřeba.

## 2. Rozbal do projektu

```bash
unzip ~/Stažené/connect-iq-mobile-sdk-ios-*.zip -d /tmp/ciq
cp -r /tmp/ciq/ConnectIQ.xcframework Frameworks/
```

Výsledek musí být `Frameworks/ConnectIQ.xcframework/`.

`.gitignore` ho drží mimo repozitář. Garmin ho distribuuje pod vlastní licencí a
redistribuovat ho není na nás — což platí dvojnásob, kdyby se repozitář někdy zveřejnil.

## 3. Odkomentuj závislost v `project.yml`

V targetu `MedProbe` najdi blok `── Garmin Connect IQ ──` a odkomentuj:

```yaml
    dependencies:
      - framework: Frameworks/ConnectIQ.xcframework
        embed: true
        codeSign: true
```

## 4. Ověř identifikátor aplikace

`ConnectIQTransport.watchAppID` musí být **stejné** jako `id` v
`garmin/MedProbeWatch/manifest.xml`. Telefon a hodinky se najdou podle něj a podle ničeho
jiného. Teď je tam:

```
a1b2c3d4e5f647589a0b1c2d3e4f5061
```

Můžeš ho nechat, nebo si vygenerovat vlastní (`uuidgen | tr -d '-' | tr 'A-Z' 'a-z'`) —
ale pak ho změň na **obou** místech.

## 5. Sestav

Od téhle chvíle musí být framework přítomný, jinak build selže na linkování — proto je
krok 3 až po kroku 2.

```bash
xcodegen generate
```

CI build a TestFlight workflow fungují beze změny, pokud je framework v pracovní kopii.
**Pozor:** protože není v gitu, GitHub Actions ho mít nebude a TestFlight build selže.
Volby jsou dvě:

- framework přidat do repozitáře (funguje hned, ale viz licence výše)
- nebo ho uložit jako base64 GitHub Secret a ve workflow rozbalit, stejně jako se to dělá
  s podpisovým certifikátem

## 6. Nainstaluj aplikaci do hodinek

Watchapp z `garmin/MedProbeWatch` musí být v hodinkách, jinak není kam posílat. Nejsnazší
cesta je rozšíření **Monkey C** pro VS Code: obsahuje SDK manager, simulátor i nasazení
přes USB.

## 7. Spárování v telefonu

1. V MedProbe → Settings → **Garmin watch**
2. Vyber hodinky (otevře se Garmin Connect, potvrdíš, vrátí tě to zpět)
3. **Send a test reading**

Po úspěchu se hodnota objeví na ciferníku. Pokud ne, zkontroluj v tomhle pořadí:

- je watchapp v hodinkách nainstalovaná?
- souhlasí `watchAppID` s `manifest.xml`?
- jsou hodinky připojené v Garmin Connect?
- ukazuje Settings → Garmin watch stav *Connected*?
