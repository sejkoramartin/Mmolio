# Worker a displeje – kontext

> Součást repa Mmolio. Pravidla pro celý projekt jsou v kořenovém `CLAUDE.md`,
> tenhle soubor je o workeru, displeji pro iPhone a GNOME rozšíření.

Displej glykemie na starém iPhone XS (fullscreen, landscape) a v liště
Ubuntu/GNOME, napájený z Cloudflare Workeru, do kterého **xDrip4iOS nahrává
naměřené hodnoty**. Do budoucna možná LED matice Ulanzi TC001 a vlastní
ESP32 panel do dílny.

## Architektura

```
Dexcom G7 senzor
        │ Bluetooth
        ▼
xDrip4iOS (iPhone) ──┐  souběžně s CamAPS FX, která řeší léčbu
        │            └─→ doplněk pro Garmin hodinky
        │ HTTPS POST /api/v1/entries (push)
        ▼
Cloudflare Worker "glykemie" (worker.js)
  - tváří se jako Nightscout server, přijímá měření a drží poslední v KV
  - /api/glucose → vrací poslední hodnotu jako jednoduché JSON
  - cokoliv jiného → static assets binding servíruje public/index.html
        │
        ├─→ iPhone XS — Safari → "Přidat na plochu" → fullscreen PWA
        │       (auto-zámek Nikdy + Řízený přístup, aby nezhasínalo)
        └─→ GNOME rozšíření glykemie@sejkora.local (HUD v docku + alarmy)
```

**Klíčové rozhodnutí: push místo dotazování.** Dřív se worker sám ptal
LibreLinkUpu (do 9/2026) a pak Dexcom Share (9/2026). Obojí jsou neveřejná
rozhraní mobilních aplikací a za jediný měsíc nás třikrát položila – WAF,
přesměrování na region, zamykání účtu. Teď data tečou sama z telefonu,
takže na cizím API nezávisíme vůbec a odpadlo i ukládání hesel k cizím
službám.

## Stav (funkční, ověřeno 28. 9. 2026)

- Jeden Worker `glykemie.VASE-JMENO.workers.dev` servíruje frontend
  i backend
- KV namespace `TOKEN_KV`, klíč `ns_latest` – poslední měření
- Secret `NIGHTSCOUT_API_SECRET` v Cloudflare **Secrets Store**
- Nastavení v xDrip4iOS → Settings → Nightscout:
  URL `https://glykemie.VASE-JMENO.workers.dev`, API_SECRET = ten secret
- `index.html` obarvuje číslo: zelená 4,2–9,5 mmol/L, jinak červená
- Wake Lock API použit k potlačení zhasínání (funguje jen omezeně na
  iOS Safari – primární obrana je stejně auto-zámek Nikdy + Guided Access)

### Výstup /api/glucose

```json
{"mgdl":286,"mmol":15.9,"trendArrow":3,"trendSymbol":"→","trendAngle":0,
 "trendName":"Flat","timestamp":"2026-09-28T09:56:55.238Z",
 "device":"DXCM9r","source":"xdrip"}
```

`trendArrow` schválně zůstává ve staré pětistupňové škále (1=↓↓ … 5=↑↑),
aby nebylo nutné měnit klienty. `trendAngle` je přesnější úhel včetně
šikmých šipek (Nightscout/Dexcom mají sedm stupňů), zatím ho nikdo nepoužívá.

## Věci, na které jsme přišli trial-and-error (nezapomenout)

1. **xDrip4iOS nahrává na `POST /api/v1/entries`** s hlavičkou
   `api-secret` = **SHA-1 otisk** tajemství (nikdy ne tajemství samotné).
   Spojení testuje přes `GET /api/v1/experiments/test`, takže ten endpoint
   musí existovat, jinak v appce neprojde "Test connection". Posílá i
   `/api/v1/devicestatus`, `/api/v1/treatments` a `/api/v1/profile` –
   neukládáme je, ale musíme odpovědět úspěchem, jinak hlásí chyby.
   Ověřeno ve zdrojácích: `NightscoutSyncManager.swift`,
   `BgReading+Nightscout.swift`.
