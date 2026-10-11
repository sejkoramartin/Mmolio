# Mmolio pro fēnix 7X Pro

Podporované cíle pro sestavení jsou `fenix7xpro` a `fenix7xpronowifi`.
V SDK Manageru se druhý jmenuje **fēnix 7X Pro – Solar Edition (no Wi-Fi)**.
Běžný Solar / Sapphire Solar model patří pod **fēnix 7X Pro**.
Samotné slovo Solar tedy nestačí k určení cíle.

Oba mají MIP displej 280 × 280. Ciferník ukazuje čas, datum, baterii, glykemii,
trend, stáří měření, tep a kroky. Na MIP zůstává plný prstenec a stejné rozložení
v úsporném režimu; neběží animace ani AMOLED posun a ztlumení. U zastaralého
měření nebo budoucího času je hodnota šedá, trend a prstenec se skryjí a zobrazí
se stav. FR165 zachovává své AMOLED chování.

## Telefon a výběr hodinek

Je potřeba upravený xDrip4iOS z větve `feature/garmin-watch` a Garmin Connect
na iPhonu. Hodinky nejprve spárujte v Garmin Connect. Potom v nastavení Garmin
v xDripu otevřete výběr zařízení a zvolte své hodinky.

Výběr již používá `ConnectIQ.showDeviceSelection()` a přijímá vrácená zařízení
bez filtru modelů. Nové modely proto nevyžadují nový seznam ani nový build
xDripu. Identifikátory Bridge a DataField i formát zpráv zůstávají stejné.
Ověřeno ve zdroji `ConnectIQTransport.swift` a nastavení Garmin ve větvi
`feature/garmin-watch` dne 3. 10. 2026.
Přenos z telefonu používá Bluetooth; Wi-Fi v hodinkách není podmínkou.
Samotné zobrazení hodinek v nabídce nepotvrzuje doručování dat do aplikace.

## Sestavení

SDK zůstává 9.2.0. V SDK Manageru nainstalujte definice FR165 a obou variant
Fēnixu (jungle soubory obsahují jejich kvalifikátory).
Nastavte `CONNECTIQ_SDK` a `DEVELOPER_KEY` stejně jako v Garmin README.
Všechny aplikace musí být podepsané stejným stávajícím klíčem.

```bash
./garmin/scripts/build-device.sh fenix7xpro
./garmin/scripts/build-device.sh fenix7xpronowifi
./garmin/scripts/build-device.sh fenix7xpro --test
```

Výsledky jsou v `build/<zařízení>/release/` nebo `build/<zařízení>/test/`.
Původní `build-fr165.sh [--test]` zůstává funkční.

## Instalace a ověření na skutečných hodinkách

1. Podle přesného modelu vyberte odpovídající složku. Pokud model není jistý,
   ověřte produktové číslo nebo informace o zařízení; nenahrávejte obě varianty.
2. Přes USB nahrajte release soubory `MmolioBridge.prg` a `MmolioWatchFace.prg`
   do `GARMIN/APPS`. Volitelně také `MmolioDataField.prg` pro sportovní aktivity.
   Existující instalace nejprve zálohujte; zachovejte jejich názvy a nemažte jiná data.
3. Jednou otevřete Bridge a nastavte Mmolio WatchFace jako ciferník.
4. V xDripu zapněte Garmin a vyberte hodinky. Ověřte několik nových měření,
   také se zamčeným iPhonem a zavřenou aplikací Bridge.
5. Ověřte přechod do úsporného režimu, glykemii, trend, stáří a barvy podle
   nastavení rozsahu v Bridge. Krátce přerušte přenos a zkontrolujte stav STALE
   po překročení nastaveného limitu; po obnovení musí přijít nové měření.
6. Datové pole přidejte do aktivity a ověřte doručování i tam.

Testy simulátoru nenahrazují ověření Bluetooth a běhu na pozadí na konkrétním
telefonu a hodinkách. Platí [upozornění projektu](DISCLAIMER.md).

## Lokální ověření 3. 10. 2026

- SDK 9.2.0: všech 18 buildů (3 aplikace × 3 zařízení × release/test) úspěšných.
- Simulátor: na každém zařízení Bridge 10/10, WatchFace 7/7, DataField 14/14;
  celkem 93 úspěšných testů. Každá aplikace spuštěna v čisté instanci simulátoru.
- Vizuálně ověřeno 10 scénářů ciferníku na každém modelu: čerstvá a vysoká hodnota,
  oba stavy v úsporném režimu, STALE, NO DATA, CHECK TIME, 1000 mg/dL,
  neznámý trend a STALE 12d v úsporném režimu. Bez překrytí a ořezu.
- Obě varianty Fēnixu vykreslily shodné obrazovky. Čerstvé měření na MIP je
  pixelově shodné v běžném a úsporném zobrazení.
- FR165 Bridge a DataField jsou bajtově shodné s kontrolním sestavením před změnou
  provedeným se stejnými aktualizovanými definicemi zařízení a SDK.
- Strukturální kontroly a kontrola syntaxe build skriptů prošly.
- Přenos z iPhonu a běh na fyzickém Fēnixu zůstává nutné ověřit.
