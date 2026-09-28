# Instalace

Návod krok za krokem. Nejdřív si přečtěte [upozornění](DISCLAIMER.md) – Mmolio není
zdravotnický prostředek a nenahrazuje oficiální aplikaci vašeho senzoru ani její alarmy.

Části jsou nezávislé. Worker a displeje dávají smysl samy o sobě, hodinky taky.
Postavte si jen to, co chcete.

```
senzor ──► xDrip4iOS ──┬──► Cloudflare Worker ──┬──► telefon nebo tablet jako displej
                       │                        └──► rozšíření do GNOME
                       └──► Garmin hodinky (Bridge, ciferník, datové pole)
```

## Co budete potřebovat

- **CGM senzor a iPhone s xDrip4iOS.** Mmolio si data nikde nebere samo, nechává si je
  posílat. Odkud je bere xDrip, je jeho věc.
- **Účet u Cloudflare** (stačí bezplatný) pro worker.
- **Node.js** kvůli `npx wrangler`.
- Pro hodinky navíc: **Garmin Forerunner 165**, Connect IQ SDK 9.2.0 a vlastní vývojářský
  klíč.

---

## 1. Cloudflare Worker

Worker se tváří jako server Nightscout, přijímá měření z telefonu, drží poslední hodnotu
a servíruje displej i jednoduché JSON API.

```bash
git clone https://github.com/sejkoramartin/Mmolio.git
cd Mmolio/worker
npm install
npx wrangler login
```

### Úložiště a tajemství

```bash
# KV pro poslední hodnotu – zapište si vrácené "id"
npx wrangler kv namespace create TOKEN_KV

# Trezor a v něm tajemství, kterým se telefon prokazuje
npx wrangler secrets-store store create mmolio
npx wrangler secrets-store secret create <ID-TREZORU> \
  --name NIGHTSCOUT_API_SECRET --scopes workers --remote
```

Poslední příkaz se na hodnotu zeptá interaktivně. **Zvolte si aspoň 12 znaků**, kratší
tajemství Nightscout neuznává. Nikam ho nepište a nikomu neposílejte.

### Konfigurace a nasazení

```bash
cp wrangler.toml wrangler.local.toml
```

Do `wrangler.local.toml` doplňte ID svého KV a trezoru. Soubor je v `.gitignore`, takže
vaše ID nezůstanou v repozitáři. Pak:

```bash
npx wrangler deploy -c wrangler.local.toml
```

Wrangler vypíše adresu, například `https://glykemie.vase-jmeno.workers.dev`. Tu si
poznamenejte, budete ji potřebovat dál.

> **Bindingy musí být v konfiguračním souboru, ne naklikané v dashboardu.** `deploy`
> odstraní z workeru všechno, co v souboru nenajde. Přesně tím tenhle projekt jednou
> přestal fungovat a měsíc si toho nikdo nevšiml.

### Nastavení v xDrip4iOS

Settings → Nightscout:

- **URL:** adresa vašeho workeru
- **API_SECRET:** tajemství, které jste si zvolili
- nahrávání zapnout

Tlačítko **Test connection** musí projít; worker má kvůli němu endpoint
`/api/v1/experiments/test`.

### Kontrola

```bash
curl -s https://glykemie.VASE-JMENO.workers.dev/api/glucose
```

Vrátí poslední měření. Když vrátí **503**, ještě nic nedorazilo, což je skoro vždy věc
nastavení v telefonu. Cizí zápis musí být odmítnut:

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  https://glykemie.VASE-JMENO.workers.dev/api/v1/entries -d '[]'   # čekejte 401
```

---

## 2. Displej na telefonu nebo tabletu

Hodí se na starý telefon, který leží na stole nebo visí v dílně.

1. Otevřete adresu workeru v prohlížeči.
2. Na iPhonu: Sdílet → **Přidat na plochu**. Spuštěné z plochy to běží na celou obrazovku.
3. Nastavení → Displej a jas → Automatický zámek → **Nikdy**.
4. Trojklik bočního tlačítka → **Řízený přístup** zamkne aplikaci na obrazovce.

Meze pro barvu hodnoty jsou ve funkci `colorForValue()` v `worker/public/index.html`.

---

## 3. Rozšíření do GNOME

Ukazuje hodnotu v docku, barví ji podle rozsahu a stáří a umí upozornit při hypo a hyper.
Testované na GNOME 50 (Wayland).

```bash
cd Mmolio/gnome-extension/glykemie@sejkora.local
cp config.example.json config.json      # a doplňte adresu svého workeru
cd -
ln -sfn "$PWD/gnome-extension/glykemie@sejkora.local" \
  ~/.local/share/gnome-shell/extensions/glykemie@sejkora.local
