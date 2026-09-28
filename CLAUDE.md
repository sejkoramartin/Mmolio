# Mmolio – kontext pro práci na projektu

Struktura a odkazy jsou v `README.md`. Tenhle soubor je o tom, jak se v projektu pracuje.
Pro worker a GNOME rozšíření platí navíc `worker/CLAUDE.md`, pro hodinky `garmin/README.md`.

## Co kde běží

- **Hodinky Forerunner 165**: Mmolio Bridge, WatchFace a DataField. Nahrávají se přes USB
  jako `.prg` do `GARMIN/Apps`. Application ID a formát zpráv se **nemění** – telefon na ně
  posílá a přenos je ověřený.
- **Telefon**: xDrip4iOS z forku `sejkoramartin/xdripswift`, větev `feature/garmin-watch`.
  Do tohoto repa nepatří a upravuje se jen tam.
- **Cloudflare**: Worker `glykemie`, KV `TOKEN_KV`, Secrets Store s `NIGHTSCOUT_API_SECRET`.
- **Ubuntu**: rozšíření `glykemie@sejkora.local` je symlink do `gnome-extension/`.

## Pravidla

1. **Stará hodnota nikdy nesmí vypadat jako aktuální.** Stáří se počítá z času měření,
   nikdy z času doručení. Ticho na lince není totéž co „je to v pořádku".
2. **Tvary cizích API se ověřují ve zdrojích**, ne po paměti. U Garmin SDK je lokální
   dokumentace v `~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0/doc`, u xDripu zdrojáky
   forku.
3. **Hesla, tokeny a klíče nikdy do repa ani do chatu.** Podpisový klíč pro Garmin leží
   mimo repo (`~/Stažené/MedProbe-garmin/developer_key.der`), Cloudflare tajemství
   v Secrets Store. Interaktivní příkazy, které se ptají na tajné hodnoty, patří uživateli.
4. **Bindingy Cloudflare patří do konfiguráku**, ne do dashboardu; `deploy` smaže
   všechno, co v něm nenajde. V repu je vzor `worker/wrangler.toml` s placeholdery,
   skutečná ID jsou v `worker/wrangler.local.toml` mimo git: `deploy -c wrangler.local.toml`.
   Stejně tak `gnome-extension/.../config.json` je osobní a mimo git, v repu je
   `config.example.json`.
5. **Změny se ověřují lokálně, ne v CI.** GitHub Actions se šetří.
6. **Repo je veřejné pod GPL-3.0.** Do repa nepatří adresa workeru, ID účtu ani nic
   osobního – všude jen příklady. Veřejná dokumentace je česky v `docs/`.
7. **Komunikace je česky.**

## Jak se dělají změny

**Garmin.** Sestavení a testy lokálně, SDK je připnuté na 9.2.0:

```bash
export CONNECTIQ_SDK="$HOME/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-9.2.0"
export DEVELOPER_KEY="$HOME/Stažené/MedProbe-garmin/developer_key.der"
./garmin/scripts/build-fr165.sh          # release všech tří aplikací
./garmin/scripts/build-fr165.sh --test   # build s Monkey C testy
.github/scripts/garmin-checks.sh         # strukturální kontroly, běží i v CI
```

Simulátor potřebuje knihovny, které nejsou v systému; běží přes Xvfb s `LD_LIBRARY_PATH`
na rozbalené závislosti. Po změně ověř, že se `.prg` nezměnilo tam, kde se změnit nemělo
(porovnání SHA-256 proti předchozímu buildu).

**Worker.** Nejdřív `npx wrangler dev --remote` proti živým bindingům, teprve pak
`npx wrangler deploy`. Podrobně v `worker/README.md`.

**GNOME rozšíření.** `config.json` se načítá za běhu, `extension.js` vyžaduje odhlášení
a přihlášení uživatele – Wayland neumí rozšíření přenačíst.

## Otevřené úkoly

1. **Hlídání výpadku workeru** – Cron Trigger + push přes ntfy.sh. Nejvyšší priorita,
   protože dnes výpadek telefonu nikdo nepozná.
2. **Graf posledních hodin** z krátké historie v KV.
3. **Mmolio pro Windows** – `docs/mmolio-navrh.md` je zastaralý, aktuální je novější verze
   (jen Windows 11, .NET 10 LTS, bez klinických alarmů kvůli MDR). Před začátkem srovnat.

## Prostředí

Uživatel (Martin) je diabetik a automechanik. Senzor Dexcom G7, léčbu řeší CamAPS FX,
té se nedotýkáme. xDrip4iOS běží souběžně a je zdrojem dat pro hodinky i pro worker.