2. **Dávka může obsahovat i starší doplněná měření.** Nikdy jimi nesmí
   přepsat novější hodnotu – řeší `storeIfNewer()`. Bez toho by stará
   hodnota vypadala jako aktuální, což je nejhorší možná chyba tohohle
   projektu (viz bod 4).
3. **Tajemství musí mít aspoň 12 znaků** – Nightscout kratší neuznává.
4. **Ticho na lince není totéž co "glykemie je v pořádku".** Když data
   nechodí, musí to být vidět. Displej i rozšíření proto barví hodnotu
   podle stáří a `/api/glucose` vrací 503, dokud nedorazí první měření.
   V 8–9/2026 nám worker měsíc nefungoval a nikdo si nevšiml.
5. **Bindingy musí být ve `wrangler.toml`, ne jen naklikané v dashboardu** –
   `wrangler deploy` z workeru odstraní všechno, co v konfiguráku nenajde.
   Přesně tím nám v 8/2026 zmizely Secrets Store bindingy.
6. **Cloudflare Secrets Store bindings nejsou stringy** – `env.X` je objekt
   s async metodou `.get()`, ne přímo hodnota. Řeší `resolveSecret()`.
   Klasické "Environment Variables (encrypted)" by byly stringy přímo.
7. **Secrets Store binding potřebuje novější `compatibility_date`** – se
   starým (`2024-01-01`) runtime vyrobí obecný `Fetcher` a `.get()` spadne
   na `parameter 1 is not of type 'string'`. Od `2026-05-01` funguje.
8. **mmol/l se počítá z mg/dL dělením 18,0182** (zdroje posílají mg/dL).
9. **Diagnostika:** dočasný debug endpoint + `wrangler dev --remote`
   (běží na Cloudflare s reálnými bindingy, nesahá na produkci). Pro test
   bez produkce jde založit tajemství v lokálním úložišti – stejný příkaz
   bez `--remote`.

### Historie datových zdrojů (proč to vypadá, jak vypadá)

- **do 9/2026 LibreLinkUp** (FreeStyle Libre 2+): vyžadoval `User-Agent`
  jinak WAF vracel 403, minimální `version` 4.16.0, hlavičku `Account-Id`
  (SHA-256 z userId) a uměl přesměrovat na regionální server i z
  `/llu/connections`, nejen z loginu.
- **9/2026 Dexcom Share**: dvoukrokové přihlášení (účet → accountId →
  sessionId), region `shareous1` pro mimo USA, `applicationId` konstanta
  z open-source klientů. Po několika špatných heslech zamyká účet, takže
  se přihlášení nesmělo opakovat ve smyčce.
- **od 9/2026 xDrip4iOS push** – současný stav.

## Další kroky / nápady (neimplementováno)

- **Hlídání výpadku + push na telefon** (Cron Trigger ve Workeru + ntfy.sh).
  Nejvyšší priorita z tohohle seznamu – řeší scénář z bodu 4.
- **Graf posledních hodin.** Teď se ukládá jen poslední měření; stačilo by
  v KV držet krátkou historii, protože data už stejně chodí sama.
- **Ulanzi TC001** (ESP32 + 32×8 RGB matice, firmware Awtrix 3, HTTP API)
  jako doplňkový displej – vhodné spíš na stůl zblízka, ne na dálku přes
  dílnu (nízké rozlišení).
- **Mmolio** – samostatná desktopová aplikace pro Windows, vlastní návrh
  v `docs/mmolio-navrh.md` a `docs/mmolio-pravni-texty.md`.

## Deploy

Viz `worker/README.md`. Wrangler je v repu jako dev dependency (`npx wrangler`),
přihlášení přes OAuth (`npx wrangler login`), takže není potřeba API token.

## Poznámky k prostředí

- Uživatel (Martin) je diabetik, pracuje jako automechanik (fyzicky
  náročné prostředí).
- Senzor Dexcom G7, léčbu řeší **CamAPS FX**; xDrip4iOS běží souběžně kvůli
  doplňku pro Garmin hodinky – a nově i jako zdroj dat pro tenhle projekt.
- Aplikaci Dexcom G7 už nepoužívá, takže `DEXCOM_*` ani `LIBRE_*` secrets
  nejsou k ničemu a je možné je ze Secrets Store smazat.
