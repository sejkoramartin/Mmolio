# Mmolio pro Garmin Forerunner 165

- **Mmolio Bridge** – receiver watch-app, příjem z telefonu i na pozadí.
- **Mmolio WatchFace** – AMOLED ciferník: datum, baterie, čas, glykemie, trend,
  stáří měření, aktuální tep a dnešní kroky.
- **Mmolio DataField** – rezervovaný název budoucího datového pole; zatím není implementované.

Historické složky `MedProbeWatch`, `xDripWatchFace` a interní namespace zůstávají kvůli
kontinuitě. V menu hodinek jsou nové názvy; na ciferníku ani obrazovce Bridge není
nápis MedProbe nebo xDrip. iOS část se touto úpravou nemění.

## Identita a přenos – neměnit

| Komponenta | application ID | Projekt |
|---|---|---|
| Mmolio Bridge | `a1b2c3d4e5f647589a0b1c2d3e4f5061` | `garmin/MedProbeWatch` |
| Mmolio WatchFace | `b1c2d3e4f5a647589a0b1c2d3e4f5072` | `garmin/xDripWatchFace` |

Ověřená cesta: **xDrip4iOS → Garmin Connect / Connect IQ → Mmolio Bridge → complication
→ Mmolio WatchFace**. Receiver je stále stejná aplikace. Phone wire protokol je stále v1:

| Klíč | Význam |
|---|---|
| `v` | verze, `1` |
| `g` | celé mg/dL |
| `t` | trend `0–7`; `0` neznámý, `4` stabilní |
| `m` | skutečný čas měření v Unix sekundách |
| `s` | zdroj: `1` Medtrum, `2` LibreLinkUp, `3` xDrip |
| `q` | pořadové číslo |

Přijetí a řazení zpráv i klíč `lastReading` ve Storage zůstávají stejné. Bridge při prvním
otevření volá `Background.registerForPhoneAppMessageEvent()`. Background delegate dál
ukládá přijatá data, publikuje complication a končí přes `Background.exit(null)`.
Chyba publikování nesmí zrušit uloženou hodnotu ani zablokovat ukončení background služby.
Po aktualizaci Bridge jednou otevřít: zaregistruje příjem a znovu publikuje uložené měření
s jeho **původním** časem. Změna jednotek nebo limitu stáří také přepublikuje uložené měření.

## Čas měření a zastarání

Connect IQ SDK 9.2.0 nemá v `Complication` pole pro čas měření. Samostatná complication
jen s časem by umožnila přečíst hodnotu z jednoho měření a čas z jiného.

Proto nová **privátní complication index 1**, `Mmolio Glucose Sample v1`, přenáší jeden
atomický ASCII řetězec v podporovaném poli `value`:

```text
1|115|5|1700000000|1|900
verze|mgdl|trend|measuredAtUnixSeconds|mmolFlag|staleSeconds
```

Je to interní kontrakt mezi dvěma Garmin aplikacemi, nikoli změna telefonního wire
protokolu. Obě `.prg` **musí být podepsané stejným existujícím vývojářským klíčem**,
protože privátní complication je dostupná jen aplikacím podepsaným stejným klíčem.
V SDK se `faceIt` deklaruje jen u public/protected komplikací, nikoli u této privátní.

Původní veřejná complication index 0 (`CGM Glucose`) zůstává pro kompatibilitu starších
odběratelů. **Nemá živou ochranu stáří po zastavení publisheru**; nový ciferník ji proto
nikdy nepoužívá. Se starým Bridge ukáže nový ciferník bezpečně `NO DATA`; aktualizovat oba.

Ciferník při každém překreslení počítá `now − measuredAt`, nezávisle na příchodu callbacku:

- Čerstvé: tyrkysová glykemie, geometrická trendová šipka, jednotka a stáří.
- Od přesného limitu stáří (výchozí **15 minut**, nastavení Bridge 5–120 minut): šedá
  glykemie, **STALE** se stářím, **žádná šipka**.
