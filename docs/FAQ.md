# Časté otázky

## Obecné

### Nahrazuje mi to oficiální aplikaci nebo alarmy?
Ne, a není to tak myšlené. Mmolio jen zobrazuje hodnotu, kterou už naměřil váš senzor.
Alarmy oficiální aplikace si nechte zapnuté. Viz [upozornění](DISCLAIMER.md).

### Musím používat xDrip4iOS?
Pro hodinky ano, protože posílá měření do Bridge. Worker přijímá cokoli, co umí nahrávat
do Nightscoutu, takže tam si vystačíte i s jiným zdrojem.

### Funguje to i na Androidu nebo s jinými hodinkami?
Worker a displeje ano, ty jsou na zdroji nezávislé. Aplikace pro hodinky jsou postavené
a ověřené pro **Forerunner 165**. Jiné modely Garminu by šly přidat do `monkey.jungle`
a manifestu, ale rozvržení ciferníku počítá s kulatým displejem a nikdo to jinde netestoval.

### Odesílá se něco někam?
Vaše hodnoty tečou z telefonu do vašeho workeru na vašem účtu u Cloudflare a do vašich
hodinek. Nikam jinam. Pozor ale na to, že **adresa workeru je veřejně čitelná** – kdo ji
zná, vidí vaši poslední hodnotu.

---

## Worker

### `/api/glucose` vrací 503
Znamená to „zatím nedorazilo žádné měření“ a skoro vždy je to na straně telefonu:
špatná adresa v xDripu, špatné API_SECRET nebo vypnuté nahrávání. Zkontrolujte, že
v xDripu projde **Test connection**.

### Test connection v xDripu neprojde
Adresa musí být celá, i s `https://`, a bez lomítka na konci. Tajemství musí mít aspoň
12 znaků. Worker musí být nasazený; ověřte si to tím, že se adresa otevře v prohlížeči.

### Po nasazení najednou nic nechodí
Nejspíš zmizely bindingy. `wrangler deploy` odstraní z workeru všechno, co nenajde
v konfiguračním souboru, takže KV i tajemství musí být ve `wrangler.local.toml`, ne jen
naklikané v dashboardu.

### `.get()` na tajemství spadne na „parameter 1 is not of type 'string'“
Staré `compatibility_date`. Se starým datem runtime vyrobí z bindingu obecný Fetcher.
Musí být aspoň `2026-05-01`.

### Chci měnit meze pro barvy
Ve `worker/public/index.html` ve funkci `colorForValue()`, u rozšíření v `config.json`
a na hodinkách v nastavení Bridge a DataFieldu.

---

## Rozšíření do GNOME

### Změnil jsem `extension.js` a nic se nestalo
Wayland neumí rozšíření přenačíst za běhu. Musíte se odhlásit a přihlásit. Naopak
`config.json` se čte živě, takže se v něm dá ladit bez odhlašování.

### Jak zjistím, proč rozšíření nefunguje
```bash
gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
  --method org.gnome.Shell.Extensions.GetExtensionErrors "glykemie@sejkora.local"
```

### Alarm mě ruší
V nabídce rozšíření je přepínač **Alarm**. Vypne i ten, který zrovna zvoní, a volba
vydrží i po odhlášení. Hodnota se dál barví a upozornění v liště chodí dál.

---

## Hodinky

### Na hodinkách je `NO DATA`
Bridge zatím nedostal žádné měření, nebo ho nedostalo datové pole. Datové pole má vlastní
application ID a **posílá se do něj zvlášť**, takže potřebujete verzi xDripu, která to umí.
Po instalaci je `NO DATA` správně až do prvního měření.

### Ciferník ukazuje `NO DATA`, i když Bridge hodnotu má
Obě aplikace musí být podepsané **stejným vývojářským klíčem**, jinak ciferník privátní
complication Bridge neuvidí. Zkontrolujte taky, že Bridge byl po instalaci aspoň jednou
otevřený.

### Co znamená `STALE`
Hodnota je starší než nastavená hranice (výchozí 15 minut). Zešedne, zmizí u ní trendová
šipka i barevný prstenec. Je to záměr: starý údaj se nikdy nesmí tvářit jako aktuální.

### Co znamená `CHECK TIME`
Čas měření je v budoucnosti, takže se mu nedá věřit. Obvykle je špatně nastavený čas
v hodinkách nebo v telefonu.

### Displej se nerozsvítí zvednutím ruky
To hodinky, ne Mmolio. Aplikace rozsvícení nemůže vyvolat ani zablokovat, dělá to firmware.
Podívejte se do Systém → Displej → Všeobecné použití a Během spánku → Gesto. V režimu
spánku bývá gesto vypnuté.

### Prstenec v Always On nesvítí celý
Tak je to navržené. V úsporném režimu se kreslí jen běžící hlava s ocasem a každou minutu
se posune, aby žádný pixel na okraji nesvítil dlouho. Garmin tohle u AMOLED displejů přímo
doporučuje kvůli vypálení. Plný prstenec je vidět, když jsou hodinky probuzené.

### Jde přidat vlastní barvy nebo meze?
Meze ano, v nastavení Bridge (pro ciferník) a DataFieldu (pro pole). Barvy jsou v kódu,
v `MmolioWatchFace/source/xDripWatchFaceView.mc` a `MmolioDataField/source/FieldRenderer.mc`.

### Build skončí na chybějící definici zařízení
V SDK Manageru musí být stažené **fr165** a SDK přesně **9.2.0**; skript na to verzi
kontroluje. Definice zařízení nejsou součástí archivu SDK, stahují se zvlášť.

---

## Vývoj

### Jak si ověřím změny bez hodinek?
```bash
.github/scripts/garmin-checks.sh          # strukturální kontroly
./garmin/scripts/build-fr165.sh --test    # build s Monkey C testy
```
Testy se pak pouští v simulátoru přes `monkeydo <prg> fr165 -t`. Simulátor ale neověří
Bluetooth ani doručení z telefonu, to jde jen na skutečných hodinkách.

### Proč se složky jmenují jinak než aplikace?
Historie. Projekt se dřív jmenoval MedProbe a ciferník vznikl jako xDripWatchFace.
Vnitřní názvy modulů v Monkey C zůstaly, aby se nemusela měnit application ID a už ověřený
přenos do hodinek.

### Proč se aplikace na iPhonu jmenuje „xDrip4iO5“?
To je název přímo od autorů xDrip4iOS, s pětkou místo velkého S. S Mmoliem to nesouvisí.
