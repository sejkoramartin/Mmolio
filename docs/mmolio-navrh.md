# Mmolio – CGM displej pro Windows

Souhrn všech rozhodnutí z návrhové fáze (13. 9. 2026). Tenhle dokument je
**aktuální autorita** – artifact „Glykemie pro Windows“ je původní návrh a část
jeho doporučení už je tímhle přepsaná (viz *Změny oproti návrhu* na konci).

Navazuje na projekt `glupro` (viz `CLAUDE.md`) – displej glykemie na iPhonu
a rozšíření pro GNOME. Právní texty jsou v `mmolio-pravni-texty.md`.

---

## 1. Co to je

Doplňkový displej glykemie pro Windows 10/11. Bere data z CGM senzoru a ukazuje
je v oznamovací oblasti a volitelně ve velkém okně přes obrazovku. Při hypo/hyper
upozorní zvukem a alarmovým oknem.

| | |
|---|---|
| **Název** | Mmolio |
| **Popis** | CGM displej pro Windows |
| **Trh** | výhradně Česká republika |
| **Jazyk** | pouze čeština, bez lokalizace |
| **Jednotky** | pouze mmol/l (mg/dL jen interně pro přepočet) |
| **Licence** | otevřený zdrojový kód, zdarma |
| **Cílovka** | domácí PC, kde je uživatel správcem – lidé u počítače a hráči |

Spravované firemní počítače jsou **mimo rozsah**: AppLocker a WDAC běžně blokují
spouštění z `%LOCALAPPDATA%`, kam instaluje Velopack, a nepodepsané binárky
plošně. Ty by potřebovaly podepsaný MSI/MSIX pro celý stroj – jiný produkt.

---

## 2. Zdroje dat

Klient mluví s CGM API **přímo**, přihlašovací údaje si drží lokálně ve Správci
pověření Windows. Žádný server, žádná registrace, žádná cizí data u autora.

- **LibreLinkUp** – e-mail + heslo → token (~6 měsíců)
- **Dexcom Share** – účet + heslo → `sessionId`, jen evropský `shareous1.dexcom.com`
- **Nightscout** – URL + API token

Cloudflare Worker `glykemie` se do Mmolia **netahá**. Zůstává výhradně pro
Martinova ostatní zařízení (iPhone PWA, GNOME rozšíření, plánovaný ESP32 panel).

### Proč ne sdílený server

Dnešní Worker má natvrdo jeden účet – komukoli dalšímu by ukazoval cizí
glykemii. Víceuživatelská varianta by znamenala provozovat službu držící cizí
zdravotní data: registrace, šifrované uložiště hesel, GDPR, závazek na roky.
Varianta „klient přímo“ tohle celé odklízí.

**Daň:** workaroundy kolem Abbottova WAF musí být i v klientovi, ne jen na
serveru – hlavička `User-Agent`, `version 4.16.0`, `Account-Id` jako SHA-256
z `userId`. Když Abbott něco změní, oprava se roznáší aktualizací, ne deployem.

### Normalizace

Zdroje schované za jedním rozhraním (`IGlucoseSource`), zbytek aplikace zná jen
`GlucoseReading` (mmol/l, mg/dL, trend, čas, zdroj). Přidat zdroj = napsat jednu
třídu.

Sjednocená škála trendu je **sedmistupňová** (podle Dexcomu). Libre má jen pět
stupňů a mapuje se do ní bez šikmých šipek – opačně by se informace ztrácela.

| Trend | LibreLinkUp | Dexcom Share |
|---|---|---|
| ↑↑ rychle stoupá | 5 | 1 DoubleUp |
| ↑ stoupá | 4 | 2 SingleUp |
| ↗ mírně stoupá | – | 3 FortyFiveUp |
| → stabilní | 3 | 4 Flat |
| ↘ mírně klesá | – | 5 FortyFiveDown |
| ↓ klesá | 2 | 6 SingleDown |
| ↓↓ rychle klesá | 1 | 7 DoubleDown |

---

## 3. Zobrazení

Windows nemá obdobu panelu GNOME – lišta je pro třetí strany uzavřená
a deskbandy Microsoft ve Win11 odstranil. Náhrada je dvojí:

**Tray ikona** – běží vždy, nejde vypnout. Číslo se vykresluje do bitmapy
a nastavuje jako ikona. **Pravý klik** otevírá nabídku s nastavením.

**HUD okno** – bezrámečkové, always-on-top, click-through, na zvoleném monitoru.
V nastavení **zapínatelné a vypínatelné**. Jediná varianta čitelná z dálky.

> **Past ve Win11:** nové ikony v oznamovací oblasti systém schovává do
> přetékací nabídky a uživatel je musí ručně vytáhnout. Musí to říct uvítací
> obrazovka, jinak polovina lidí nahlásí, že se nic nezobrazilo.

