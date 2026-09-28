# Předání projektu

Pro novou session, která projekt přebírá. **Přečti si nejdřív `CLAUDE.md`** –
je tam architektura a hlavně seznam věcí, na které jsme přišli trial-and-error.
Tenhle dokument je o tom, co potřebuješ vědět navíc, abys mohl pokračovat.

Stav k 28. 9. 2026: **funkční a nasazené**, čerstvě po migraci z Dexcom Share
na push z xDrip4iOS. Od téhož dne je projekt součástí repa `sejkoramartin/Mmolio`
(dřív samostatná složka `glupro` mimo git).

---

## 1. Co běží a kde

| | |
|---|---|
| Worker | `glykemie` na `https://glykemie.VASE-JMENO.workers.dev` |
| KV namespace | `TOKEN_KV`, id `<ID-VASEHO-KV>` |
| KV klíč s daty | `ns_latest` – poslední měření |
| Secrets Store | id `<ID-VASEHO-SECRETS-STORE>` |
| Jediný secret | `NIGHTSCOUT_API_SECRET` |
| GNOME rozšíření | `~/.local/share/gnome-shell/extensions/glykemie@sejkora.local` → **symlink** do `gnome-extension/` v projektu |

Zdroj dat je **xDrip4iOS na iPhonu**, který do workeru nahrává měření, jako by
to byl Nightscout. Worker se nikam neptá. Souběžně uživateli běží **CamAPS FX**,
která řeší léčbu – té se nedotýkáme a data z ní nebereme.

## 2. Přístupy

`wrangler` je přihlášený přes **OAuth** (`~/.config/.wrangler/config/default.toml`),
takže `npx wrangler deploy` prostě funguje a **žádný API token není potřeba**.
Kdyby session vypršela, `npx wrangler login` – ale pozor, jednou nám to spadlo
na `invalid_scope` a museli jsme to zkusit znovu.

**Nikdy si nenech posílat hesla a tokeny do chatu.** Uživatel to jednou udělal
s Cloudflare tokeny a musel je pak revokovat. Příkazy, které se ptají na tajné
hodnoty, mu dej k ručnímu spuštění – `wrangler` se na ně interaktivně zeptá.

## 3. Mapa souborů

Od 28. 9. 2026 je tohle součást repa **Mmolio**, cesty jsou vůči jeho kořeni:

```
worker/worker.js          backend i směrování; přijímá měření, servíruje /api/glucose
worker/wrangler.toml      konfigurace; POZOR: bindingy musí být tady, ne v dashboardu
worker/public/index.html  displej pro iPhone (fullscreen PWA)
worker/CLAUDE.md          architektura + trial-and-error poznatky
worker/README.md          nasazení a obsluha
gnome-extension/…/        rozšíření pro GNOME 50 – HUD v docku, alarmy
  extension.js            logika (změna vyžaduje odhlášení, viz níž)
  config.json             nastavení, načítá se ZA BĚHU
docs/mmolio-navrh.md      návrh samostatné Windows aplikace (viz dluhy)
docs/mmolio-pravni-texty.md  právní texty k té aplikaci
garmin/                   aplikace pro hodinky Garmin
```

## 4. Jak ověřit, že to žije

```bash
# aktuální hodnota
curl -s https://glykemie.VASE-JMENO.workers.dev/api/glucose

# cizí zápis musí být odmítnut (čekej 401)
curl -s -o /dev/null -w "%{http_code}\n" \
  -X POST https://glykemie.VASE-JMENO.workers.dev/api/v1/entries -d '[]'
```

Když `/api/glucose` vrátí **503**, znamená to, že ještě nedorazilo žádné měření –
typicky problém na straně telefonu (xDrip nenahrává, špatné URL nebo API_SECRET).

## 5. Jak se dělají změny

**Worker.** Vždycky nejdřív `npx wrangler dev --remote` a test proti živým
bindingům – běží to na Cloudflare, ale produkce se nedotkne. Teprve pak
`npx wrangler deploy`. Pro ladění je v pohodě dočasně přidat debug endpoint,
jen ho nesmíš zapomenout odstranit před nasazením.

**GNOME rozšíření.** Tohle je důležité: na Waylandu **nejde přenačíst kód
rozšíření za běhu**. Zkoušeli jsme `ReloadExtension` (v GNOME 50 deprecated
a odmítne to), cyklus disable/enable (načte starý kód z cache) i vnořenou
instanci Shellu (nefunguje). Jediná cesta je **odhlášení a přihlášení uživatele**.

Proto:
- změny v `extension.js` dávkuj a před odhlášením ověř syntax
  (`node --check` na kopii s příponou `.mjs`)
