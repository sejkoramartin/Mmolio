# MedProbe

Minimalistická iOS companion aplikace, která **pasivně poslouchá** CGM hodnoty vysílané
pumpou Medtrum Nano (TouchCare) přes Bluetooth Low Energy, dekóduje je a zobrazuje
na jediné diagnostické obrazovce.

Etapa 1 = diagnostický prototyp. Nic víc.

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
