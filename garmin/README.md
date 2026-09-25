# Mmolio pro Garmin Forerunner 165

- **Mmolio Bridge** – receiver watch-app, příjem z telefonu i na pozadí.
- **Mmolio WatchFace** – AMOLED ciferník: datum, baterie, čas, glykemie, trend,
  stáří měření, aktuální tep a dnešní kroky.
- **Mmolio DataField** – datové pole pro sportovní aktivity: glykemie, trend, jednotka a
  skutečné stáří měření. Data přijímá přímo z telefonu pod vlastním ID (viz níže).

Historické složky `MedProbeWatch`, `xDripWatchFace` a interní namespace zůstávají kvůli
kontinuitě. V menu hodinek jsou nové názvy; na ciferníku ani obrazovce Bridge není
nápis MedProbe nebo xDrip. Nový projekt `garmin/MmolioDataField` už nese nový název.
iOS část MedProbe se touto úpravou nemění.

## Identita a přenos – neměnit

| Komponenta | application ID | Projekt |
|---|---|---|
| Mmolio Bridge | `a1b2c3d4e5f647589a0b1c2d3e4f5061` | `garmin/MedProbeWatch` |
| Mmolio WatchFace | `b1c2d3e4f5a647589a0b1c2d3e4f5072` | `garmin/xDripWatchFace` |
| Mmolio DataField | `7ca56fd800634cab90f28d5e72be2e05` | `garmin/MmolioDataField` |

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
Přechod na zjednodušený vzhled se řídí skutečným stavem displeje Garminu; oznámení
`onEnterSleep` samo už nevynutí jeho překreslení, dokud displej ještě svítí naplno.
Bridge má při otevřené obrazovce vlastní obnovu po 30 s, takže stará hodnota nezůstane
bez označení ani při dlouho otevřené aplikaci bez nových zpráv.

Tep a kroky pocházejí z nativních Garmin complications. Chybějící tep je `--`, nikoli
poslední historická hodnota; nula kroků je platná. Hodiny respektují čas hodinek a používají
24hodinový formát. Ciferník nezapíná senzor ani neprovádí síťové požadavky.

## Mmolio DataField

Connect IQ nedovoluje datovému poli odebírat complications: oprávnění
`ComplicationSubscriber` je jen pro ciferníky a kompilátor ho u `datafield` odmítne. Pole
proto **nečte Bridge**, ale přijímá stejný telefonní paket v1 `{v,g,t,m,s,q}` přímo, pod
vlastním application ID `7ca56fd800634cab90f28d5e72be2e05`. Foreground `Communications` je
pro datová pole podporované od API 5.0.0 (`minApiLevel="5.0.0"`, FR165 má 5.2.0).

**Telefon musí posílat kopii každého nového měření i na toto ID**, nezávisle na výsledku
doručení do Bridge. Starší xDrip4iOS posílá jen Bridge – pole pak zůstane na `NO DATA`,
takže samotný USB sideload nestačí. Nutná je verze xDrip4iOS s tímto odesíláním (fork
`sejkoramartin/xdripswift`, větev `feature/garmin-watch`).

- Parser a pořadí zpráv jsou **přímo soubory Bridge** `GlucoseReading.mc` a `GlucoseStore.mc`
  (zakompilované beze změny přes `monkey.jungle`): duplicitní, opožděné a starší pakety pole
  odmítne stejně jako Bridge. Navíc musí hodnota projít `Mmolio.SampleCodec`, stejným
  validátorem jako na ciferníku; neplatný paket se neuloží a zůstane poslední platné měření.
- Oprávnění `Background` je v manifestu jen proto, že sdílené soubory Bridge nesou anotaci
  `(:background)`; kompilátor ho pak vyžaduje. Pole žádnou background službu neregistruje.
- Poslední platné měření se ukládá do vlastního úložiště pole se **skutečným časem měření**
  a po restartu pole se načte. Stáří se počítá při každém překreslení (jednou za sekundu),
  i bez nových zpráv a při pozastavené aktivitě. Nikdy se nepoužívá čas příjmu.
- Zprávy přijímá callback, když je pole zobrazené v aktivitě. Při registraci převezme i
  zprávy, které pro něj Connect IQ ještě drží, ale doručení do neběžícího pole není
  zaručené – telefon může dostat chybu doručení. Do dalšího měření pole ukáže uložené
  měření s jeho skutečným stářím. Bridge nemusí být otevřený.
- Stavy: čerstvé – tyrkysová hodnota, geometrická šipka, jednotka a stáří; od limitu stáří –
  šedá hodnota, `STALE` se stářím, bez šipky; budoucí čas – `CHECK TIME`, bez šipky; bez
  platného měření (např. po nové instalaci) – `--` / `NO DATA`; neznámý trend – `?`.
- Rozložení se počítá z rozměrů `dc` a `getObscurityFlags()` (viditelná část kulatého
  displeje), ne z pevných 390 px: plné pole, 2 pole, 3 pole i kompaktní 4polový layout.
  Barvy sledují motiv aktivity (`getBackgroundColor()`): černé pozadí s tyrkysovou, nebo
  bílé pozadí s tmavě tyrkysovou hodnotou. Když není místo, zmizí nejdřív jednotka, stáří
  nikdy.
