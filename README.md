# MedProbe

Minimalistická iOS companion aplikace, která **pasivně poslouchá** CGM hodnoty vysílané
pumpou Medtrum Nano (TouchCare) přes Bluetooth Low Energy, dekóduje je a zobrazuje
na jediné diagnostické obrazovce.

Etapa 1 = diagnostický prototyp. Nic víc.

> **Aktuální stav, otevřené otázky a kudy dál najdeš v [STATUS.md](STATUS.md).**
> Dekodér je ověřený proti EasyPatch; nedořešená zůstává spolehlivost doručování.

---

## ⚠️ Co aplikace NEDĚLÁ

Jde o inzulinovou pumpu, proto je rozsah aplikace záměrně tvrdě omezený.
MedProbe **nikdy**:

- neposílá pumpě žádné příkazy
- nenastavuje bolus
- nenastavuje bazál
- nemění terapii
- nemění konfiguraci pumpy
- nepotvrzuje ani neruší alarmy
- nezapisuje do žádné BLE charakteristiky
- neimplementuje pump-control protokol
- neimplementuje firmware update
- nepoužívá žádný mechanismus BLE zápisu

Jediné operace, které aplikace nad Bluetooth provádí, jsou:
`scan` → `connect` → `discoverServices` → `discoverCharacteristics` → `setNotifyValue(true, …)`
→ příjem notifikací.

**Oficiální aplikací pro řízení pumpy zůstává Medtrum EasyPatch.**
MedProbe je pouze pasivní posluchač na již existujícím spojení.

Tento invariant vynucuje i CI: krok *„Assert no BLE write path exists“* prohledá celý
zdrojový strom na `writeValue`, `CBCharacteristicWriteType`, `withResponse`,
`withoutResponse`, `setDesiredConnectionLatency` a `CBPeripheralManager`.
Jakýkoli nález build shodí.

Dále v této etapě **není** implementováno (YAGNI): Garmin Connect IQ, FR255 aplikace,
cloud, Nightscout, EasyView API, alarmy, grafy, databáze historie, login, analytics.

---

## Jak to funguje

CGM senzor komunikuje s patch pumpou proprietárním RF spojením. Pumpa pak vysílá
CGM hodnoty přes BLE na vlastní službě. iOS umí jedno ACL spojení sdílet mezi více
aplikacemi, takže se lze přihlásit ke stejným notifikacím souběžně s EasyPatch,
bez vlastní autentizace.

| | |
|---|---|
| BLE služba | `669A9001-0008-968F-E311-6050405558B3` |
| CGM notifikační charakteristika | `669A9141-0008-968F-E311-6050405558B3` |
| Název zařízení | začíná `MT` |
| Délka CGM paketu | 20 bytů |

Rozložení paketu (pouze pole, která skutečně interpretujeme):

```
offset  0   typ paketu        (pozorováno 0xB3 0x02)
offset  1   marker CGM paketu (0x02)  ← podle tohoto bytu paket rozpoznáváme
offset  4   uint16 LE  reading counter (+1 každý 2minutový CGM cyklus)
offset  8   uint16 LE  aktuální raw glucose
offset 10   uint16 LE  raw glucose před 2 minutami
offset 12   uint16 LE  raw glucose před 4 minutami
offset 14   uint16 LE  raw glucose před 6 minutami
offset 18   uint16 LE  kalibrační faktor senzoru
```

Přepočet:

```
mg/dL  = rawGlucose * 1000 / calibrationFactor
mmol/L = mg/dL / 18.0182
```

### Validace paketu

Paket je přijat pouze pokud projde **všemi** kontrolami; jinak je odmítnut a zalogován
i s důvodem:

1. `data.count == 20`
2. `data[1] == 0x02`
3. `calibrationFactor > 0`
4. výsledek v rozsahu 40–400 mg/dL

### Zdroj protokolu