gnome-extensions enable glykemie@sejkora.local
```

Pak se odhlaste a přihlaste. **Změny v `extension.js` se projeví až po odhlášení**,
protože Wayland neumí rozšíření přenačíst za běhu. Naproti tomu `config.json` se načítá
živě, takže pozici, velikosti, meze i upozornění doladíte bez odhlašování.

V nabídce (klik na hodnotu) je přepínač **Alarm**, který upozornění vypne včetně toho,
které zrovna zvoní.

---

## 4. Hodinky Garmin

Tři aplikace pro Forerunner 165:

| Aplikace | Co dělá |
|---|---|
| **Mmolio Bridge** | přijímá měření z telefonu, i na pozadí, a publikuje je ostatním |
| **Mmolio WatchFace** | ciferník s glykemií, trendem, stářím, tepem a kroky |
| **Mmolio DataField** | datové pole do sportovních aktivit |

### Předpoklady

- **Connect IQ SDK 9.2.0** a v SDK Manageru stažená definice zařízení **fr165**
- **vlastní vývojářský klíč** (`.der`), který si vygenerujete v SDK Manageru nebo ve VS Code
- Java

Všechny tři aplikace **musí být podepsané stejným klíčem**. Bridge posílá hodnotu ciferníku
přes privátní complication a tu vidí jen aplikace se stejným podpisem.

### Sestavení

```bash
export CONNECTIQ_SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0"
export DEVELOPER_KEY="/cesta/k/vasemu/developer_key.der"
./garmin/scripts/build-fr165.sh
```

Vzniknou `build/fr165/release/MmolioBridge.prg`, `MmolioWatchFace.prg`
a `MmolioDataField.prg`. Klíč do repozitáře nepatří, `.gitignore` na `*.der` myslí.

### Nahrání do hodinek

Připojte hodinky USB kabelem a nakopírujte `.prg` do složky `GARMIN/Apps`. Na Linuxu bývá
zařízení přes MTP:

```bash
APPS='mtp://.../Internal Storage/GARMIN/Apps'
gio copy build/fr165/release/MmolioBridge.prg    "$APPS/MmolioBridge.prg"
gio copy build/fr165/release/MmolioWatchFace.prg "$APPS/MmolioWatchFace.prg"
gio copy build/fr165/release/MmolioDataField.prg "$APPS/MmolioDataField.prg"
sync
```

Po odpojení si hodinky aplikace nainstalují a soubory ze složky zmizí. To je normální.

### Na hodinkách

1. **Jednou otevřete Mmolio Bridge.** Tím se zaregistruje příjem na pozadí.
2. Jako ciferník nastavte **Mmolio WatchFace**.
3. Datové pole přidáte v profilu aktivity: podržet UP → Datové obrazovky → vybrat
   obrazovku a pole → Connect IQ → **Mmolio DataField**.
4. Jednotky, hranici stáří a meze pro barvy nastavíte v Garmin Connect u Bridge
   a zvlášť u DataFieldu.

### Odesílatel v telefonu

Do hodinek posílá **upravený xDrip4iOS**, ne tenhle repozitář. Je to fork
[`sejkoramartin/xdripswift`](https://github.com/sejkoramartin/xdripswift), větev
`feature/garmin-watch`. Bez něj hodinky žádná data nedostanou. Formát zpráv je popsaný
v [`garmin/wire-protocol.md`](../garmin/wire-protocol.md).

---

## Další čtení

- [FAQ](FAQ.md) – co dělat, když něco nefunguje
- [`garmin/README.md`](../garmin/README.md) – podrobnosti k hodinkám
- [`worker/README.md`](../worker/README.md) – provoz workeru