### Overlay ve hrách

Vstřikování knihovny do procesu hry à la Steam/Discord je **zamítnuté**.
Antipodvodní systémy (EAC, BattlEye, Vanguard) to detekují jako cheat; Steam
a Discord mají výjimku, neznámá aplikace ji mít nebude. Nejlepší možný výsledek
je zablokovaný overlay, nejhorší ban účtu.

Řešení místo toho:
1. **Zvuk** – přehraje se bez ohledu na režim hry, u hypa stejně nechceš, aby si
   toho člověk všiml koutkem oka
2. **Always-on-top okno** – funguje přes bezrámečkové okno, což dnes používá
   většina her
3. **Druhý monitor** – hráči je často mají, spolehlivost 100 %
4. **Widget do Herního panelu (Win+G)** – oficiální cesta pro pravý
   celoobrazovkový režim, ale samostatný projekt a distribuce přes Store.
   Až podle poptávky, ne ve fázích 1–4.

---

## 4. Alarmy

Stavový automat hypo / v normě / hyper. Hlásí se při změně stavu nebo po
vypršení prodlevy, **nikdy ze zastaralých dat**.

1. **Dvě úrovně hypo** – běžná (výchozí 4,2 mmol/l) a urgentní (výchozí 3,0).
   Urgentní je hlasitější a nejde odklepnout tak snadno.
2. **Odložit / vypnout max. na 6 hodin** (podle vzoru Dexcomu). Po uplynutí se
   alarmy **samy znovu aktivují**, trvale vypnout nejdou.
3. **Tichý režim od–do** (typicky 22:00–7:00). Uživatel v něm zvlášť volí, jestli
   mlčí jen hyper, nebo i hypo. *Od buzení má telefon.*
4. **Alarm na rychlý pád** – upozorní, i když je hodnota ještě v rozsahu, ale
   rychle klesá (6,0 se šipkou ↓↓ je za chvíli 3,5).
5. **Výpadek dat** – výchozí práh 20 minut bez čerstvé hodnoty, změnitelný.
   Podléhá stejnému tichému režimu.

Kanály: systémový toast (vyžaduje `AppUserModelID`, tedy zástupce v nabídce
Start) + **vlastní alarmové okno** – celoobrazovkové na zvoleném monitoru,
pulzující, se smyčkovým zvukem, zavře se kliknutím nebo návratem do rozsahu.

> **Bezpečnostní požadavky, ne detaily:**
> - Konec odložení se ukládá **na disk**, ne do paměti – restart aplikace ani
>   počítače nesmí odložení potichu zrušit ani ztratit.
> - Vypnutí hypo alarmů v tichém režimu musí být **vědomá volba**, nikdy výchozí
>   stav, a s varováním u té volby.
> - Ticho na lince **není** totéž co „glykemie je v pořádku“. Přesně tenhle
>   scénář nastal v 9/2026 u Workeru – displej měsíc ukazoval poslední hodnotu
>   a nikdo nic nepoznal.

---

## 5. Technologie

**.NET 8 (LTS) + WPF, C#.** Tray ikona, vrstvená okna, toasty, Správce pověření
i sledování souborů jsou nativně, bez knihoven třetích stran, a k Windows API se
dá sáhnout přímo (click-through okno).

**Build self-contained** (~150 MB – WPF nelze trimovat). Zvoleno vědomě: dnes má
každý rychlý internet a odpadá tím závislost na .NET Desktop Runtime, jehož
instalace vyžaduje práva správce. Instalace je tak opravdu bez UAC.

- Velopack dělá **rozdílové** aktualizace, takže velikost bolí jen poprvé.
- Důsledek: bezpečnostní záplaty .NET se roznášejí novým buildem aplikace,
  ne přes Windows Update. Občas zkontrolovat.

---

## 6. Instalace a distribuce

**Velopack** – instalace bez práv správce, automatické rozdílové aktualizace,
zdroj GitHub Releases.
**GitHub Releases** jako primární kanál, **WinGet** jako doplňkový pro technicky
zdatné – ne jako jediný, protože cílovka jsou diabetici, ne vývojáři.

**Autostart** přes `HKCU\…\CurrentVersion\Run`, per-uživatel, s přepínačem
v nastavení. Po startu nesmí být displej prázdný – poslední známá hodnota se
ukládá a zobrazí ztlumeně, než dorazí čerstvá.

**Provozní drobnosti**, na kterých stojí, jestli to lidem vydrží běžet:
- obnovit hned po probuzení z uspání a při návratu sítě
- exponenciální odstup při chybách, nikdy se neptat častěji než jednou za minutu
- uvolňovat handle ikony po každém překreslení, jinak aplikace za den vyčerpá
  GDI objekty
