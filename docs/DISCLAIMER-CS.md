# Upozornění

[English](DISCLAIMER.md) · **Čeština**

**Mmolio není zdravotnický prostředek.**

Mmolio je doplňkový displej. Jen zobrazuje hodnoty, které naměřil váš senzor a které mu
pošle aplikace na telefonu. Nic neměří, nic nevyhodnocuje a k ničemu se nevyjadřuje.

## O léčbě podle Mmolia nerozhodujte

Dávkování inzulinu, jídlo a posouzení vašeho stavu vždy řešte podle **oficiální aplikace
svého senzoru a podle glukometru**, nikdy podle Mmolia.

## Alarmy si nechte v oficiální aplikaci

Alarmy oficiální aplikace senzoru mají zůstat zapnuté. Mmolio je doplňkový displej
a tyto alarmy nenahrazuje.

Watch-app, ciferník ani datové pole na hodinkách žádné alarmy nemají a mít nebudou.

## Hodnota může být stará, chybná, nebo nemusí dorazit

Data putují přes několik zařízení a přes internet. Cestou se mohou zdržet nebo ztratit.

Proto v Mmoliu platí pravidlo, které nikdy neporušujeme: **stará hodnota se nikdy netváří
jako aktuální.** Všude se počítá stáří od okamžiku měření, hodinky starou hodnotu zešediví
a označí `STALE`, a worker raději vrátí chybu, než aby mlčky poslal zastaralý údaj.
Prázdné nebo šedé místo znamená „nevím“, ne „je to v pořádku“.

## Bez záruky

Mmolio je otevřený software poskytovaný zdarma a **bez jakékoli záruky**, včetně záruky
prodejnosti a vhodnosti pro určitý účel. Používáte jej na vlastní riziko. Autor
neodpovídá za škody vzniklé jeho použitím. Podrobnosti jsou v [licenci](../LICENSE).

## Co se zveřejňuje

Zdrojový kód zůstává veřejný pod GPL-3.0. Pro Garmin jsou dostupné verzované
testovací instalační balíčky s návodem, licencí a uvedeným stavem ověření. Ostatní části projektu si uživatel sestavuje a provozuje sám.

## Ochranné známky

Dexcom, FreeStyle Libre, Garmin, Connect IQ, Cloudflare a další názvy patří svým
vlastníkům. V Mmoliu se používají **jen popisně**, aby bylo zřejmé, s čím projekt
spolupracuje. Mmolio není žádnou z těchto firem vyvíjené, podporované ani schválené.

## Vaše data

Mmolio neposílá vaše hodnoty nikomu dalšímu. Tečou z vašeho telefonu do vašeho vlastního
workeru na vašem účtu u Cloudflare a do vašich hodinek. Znalost adresy workeru umožňuje číst poslední hodnotu;
neveřejná adresa sama o sobě není řízení přístupu.

**Adresa workeru je veřejně čitelná.** Kdo ji zná, může si přečíst vaši poslední hodnotu.
Zacházejte s ní jako s citlivým údajem: nedávejte ji do screenshotů, do issue na GitHubu
ani nikam, kde ji uvidí cizí lidé.