- Čas měření v budoucnosti: šedá hodnota, **CHECK TIME**, žádná šipka.
- Chybějící Bridge, starý payload bez času, neznámá verze nebo neplatný formát: **-- / NO DATA**.
- Neznámý trend: `?`, nikdy šipka pro stabilní glykemii.

Limit je zkontrolován i při minutových aktualizacích ciferníku v úsporném režimu; změna
stavu se tak projeví nejpozději při následujícím překreslení. Režim AMOLED sleep zmenší
čas a glykemii, skryje sekundární údaje a posouvá obsah; informace o stáří zůstává vidět.
Bridge má při otevřené obrazovce vlastní obnovu po 30 s, takže stará hodnota nezůstane
bez označení ani při dlouho otevřené aplikaci bez nových zpráv.

Tep a kroky pocházejí z nativních Garmin complications. Chybějící tep je `--`, nikoli
poslední historická hodnota; nula kroků je platná. Hodiny respektují čas hodinek a používají
24hodinový formát. Ciferník nezapíná senzor ani neprovádí síťové požadavky.

## Build s SDK 9.2.0

Předpoklady: Java, **Connect IQ SDK 9.2.0**, definice zařízení **fr165** v SDK Manageru a
**stávající** vývojářský `.der` klíč použitý u nainstalovaných aplikací. Klíč necommitovat.
FR255 resources zůstávají připravené, ale tento build cílí pouze na FR165.

Z kořene repozitáře na Linuxu (na tomto PC jsou tyto cesty již dostupné):

```bash
export CONNECTIQ_SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0"
export DEVELOPER_KEY="$HOME/Stažené/MedProbe-garmin/developer_key.der"
./garmin/scripts/build-fr165.sh
```

Skript kontroluje přesnou verzi SDK, používá kontrolu typů `-l 2`, sestaví release obou
aplikací a skončí chybou, pokud kterýkoli build selže:

```text
build/fr165/release/MmolioBridge.prg
build/fr165/release/MmolioWatchFace.prg
```

Na Windows lze použít stejné projekty přímo s `monkeyc.bat` (cesty přizpůsobit):

```powershell
$Sdk = 'C:\path\to\connectiq-sdk-9.2.0'
$Key = 'C:\path\to\existing\developer_key.der'
New-Item -ItemType Directory -Force build/fr165/release
& "$Sdk\bin\monkeyc.bat" -f garmin/MedProbeWatch/monkey.jungle -d fr165 -o build/fr165/release/MmolioBridge.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'Bridge build failed' }
& "$Sdk\bin\monkeyc.bat" -f garmin/xDripWatchFace/monkey.jungle -d fr165 -o build/fr165/release/MmolioWatchFace.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'WatchFace build failed' }
```

## Kontroly

```bash
.github/scripts/garmin-checks.sh
./garmin/scripts/build-fr165.sh --test
"$CONNECTIQ_SDK/bin/connectiq"
# V druhém terminálu, s běžícím simulátorem:
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioBridge.prg fr165 -t
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioWatchFace.prg fr165 -t
```

Monkey C testy ověřují serializaci skutečného publisheru a dekódování ciferníku, hranici
zastarání, opakované doručení bez omlazení dat, budoucí čas, změnu jednotek a limitu,
velké timestampy, neznámý trend a odmítnutí neplatných payloadů. Kontrolují také původní
telefonní paket a řazení zpráv. Testy jsou z release buildu odstraněné.

CI bez definic Garmin zařízení dělá jen strukturální a wire kontroly; nenahrazuje lokální
kompilaci ani skutečné hodinky. Samotný simulátor neověří Bluetooth/iPhone background
přenos ani doručování mezi dvěma současně nainstalovanými aplikacemi.

### Stav ověření 21. 9. 2026