- lokální log s rotací

### SmartScreen

Nepodepsaný instalátor stažený prohlížečem uvítá hláškou „Windows ochránil váš
počítač“. WinGet ji z velké části obchází (nenasazuje Mark-of-the-Web), ale není
to zaruč­ená vlastnost a **Smart App Control** ve Win11 nepodepsané binárky
blokuje bez ohledu na původ. Podpisový certifikát dnes vyžaduje hardwarový token
nebo cloudové HSM, řádově tisíce korun ročně – rozhodnutí o penězích, ne o kódu.

---

## 7. Právní rámec

**MDR 2017/745** může software sledující fyziologické pochody klasifikovat jako
zdravotnický prostředek; aplikace hlásící hypoglykemii je přesně na hraně.
Certifikace je pro jednotlivce nedosažitelná.

Zvolený postoj je ten, ve kterém **Nightscout a xDrip+** fungují přes deset let:
otevřený kód, zdarma, žádná tvrzení o léčbě, „na vlastní riziko“. Zpoplatnění
nebo diagnostická tvrzení by expozici skokově zvýšila.

- **Žádná telemetrie ani hlášení pádů.** Jen lokální log, který uživatel sám
  přiloží. Drží to projekt mimo GDPR – autor není správce ani zpracovatel.
- **Mmolio nikdy nesmí vystupovat jako primární alarm.** Uživatel si ponechává
  zapnuté alarmy v oficiální aplikaci – to je zároveň pravda, takže se to dobře
  obhajuje.
- **Ochranné známky** – „Libre“, „FreeStyle“ ani „Dexcom“ nesmí být v názvu ani
  logu, v popisu jen popisně („oficiální aplikace senzoru“).

Znění upozornění pro instalátor, první spuštění, O programu a nastavení je
v `mmolio-pravni-texty.md`.

---

## 8. Fáze

| # | Co | Odhad |
|---|---|---|
| 1 | Tray ikona + HUD okno, jeden zdroj, nastavení v souboru | ~2–3 dny |
| 2 | `IGlucoseSource` + LibreLinkUp přímo, Správce pověření, okno nastavení, alarmy | ~3–4 dny |
| 3 | Dexcom Share + Nightscout, sjednocená škála trendu | ~2–3 dny |
| 4 | Velopack, autostart, aktualizace, GitHub Releases, uvítací obrazovka | ~2 dny |

Fáze 1 původně počítala s Workerem jako zdrojem, aby se neladilo nové API.
Protože Worker vypadl ze hry, začne se rovnou LibreLinkUpem – fáze 1 a 2 se tím
částečně slévají.

---

## 9. Rizika

| Riziko | Dopad | Co s tím |
|---|---|---|
| Abbott/Dexcom změní API | vysoký | zdroje za rozhraním, aktualizace roznese opravu do dne |
| SmartScreen u nepodepsaného balíku | vysoký | rozhodnout o certifikátu dřív než o distribuci |
| Tichý výpadek dat | vysoký | stáří hodnoty je prvotřídní stav – barva i alarm |
| Zablokování účtu při častém dotazování | střední | exponenciální odstup, max. 1×/min |
| Ikona schovaná v přetékací nabídce Win11 | střední | uvítací obrazovka, HUD jako záloha |
| Únik GDI handle u překreslované ikony | střední | `DestroyIcon` po každé výměně, test přes noc |
| Podpora uživatelů | střední | jen issue tracker na GitHubu, nic víc |
| Přebalení instalátoru někým cizím | nízký | jediný oficiální odkaz, zveřejněné kontrolní součty |

---

## 10. Co ověřit před implementací

- **Dexcom Share** jsme nikdy nevolali. Konkrétní tvar požadavků ověřit proti
  živě udržovaným implementacím (Nightscout bridge, `pydexcom`), ne psát po
  paměti – u Libre nás to už dvakrát kouslo.
- **Chování SmartScreenu a Smart App Control** u instalace přes WinGet ověřit
  aktuálním testem, ne odhadem.
- **Dostupnost jména Mmolio** – GitHub, případně doména. Udělat dřív, než se
  objeví v manifestech a instalátoru.

---

## Změny oproti původnímu návrhu

Artifact „Glykemie pro Windows“ obsahuje tato už neplatná doporučení:

1. **Worker jako čtvrtý zdroj** – zrušeno, do Mmolia se netahá
2. **Build závislý na runtime** – zvolen self-contained
3. **Mezinárodní použití** – jen ČR a jen česky, což ruší volbu jednotek
   i volbu regionu Dexcomu (natvrdo `shareous1`)
4. **Firemní počítače** – explicitně mimo rozsah