- co jde, dělej přes `config.json` – ten se načítá živě a uživatel tím může
  ladit pozici, velikosti i prahy bez odhlašování
- chyby po přihlášení najdeš rychleji takhle než v journalu:
  ```bash
  gdbus call --session --dest org.gnome.Shell --object-path /org/gnome/Shell \
    --method org.gnome.Shell.Extensions.GetExtensionErrors "glykemie@sejkora.local"
  ```

## 6. Pravidla, která v tomhle projektu platí

**Stará hodnota nikdy nesmí vypadat jako aktuální.** To je hlavní bezpečnostní
invariant. Proto se dávka měření kontroluje proti uloženému času
(`storeIfNewer()`), proto se barví podle stáří a proto `/api/glucose` radši
vrátí chybu, než aby mlčky servíroval nesmysl. V 8–9/2026 nám worker měsíc
nefungoval a nikdo si nevšiml, protože displej dál ukazoval poslední hodnotu.

**Ticho na lince není totéž co „je to v pořádku".** Platí i pro nové funkce.

**Tvary cizích API si ověřuj, nepiš je po paměti.** U xDripu jsme šli přímo do
zdrojáků (`NightscoutSyncManager.swift`, `BgReading+Nightscout.swift`), u Dexcomu
proti pydexcom. Když jsem psal z paměti, spletl jsem se (`.NET 8` místo 10,
`Windows 10` jako cílová platforma, formát `Date()` u Dexcomu).

**Komunikace je česky.**

## 7. Otevřené úkoly

1. **Hlídání výpadku – nejvyšší priorita.** Momentálně je to jediné slabé místo:
   když se telefon vybije nebo xDrip přestane nahrávat, worker o tom neví.
   Domluvený plán: Cron Trigger ve Workeru (každých ~15 min) zkontroluje stáří
   `ns_latest` a při překročení prahu pošle push přes **ntfy.sh** (HTTP POST,
   bez registrace; uživatel si v appce přidá náhodně pojmenované téma).
   Uživatel to schválil, jen se k tomu ještě nedošlo.
2. **Graf posledních hodin.** Teď se ukládá jen poslední měření. Data už chodí
   sama, takže stačí v KV držet krátkou historii. Pozor na limit zápisů do KV.
3. **Mmolio** – samostatná aplikace pro Windows. Návrh hotový, implementace ne.
   Viz dluhy níž.

## 8. Známé dluhy a nedodělky

~~**Projekt není git repozitář.**~~ Vyřešeno 28. 9. 2026: worker i rozšíření jsou
součástí repa `sejkoramartin/Mmolio`, `node_modules` a `.wrangler` jsou v `.gitignore`.

**`mmolio-navrh.md` v projektu je zastaralý.** Uživatel si nechal návrh
přepracovat a poslal podstatně důkladnější verzi (589 řádků proti 260),
ale **do projektu se nikdy nenahrála**. Ta novější mění zásadní věci: cílem je
jen Windows 11, .NET 10 LTS místo 8, a hlavně **z první veřejné verze vypadly
klinické alarmy** kvůli evropskému MDR. Než se na Mmoliu začne dělat, je
potřeba tohle srovnat – aktuální je ta nahraná verze, ne soubor v projektu.

**V lokálním úložišti Secrets Store leží testovací tajemství**
`NIGHTSCOUT_API_SECRET` s hodnotou `test-secret-12345`. Je jen lokální (bez
`--remote`), do produkce se nedostalo, slouží k testům přes `wrangler dev`.

**V paměti projektu** (`~/.claude/projects/.../memory/`) jsou uložená rozhodnutí
k Mmoliu – varianta A3, chování alarmů a právní rámec.

## 9. Co se stalo předtím (zkráceně)

Projekt třikrát spadl kvůli závislosti na neveřejných API výrobců:

- **8/2026** – `wrangler deploy` odstranil Secrets Store bindingy, které byly
  jen v dashboardu. Měsíc si toho nikdo nevšiml, protože worker jel z tokenu
  v KV. Rozbilo se to až po změně hesla.
- **9/2026** – Abbott začal přesměrovávat na regionální server i z
  `/llu/connections`, nejen z loginu.
- **9/2026** – přechod na Dexcom Share, o dva týdny později přechod na xDrip.

Odtud plyne současná architektura: **push místo dotazování**, žádná cizí hesla
u nás, žádné reverzní inženýrství. Tuhle vlastnost prosím neztrácej – pokud
někdy přibude další zdroj, měl by do workeru taky posílat, ne se ho ptát.