- Oba release buildy pro FR165: **BUILD SUCCESSFUL**, SDK 9.2.0, `-l 2 -r`.
- Oba buildy s Monkey C testy: **BUILD SUCCESSFUL**, SDK 9.2.0, `-l 2 -t`.
- Existující `.github/scripts/garmin-checks.sh`, syntaxe build skriptu a `git diff --check`: prošly.
- **Běh testů ani vizuální kontrola v simulátoru nebyly dokončené.** Simulátor narazil
  na starý zámek a následně chybu oprávnění pracovního sandboxu. Kompilace testů není
  totéž jako jejich úspěšný běh; Claude má testy spustit lokálně před nasazením.
- USB sideload a ověření nové verze na fyzických hodinkách nebyly provedené.

## Nasazení obou aplikací přes USB – pro Claude Code

1. V lokálním repozitáři ověř čistý stav, checkout `feature/xdrip-garmin-complication`,
   `git pull --ff-only`. Nemergovat do main. Při lokálních změnách je nejprve zachovat.
2. Spusť kontroly a release build výše se **stejným původním podpisovým klíčem**.
3. Připoj FR165 přes USB. Ověř zařízení pomocí `GARMIN/GarminDevice.xml` a najdi skutečnou
   složku `GARMIN/APPS` (někde `GARMIN/Apps`). Na Linuxu může být zařízení přístupné přes
   MTP místo běžné připojené složky; v takovém případě použij MTP přenos.
4. Zálohuj původní dvě `.prg` mimo hodinky. Nahraď **jen tyto dvě aplikace**. Zachovej
   jejich existující cílové názvy souborů; application ID se řídí manifestem, viditelný
   název prostředky uvnitř `.prg`. Nemaž žádné jiné aplikace ani složky DATA/SETTINGS.
   Jestli jsou současné soubory `MedProbe.prg` a `xDripWatchFace.prg`, je příklad:

   ```bash
   GARMIN_APPS='/skutecna/cesta/GARMIN/APPS'
   cp build/fr165/release/MmolioBridge.prg "$GARMIN_APPS/MedProbe.prg"
   cp build/fr165/release/MmolioWatchFace.prg "$GARMIN_APPS/xDripWatchFace.prg"
   cmp build/fr165/release/MmolioBridge.prg "$GARMIN_APPS/MedProbe.prg"
   cmp build/fr165/release/MmolioWatchFace.prg "$GARMIN_APPS/xDripWatchFace.prg"
   sync
   ```

   Pokud jsou názvy jiné (např. Garmin přejmenoval soubory), nejprve identifikuj obě
   nainstalované aplikace; neodhaduj cíle a nevytvářej druhou kopii téhož ID pod jiným názvem.
   U MTP soubory po přenosu načti zpět a porovnej. Pak zařízení bezpečně odpoj.
5. Na hodinkách **jednou otevři Mmolio Bridge**, pak nastav **Mmolio WatchFace**.
6. Ověř čerstvou hodnotu, trend, jednotku a stáří; nech Bridge zavřený, iPhone zamčený
   a sleduj několik nových měření. Datum, baterie, aktuální tep a dnešní kroky mají
   odpovídat hodinkám. Ověř i probuzení / Always On režim.
7. Pro krátký test nastav v Bridge limit 5 minut, zastav přenos a počkej přes limit.
   Ciferník musí bez další zprávy zešednout, zobrazit `STALE 5m` a skrýt šipku. Po obnovení
   přenosu čerstvého měření se vrátí běžný vzhled. Vrať požadovaný limit, výchozí je 15 minut.
8. Zapiš commit, verzi SDK, výsledky obou buildů, cesty k `.prg`, výsledek kopírování a
   kontroly na hodinkách. Pokud hodinky nejsou připojené, pouze připrav obě `.prg` a uveď,
   že sideload a příjem na fyzickém zařízení nebyly provedené.

## SDK reference

Implementace byla porovnána s lokální dokumentací SDK 9.2.0. Online API reference:
[Complications](https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications.html),
[Complication](https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications/Complication.html),
[publikování a přístup](https://developer.garmin.com/connect-iq/core-topics/complications/),
[WatchFace lifecycle](https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/WatchFace.html).