- **Nastavení jsou samostatná** (`useMmol`, výchozí mmol/L; `staleMinutes` 5–120, výchozí
  15), nezávislá na nastavení Bridge – každá Connect IQ aplikace má vlastní. Nastavují se
  v Garmin Connect / Connect IQ u aplikace Mmolio DataField.
- Pole neřídí aktivitu, nevibruje a nezapisuje do FIT.

Přidání do aktivity na FR165 (názvy položek podle českého manuálu hodinek): v profilu
aktivity (např. Běh) otevři nastavení aktivity podržením UP → Datové obrazovky → vyber
obrazovku a pole → Connect IQ → **Mmolio DataField**. Na zařízeních s API 5.2 nabídne
Garmin po instalaci také přiřazení pole k aktivitám.

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

Skript kontroluje přesnou verzi SDK, používá kontrolu typů `-l 2`, sestaví release všech
tří aplikací a skončí chybou, pokud kterýkoli build selže:

```text
build/fr165/release/MmolioBridge.prg
build/fr165/release/MmolioWatchFace.prg
build/fr165/release/MmolioDataField.prg
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
& "$Sdk\bin\monkeyc.bat" -f garmin/MmolioDataField/monkey.jungle -d fr165 -o build/fr165/release/MmolioDataField.prg -y $Key -l 2 -r
if ($LASTEXITCODE -ne 0) { throw 'DataField build failed' }
```

## Kontroly

```bash
.github/scripts/garmin-checks.sh
./garmin/scripts/build-fr165.sh --test
"$CONNECTIQ_SDK/bin/connectiq"
# V druhém terminálu, s běžícím simulátorem:
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioBridge.prg fr165 -t
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioWatchFace.prg fr165 -t
"$CONNECTIQ_SDK/bin/monkeydo" build/fr165/test/MmolioDataField.prg fr165 -t
```

Testy DataFieldu ověřují příjem paketu v1, zachování času měření po restartu, přesnou
hranici zastarání, duplicitní, starší a opožděné pakety podle pravidel Bridge, odmítnutí
neplatných paketů se zachováním posledního platného, budoucí čas, mmol/L i mg/dL,
čtyřmístné mg/dL, velké timestampy a validaci vlastních nastavení. Testy po sobě mažou
uložené měření, protože simulátor sdílí úložiště s aplikací.

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
- Monkey C testy spuštěné v simulátoru SDK 9.2.0: **Bridge 8/8, WatchFace 5/5**, bez chyb.
- GitHub Actions Garmin project checks: prošly. Zdrojové soubory byly porovnány s commitem
  na cílové větvi; jde o stejné soubory, ze kterých vznikly ověřené buildy.
- Vizuálně zkontrolovaný skutečný renderer v simulátoru FR165 s testovacími hodnotami:
  čerstvá/stará/chybějící hodnota, budoucí timestamp, neznámý trend, čtyřmístné mg/dL,
  čerstvá i stará data v AMOLED sleep. Bez překrytí nebo oříznutí textu.
- Finální release ciferníku spuštěný bez publisheru: `NO DATA`, nativní tep a nula kroků
  zobrazené správně, bez runtime chyby.
- USB sideload a ověření nové verze na fyzických hodinkách nebyly provedené.

### Stav ověření Mmolio DataField 21. 9. 2026

- Všechny tři release i test buildy pro FR165 přes `build-fr165.sh`: **BUILD SUCCESSFUL**,
  SDK 9.2.0, `-l 2`. Release Bridge a WatchFace jsou bajtově shodné s předchozími
  ověřenými buildy (SHA-256 `eacd0fe1…` a `1fd9cc3b…`).
- Monkey C testy DataFieldu v simulátoru SDK 9.2.0: **12/12** (7 nových a 5 sdílených testů
  kodeku).
- Produkční release DataFieldu po testech v tomtéž simulátoru: `-- / NO DATA`, bez runtime
  chyby.
- Vizuální kontrola produkčního rendereru v přesných layoutech FR165 ze `simulator.json`
  (1, 2, 3 a 4 pole, tmavé i světlé téma). Simulátor se před každým scénářem čistě
  restartoval a načtení správného scénáře bylo ověřeno značkou v logu. Stavy: čerstvé, STALE
  (1h12m, 2h5m, 23h59m, 12d), CHECK TIME, NO DATA, neznámý trend, dvojité šipky,
  čtyřmístné mg/dL. Bez překrytí a ořezu.
- Příjem zpráv z telefonu simulátor neověří; to zbývá na hodinkách s aktualizovaným
  xDrip4iOS.

## Nasazení aplikací přes USB – pro Claude Code

Mmolio DataField je nová aplikace s novým ID: nahrává se jako nový soubor
`MmolioDataField.prg`, nic nepřepisuje. Data dostane jen s aktualizovaným xDrip4iOS.

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