Rozložení paketu, UUID i konverze pocházejí z open-source referenční implementace
[`JohanDegraeve/xdripswift`](https://github.com/JohanDegraeve/xdripswift),
soubor `xDrip/BluetoothTransmitter/CGM/Medtrum/TouchCareNano/CGMMedtrumTouchCareNanoTransmitter.swift`.

Nic z protokolu nebylo domýšleno ani odhadnuto.

---

## Architektura

```
MedProbe/
├── MedProbeApp.swift              @main + AppDelegate (BLE manager vzniká hned při startu
│                                   kvůli CoreBluetooth state restoration)
├── ContentView.swift              jediná diagnostická obrazovka (SwiftUI)
├── MedtrumBluetoothManager.swift  BLE transport — read-only, žádný zápis
├── MedtrumPacketDecoder.swift     dekódování + validace, bez CoreBluetooth
├── MedtrumReading.swift           hodnotový typ jednoho čtení
└── DiagnosticLog.swift            kruhový buffer událostí + OSLog

MedProbeTests/
└── MedtrumPacketDecoderTests.swift
```

Vrstvy jsou oddělené záměrně: `MedtrumPacketDecoder` a `MedtrumReading` neimportují
CoreBluetooth, takže je lze testovat bez rádia i bez zařízení.

### Logování

OSLog, subsystém `cz.sejkora.MedProbe`. Logují se stavy `CBCentralManager`, nalezená
zařízení a jejich UUID, connect/disconnect, service a characteristic discovery, stav
notifikací, velikost paketu, raw HEX, dekódované hodnoty a každý odmítnutý paket
včetně důvodu. Terapeutická data se nelogují, protože je aplikace vůbec nezískává.

### Běh na pozadí

Projekt je připraven na pozdější provoz na pozadí:

- background mode `bluetooth-central` v Info.plist
- `CBCentralManager` s `CBCentralManagerOptionRestoreIdentifierKey`
- implementovaný `centralManager(_:willRestoreState:)`

Dlouhodobá stabilita na pozadí se bude ověřovat až na fyzickém iPhonu.

---

## Build

Vývoj probíhá na Linuxu, kompiluje se na macOS runneru v GitHub Actions.

`MedProbe.xcodeproj` **není v repozitáři** — generuje se z `project.yml` pomocí
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Zdrojem pravdy je `project.yml`
(z něj se generuje i `MedProbe/Info.plist`).

Lokálně na Macu:

```bash
brew install xcodegen
xcodegen generate
open MedProbe.xcodeproj
```

CI build (bez Apple Developer účtu a bez podepisování):

```bash
xcodebuild build \
  -project MedProbe.xcodeproj \
  -scheme MedProbe \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=<UDID>" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""
```

Testy se spouští stejným příkazem s `test` místo `build`.

Warningy jsou v CI chybami (`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `GCC_TREAT_WARNINGS_AS_ERRORS`).

---

## Testování na fyzickém iPhonu

Pro první reálný test je potřeba Mac s Xcode a Apple ID (stačí free personal team):
nastavit `DEVELOPMENT_TEAM`, zapnout automatické podepisování a aplikaci nainstalovat
na zařízení. Pumpa musí být spárovaná a aktivní v EasyPatch — MedProbe se přidává
k existujícímu spojení, sám pumpu nepáruje.

---

# TestFlight deployment without a local Mac

Celý řetězec běží na GitHub Actions macOS runneru:

```
workflow_dispatch → XcodeGen → xcodebuild archive (device, signed)
                  → xcodebuild -exportArchive → .ipa
                  → xcrun altool --upload-app → App Store Connect → TestFlight
```

Workflow: `.github/workflows/testflight.yml`. Spouští se **výhradně ručně**
(`workflow_dispatch`) — upload je rozhodnutí, ne vedlejší efekt commitu.
Běžný push spouští jen `ios-build.yml` (simulator build, testy, bezpečnostní audity).

Žádný Fastlane. Vystačíme si s `security`, `xcodebuild`, `xcrun altool` a App Store
Connect API klíčem, takže v distribučním řetězci není žádná externí závislost, která by
mohla vidět podepisovací materiál.

## One-time Apple setup

Tyhle kroky **musíš udělat ručně** — automatizovat je by bylo nebezpečnější než je
jednou proklikat. Všechny jdou z Linuxu, Mac není potřeba.

### 1. Apple Developer Program

Členství v [Apple Developer Program](https://developer.apple.com/programs/) (99 USD/rok).
Free Personal Team na TestFlight nestačí.

### 2. Registrace Bundle ID

Certificates, Identifiers & Profiles → **Identifiers** → **+** → App IDs → App

- Description: `MedProbe`
- Bundle ID: **Explicit**, `cz.sejkora.MedProbe`
- Capabilities: **nezaškrtávej nic**

MedProbe žádnou capability nepotřebuje. Background mode `bluetooth-central` je pouze
klíč v Info.plist, není to entitlement — aplikace nemá a nesmí mít žádný entitlements
soubor. Když ti portál nabídne zaškrtnout capabilities, nech je prázdné.

### 3. Distribution certificate (bez Macu, přes OpenSSL)

Apple chce Certificate Signing Request. Na Linuxu:

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout distribution.key \
  -out distribution.csr \
  -subj "/emailAddress=TVUJ@EMAIL/CN=MedProbe Distribution/C=CZ"
```

Portál → **Certificates** → **+** → **Apple Distribution** → nahraj `distribution.csr`
→ stáhni `distribution.cer`.

Převod na `.p12`, který bude runner importovat:

```bash
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM

openssl pkcs12 -export -legacy \
  -inkey distribution.key \
  -in distribution.pem \
  -out distribution.p12 \
  -passout pass:ZVOL_SI_SILNE_HESLO
```

**K `-legacy`:** OpenSSL 3 bez něj zašifruje `.p12` pomocí PBES2/AES-256, zatímco
s ním vznikne starší 3DES/SHA-1 varianta. Historicky `security import` na macOS to
první nepřečetl a job spadl na importu certifikátu s nevypovídající chybou.

Aktuální runner (macOS 26) už zvládne obojí — CI to ověřuje krokem
*Verify the README's OpenSSL .p12 recipe still holds*, který oba formáty skutečně
importuje. `-legacy` přesto doporučuji: funguje na obou a nestojí nic navíc.
Kdyby se to někdy změnilo, CI to nahlásí dřív, než na to narazíš ty.

Heslo, které si zvolíš, jde do secretu `APPLE_DISTRIBUTION_CERT_PASSWORD`.

`distribution.key` si ulož — bez něj nemůžeš certifikát znovu zabalit a musel bys ho
vydat znovu. Ulož ho mimo repozitář.

### 4. Provisioning profile

Portál → **Profiles** → **+** → Distribution → **App Store Connect**

- App ID: `cz.sejkora.MedProbe`
- Certificate: ten z kroku 3
- Name: cokoli, workflow si jméno přečte přímo z profilu

Stáhni `.mobileprovision`.

### 5. App Store Connect app record

[App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **+** → New App

- Platform: **iOS**
- Name: `MedProbe`
- Primary language: dle libosti
- Bundle ID: `cz.sejkora.MedProbe`
- SKU: např. `medprobe-001`

Bez tohoto záznamu upload skončí chybou o neznámé aplikaci. Repozitář ho nezakládá
sám — je to jednorázový krok.

### 6. App Store Connect API key

App Store Connect → **Users and Access** → **Integrations** → App Store Connect API
→ **Team Keys** → **+**

- Name: např. `MedProbe CI`
- Access: **App Manager**

Stáhni `AuthKey_XXXXXXXXXX.p8` — **jde to jen jednou**. Opiš si **Key ID** a **Issuer ID**.

## GitHub Secrets

Hodnoty zakóduj do base64 jedním řádkem:

```bash
base64 -w0 distribution.p12         > /tmp/cert.b64
base64 -w0 MedProbe_AppStore.mobileprovision > /tmp/profile.b64
base64 -w0 AuthKey_XXXXXXXXXX.p8    > /tmp/key.b64
```

Šest secretů, přesně tyto názvy:

| Secret | Obsah |
|---|---|
| `APPLE_DISTRIBUTION_CERT_P12_BASE64` | base64 `distribution.p12` |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | heslo zvolené v kroku 3 |
| `APPLE_PROVISIONING_PROFILE_BASE64` | base64 `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_ID` | Key ID, 10 znaků |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID, UUID |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | base64 `.p8` |

Team ID ani jméno profilu jako secret nepotřebuješ — workflow si obojí přečte přímo
z provisioning profilu, takže se to nemůže rozejít.

Nastavení přes `gh`:

```bash
gh secret set APPLE_DISTRIBUTION_CERT_P12_BASE64   < /tmp/cert.b64
gh secret set APPLE_PROVISIONING_PROFILE_BASE64    < /tmp/profile.b64
gh secret set APP_STORE_CONNECT_API_KEY_P8_BASE64  < /tmp/key.b64
gh secret set APPLE_DISTRIBUTION_CERT_PASSWORD     # vyzve interaktivně
gh secret set APP_STORE_CONNECT_KEY_ID
gh secret set APP_STORE_CONNECT_ISSUER_ID

shred -u /tmp/cert.b64 /tmp/profile.b64 /tmp/key.b64
```

Po nastavení už hodnoty z GitHubu nepřečteš zpátky — to je záměr.

## Running the workflow

GitHub → **Actions** → **TestFlight** → **Run workflow**. Nebo:

```bash
gh workflow run testflight.yml
gh run watch
```

Workflow rozlišuje fáze, takže v logu poznáš, kde to případně spadlo:

1. **Preflight** — vypíše jména chybějících secretů, nikdy hodnoty
2. **ARCHIVE SUCCEEDED** — `.xcarchive` pro zařízení
3. **EXPORT SUCCEEDED** — podepsaná `.ipa`
4. **UPLOAD SUCCEEDED** — Apple převzal build

Apple pak build zpracovává asynchronně, typicky pár minut. Workflow na to nečeká.

### Build number

`CFBundleVersion` se plní z `github.run_number` předaného na příkazové řádce
`xcodebuild archive` jako `CURRENT_PROJECT_VERSION`. To číslo je monotónní a nikdy se
neopakuje, takže TestFlight build nikdy neodmítne jako duplicitní. `MARKETING_VERSION`
zůstává `0.1.0` a mění se ručně v `project.yml`.

Aby se hodnota z příkazové řádky vůbec dostala do bundlu, má Info.plist
`CFBundleVersion` nastavené na `$(CURRENT_PROJECT_VERSION)`, ne na literál. CI si to
hlídá — dry-run archivuje s `424242` a ověří, že se to číslo objeví v Info.plist.

## Installing MedProbe from TestFlight

1. App Store Connect → MedProbe → **TestFlight** → počkej, až build přejde z *Processing*
2. Vyplň **Export Compliance**, pokud se zeptá. Aplikace deklaruje
   `ITSAppUsesNonExemptEncryption = false`, takže by se ptát neměl.
3. Přidej sebe jako internal testera (Users and Access → tvůj účet → role s přístupem)
4. Na iPhonu 15 Pro nainstaluj **TestFlight** z App Storu, přihlas se stejným Apple ID
5. Build se objeví v TestFlightu, instalace jedním klepnutím

Pak už jen: povolit Bluetooth oprávnění při prvním spuštění a mít pumpu aktivní
a spárovanou v EasyPatch. MedProbe se přidává k existujícímu spojení, sám nepáruje.

## Rotating/revoking credentials

Podepisovací materiál existuje jen po dobu běhu jobu: certifikát se importuje do
dočasné keychain v `$RUNNER_TEMP` s náhodně vygenerovaným heslem, profil se instaluje
až v jobu a cleanup krok běží i při selhání (`if: always()`).

Když se něco přesto vyzradí:

- **Certifikát** — Apple Developer → Certificates → revoke. Vydej nový (krok 3),
  vytvoř nový provisioning profile (starý přestane platit) a přepiš oba secrety.
- **API key** — App Store Connect → Integrations → Revoke. Vytvoř nový, přepiš
  `APP_STORE_CONNECT_KEY_ID` a `APP_STORE_CONNECT_API_KEY_P8_BASE64`.
- **Provisioning profile** — sám o sobě není citlivý (je v každé `.ipa`), ale po
  revokaci certifikátu ho stejně musíš vydat znovu.

Certifikát platí rok, provisioning profile taky — až workflow jednou spadne na
podpisu, tohle bude nejspíš důvod.

Kdyby se podepisovací soubor omylem dostal do gitu, CI to zachytí krokem
*Assert no signing secrets are committed*, ale samotné odstranění commitu nestačí —
credential je nutné revokovat a vydat znovu.

---

# Capture workflow (diagnostic builds)

Build 0.2.0 showed that CGM notifications do **not** arrive on `669A9141` at all,
while two other characteristics stream continuously. Build 0.3.0 therefore stops
guessing and records everything for offline analysis.

## Recording a session

1. Otevři MedProbe, ověř, že **Characteristics** ukazuje rostoucí čísla u `669A9101`
   a `669A9120`
2. Nech telefon nahrávat 15–30 minut. Záznam přežije uspání i přepnutí do pozadí —
   zapisuje se průběžně na disk, ne až na konci.
3. Kdykoli se v EasyPatch objeví nová glykemie, klepni na **Mark EasyPatch Reading**
   a zadej ji (např. `10.6`). Uloží se s přesným časem klepnutí.
   Čím víc značek, tím lépe — ideálně každý CGM cyklus.
4. Na konci **Export CSV** a pošli soubor sobě (Files, mail, AirDrop).

## Formát exportu

```
timestamp,characteristic,length,hex
2026-09-05T12:50:51.284Z,669A9101-…,20,4F 93 3D 01 00 00 A0 …
2026-09-05T12:51:30.117Z,EASYPATCH_MMOL_L,0,10.6
```

Timestamp je ISO 8601 s milisekundami — během jedné sekundy chodí víc paketů a na
jejich pořadí záleží.

Ručně označené hodnoty z EasyPatch jsou ve stejném souboru, rozlišené hodnotou
`EASYPATCH_MMOL_L` ve sloupci `characteristic`. Drží se schema o čtyřech sloupcích
a offline se dají triviálně oddělit. **Aplikace je nikdy nečte zpět** — neovlivňují
dekódování, slouží výhradně ke korelaci mimo telefon.

Data se ukládají do `medprobe-capture.jsonl` v Documents aplikace, řádek po řádku.
Když se aplikace ukončí, přijdeš nanejvýš o poslední rozepsaný řádek, ne o celý záznam.
**Clear capture** začne nový sběr.

## Co se ví o rámcích

Zatím jen struktura, žádný význam:

- `669A9101` — `write-acked,indicate`, nese dva druhy rámců: dvojice `20 22 XX 01/02`
  (20 a 18 bajtů) a sekvence `4F 93 XX 01..05` (20 bajtů)
- `669A9120` — `notify`, 13bajtové rámce, z toho 11 bajtů konstantních
- `669A9141` — `notify`, subscribe uspěje, **nikdy nic nepřijde**

Sémantika bajtů zatím přiřazená není a přiřazovat se nebude, dokud ji nepodloží data.
