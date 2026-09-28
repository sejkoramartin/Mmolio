# Glykemie – nasazení a obsluha

> Kontext a historie rozhodnutí (proč je to postavené takhle) je v `CLAUDE.md`
> v této složce. Mapa celého repa je v kořenovém `README.md`.

Jeden Cloudflare Worker (`glykemie`) dělá tři věci: přijímá naměřené hodnoty
z xDrip4iOS, drží poslední z nich v KV a servíruje displej i JSON API.
Wrangler je v repu jako dev dependency, spouští se přes `npx wrangler`.

```
xDrip4iOS → POST /api/v1/entries → Worker → /api/glucose → displeje
```

## 1) Nastavení v xDrip4iOS

Settings → Nightscout:

- **URL:** `https://glykemie.sejkoramartin.workers.dev`
- **API_SECRET:** hodnota secretu `NIGHTSCOUT_API_SECRET` (minimálně 12 znaků)
- zapnout nahrávání

Tlačítko **Test connection** musí projít – worker má kvůli tomu
naimplementovaný endpoint `/api/v1/experiments/test`.

## 2) První nasazení na čistém účtu

```bash
npm install
npx wrangler login

npx wrangler kv namespace create TOKEN_KV
# vrácené id vlož do wrangler.toml (kv_namespaces -> id)

# tajemství pro xDrip (zeptá se interaktivně)
npx wrangler secrets-store secret create <STORE_ID> \
  --name NIGHTSCOUT_API_SECRET --scopes workers --remote
# id storu vlož do wrangler.toml (secrets_store_secrets -> store_id)

npx wrangler deploy
```

**Bindingy musí být ve `wrangler.toml`, ne jen naklikané v dashboardu.**
`wrangler deploy` z workeru odstraní všechno, co v konfiguráku nenajde –
přesně tím nám v 8/2026 přestala fungovat glykemie.

## 3) Běžná práce

```bash
# test proti živým bindingům, ale bez zásahu do produkce
npx wrangler dev --remote

# nasazení
npx wrangler deploy

# kontrola
curl -s https://glykemie.sejkoramartin.workers.dev/api/glucose
```

## 4) Na iPhonu

1. Otevři URL v Safari
2. Sdílet → **Přidat na plochu**
3. Spusť z plochy (běží fullscreen, bez Safari lišt)
4. Nastavení → Displej a jas → Automatický zámek → **Nikdy**
5. Trojklik bočního tlačítka → **Řízený přístup** → uzamkne appku na obrazovce

## 5) Na Ubuntu (GNOME)

Rozšíření je v kořeni repa, v `gnome-extension/glykemie@sejkora.local`, a nalinkuje se:

```bash
ln -sfn "$PWD/../gnome-extension/glykemie@sejkora.local" \
  ~/.local/share/gnome-shell/extensions/glykemie@sejkora.local
gnome-extensions enable glykemie@sejkora.local
```

Ukazuje hodnotu na pravém konci spodního docku, kliknutím se otevře nabídka.
Při hypo/hyper spustí alarm se zvukem.

**Nastavení je v `config.json` a načítá se za běhu** – pozice, velikosti, prahy
i alarmy se dají měnit bez odhlašování. Naopak **změna `extension.js` vyžaduje
odhlášení a přihlášení**, protože Wayland neumí rozšíření přenačíst.

## Poznámky

- xDrip nahrává po každém měření, G7 vysílá po ~5 minutách
- `/api/glucose` vrací 503, dokud nedorazí první hodnota – prázdný displej
  nesmí vypadat jako „všechno v pořádku"
- Barvy podle rozsahu: zelená 4,2–9,5 mmol/L, jinak červená; meze se upravují
  v `colorForValue()` v `worker/public/index.html` a v `config.json` u rozšíření
- Pro OLED displej (iPhone XS) se vyhni bílému pozadí na plný jas kvůli
  vypálení – proto je to navržené tmavě
