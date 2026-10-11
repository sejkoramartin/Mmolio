# Instalace Mmolio do hodinek Garmin

[English instructions](GARMIN-INSTALL.md) · [Stažení a poznámky k vydání](https://github.com/sejkoramartin/Mmolio/releases)

Potřebujete iPhone s xDrip4iOS obsahujícím nastavení **Garmin Watch**, Garmin Connect,
podporované hodinky, počítač a datový USB kabel. Pro přenos z telefonu do hodinek
není potřeba Nightscout, Mmolio server ani Wi-Fi v hodinkách. Cloudový zdroj glykémie
nadále potřebuje internet pro získávání nových měření.

**Připravené balíčky jsou testovací kandidáti.** Úspěšné sestavení nepotvrzuje provoz
na fyzických hodinkách. Před instalací přečtěte stav ověření u konkrétního vydání.
Pokud v Releases žádné vydání není, instalační balíčky ještě nebyly zveřejněné.
Integrace do oficiálního xDrip4iOS se teprve připravuje; návod neslibuje její
přítomnost v současném oficiálním vydání.

Mmolio je doplňkový displej a v hodinkách nemá alarmy glykémie. Přečtěte si
[upozornění](DISCLAIMER-CS.md) a ponechte své obvyklé aplikace a alarmy.

## 1. Vyberte přesný model

V části **Assets** konkrétního vydání stáhněte odpovídající ZIP. Pro instalaci do
hodinek nepoužívejte položku **Source code** — ta je pro vývojáře.

| Hodinky | Konec názvu balíčku | Fyzické ověření tohoto kandidáta |
| --- | --- | --- |
| Forerunner 165 | `-fr165.zip` | Čeká na ověření |
| fēnix 7X Pro | `-fenix7xpro.zip` | Čeká na ověření |
| fēnix 7X Pro – Solar Edition (no Wi-Fi) | `-fenix7xpronowifi.zip` | Čeká na ověření |

Jde o produktové identifikátory Garmin SDK. Samotné slovo „Solar“ nestačí k výběru.
Přesný model ověřte podle informací o zařízení a dokumentace Garmin; při nejistotě
se před instalací zeptejte. To, zda chcete Wi-Fi používat, nerozhoduje o variantě
balíčku. Jiné Forerunnery, Fenixy, velikosti ani Music varianty tím nejsou pokryté.

## 2. Rozbalte a nahrajte aplikace

1. ZIP rozbalte v počítači. Soubor `START-HERE.txt` uvádí přesný model a umístění návodu.
2. Připojte hodinky datovým USB kabelem. V jejich úložišti otevřete `GARMIN/APPS`
   (může být zobrazeno jako `GARMIN/Apps`). Pokud úložiště nevidíte, použijte postup
   Garmin pro přenos souborů pro váš model a operační systém.
3. Ze složky `apps` zkopírujte do `GARMIN/APPS` soubory `MmolioBridge.prg` a
   `MmolioWatchFace.prg`. Volitelně přidejte `MmolioDataField.prg` pro aktivity.
   Kopírují se samotné soubory, nikoli ZIP nebo celá složka `apps`.
4. Hodinky bezpečně odpojte. **Jednou otevřete Mmolio Bridge**, potom nastavte
   **Mmolio WatchFace** jako ciferník. Otevření Bridge zaregistruje příjem na pozadí.

Bridge přijímá data, ciferník je zobrazuje. Datové pole přijímá vlastní kopii při
běhu v aktivitě. Bridge a ciferník musejí pocházet ze stejného kompatibilního
vydání a být podepsané stejným klíčem. Balíček je takto připravený — nic nekompilujete.

## 3. Zapněte přenos v xDripu

1. Spárujte hodinky v Garmin Connect na iPhonu a povolte Bluetooth.
2. V kompatibilním xDripu otevřete **Settings → Sharing and Services → Garmin Watch**.
   Chybějící sekce znamená, že daný build tuto integraci neobsahuje.
3. Zapněte sdílení a zvolte **Find / Change Watch**. Potvrďte hodinky v Garmin Connect
   a vraťte se do xDripu. Při více zařízeních vyberte jedny v nabídce **Watch**.
4. Po připravení spojení stiskněte **Resend Latest Reading**. Starší osobní buildy
   používají název **Send Test Reading**. Posílá se poslední skutečné měření.
5. Porovnejte hodnotu, šipku a stáří na hodinkách s xDripem. Údaj **Last Bridge
   Transfer** potvrzuje jen přenos SDK, nikoli skutečné zobrazení na ciferníku.
6. Ověřte několik nových měření také se zamčeným iPhonem a zavřeným Bridge.
   Datové pole přidejte na obrazovku aktivity a ověřte při jejím běhu.

Osobní/upravený xDrip nepřepisujte jiným buildem bez ověření kompatibility jeho dat.
Pro instalaci do telefonu platí návod k danému vydání xDripu.

## 4. Co znamenají stavy

| Stav | Význam a kontrola |
| --- | --- |
| `NO DATA` / `--` | Chybí platné měření. Zkontrolujte Bridge, jednou jej otevřete, ověřte Bluetooth a výběr v xDripu. |
| `STALE` | Měření je staré. Zkontrolujte poslední měření v telefonu a spojení; čas doručení není čas měření. |
| `CHECK TIME` | Čas měření je vůči hodinkám v budoucnosti. Zkontrolujte hodiny zařízení. |
| Šipka `?` | Neznámý trend, nikoli stabilní glykemie. |
| Bridge funguje, ciferník ne | Nahrajte odpovídající Bridge i ciferník z jednoho vydání a znovu otevřete Bridge. |
| Pole se neaktualizuje | Musí běžet v aktivitě a xDrip musí podporovat přímé odesílání do pole. Počkejte na nové měření. |

Od přijímače **2026.10.11-rc2** s aktualizovaným Garmin rozšířením xDripu přebírají
Bridge, ciferník i datové pole jednotky automaticky z běžného nastavení xDripu:
mmol/L s jedním desetinným místem nebo celé mg/dL. Další přepínač není potřeba.
Změna jednotek znovu odešle poslední skutečné měření s původním časem. Bez spojení
se odešle po jeho obnovení; datové pole musí běžet v aktivitě. Po aktualizaci
počkejte na nové měření. Starší telefon bez informace o jednotkách používá místní
nastavení každého přijímače; starší aplikace v hodinkách je nutné aktualizovat.

Výchozí limit stáří je 15 minut. Nastavení hodinek popisuje [technický návod](../garmin/README-CS.md).
Dosah Bluetooth, uspání iOS, ruční ukončení aplikace nebo omezení hodinek mohou
přenos zpozdit nebo zastavit. Nepřetržitý běh na pozadí není garantovaný.

## Aktualizace a odebrání

Před aktualizací si poznamenejte verze a nastavení a pokud možno uchovejte původní
soubory Mmolio. Starší instalace mohou používat `MedProbe.prg` a `xDripWatchFace.prg`:
aktualizujte odpovídající aplikace pod jejich původními názvy, nenechávejte vedle sebe
staré a nové kopie. Bridge i ciferník aktualizujte společně a potom otevřete Bridge.
Nemažte ostatní aplikace ani data Garmin.

Přenos zastavíte vypnutím Garmin sdílení v xDripu. Již předaná zpráva může ještě dorazit
a poslední hodnota zůstane uložená s původním stářím. Pro odebrání nejdřív nastavte
jiný ciferník a odstraňte datové pole z aktivity, potom odinstalujte komponenty Mmolio
postupem správy aplikací v hodinkách.

## Verze, kontrolní součty a zdroj

ZIP obsahuje licenci GPL-3.0, upozornění v obou jazycích, návody, `RELEASE.json`
(model, verze, zdrojová revize, SDK a stav ověření) a `SHA256SUMS`. Vydání obsahuje
kontrolní součty samotných ZIPů. Součet odhalí změnu souboru, nepotvrzuje však
funkčnost na hodinkách ani důvěryhodnost cizího zdroje. Stahujte z repozitáře Mmolio.

Odkaz na přesný zdroj a samostatný archiv zdrojů je v `RELEASE.json`; zdrojový kód
není přimíchaný do instalačního ZIPu. Viz [licence](../LICENSE).
Při hlášení problému uveďte verzi balíčku, model a firmware hodinek, verzi iOS/xDripu
a zobrazený stav. Nezveřejňujte historii glykémie, soukromý klíč ani identifikátory zařízení.
