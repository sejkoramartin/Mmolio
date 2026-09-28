# Upozornění

**Mmolio není zdravotnický prostředek.**

Mmolio je doplňkový displej. Jen zobrazuje hodnoty, které naměřil váš senzor a které mu
pošle aplikace na telefonu. Nic neměří, nic nevyhodnocuje a k ničemu se nevyjadřuje.

## O léčbě podle Mmolia nerozhodujte

Dávkování inzulinu, jídlo a posouzení vašeho stavu vždy řešte podle **oficiální aplikace
svého senzoru a podle glukometru**, nikdy podle Mmolia.

## Alarmy si nechte v oficiální aplikaci

Alarmy oficiální aplikace senzoru jsou vaše hlavní pojistka a mají zůstat zapnuté.
Upozornění v Mmoliu jsou pouze doplňková. Mohou se opozdit nebo nezaznít vůbec, například
když vypadne internet, vybije se telefon, počítač usne nebo hodinky ztratí spojení.

Watch-app, ciferník ani datové pole na hodinkách žádné alarmy nemají a mít nebudou.
Upozornění umí jen rozšíření do GNOME a jde vypnout.

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

Zveřejňuje se **zdrojový kód**, ne hotové instalační balíčky. Kdo chce Mmolio používat,
sestaví si ho sám pro sebe a pro sebe si ho i provozuje. Nejde o uvedení výrobku na trh.

## Ochranné známky

Dexcom, FreeStyle Libre, Garmin, Connect IQ, Cloudflare a další názvy patří svým
vlastníkům. V Mmoliu se používají **jen popisně**, aby bylo zřejmé, s čím projekt
spolupracuje. Mmolio není žádnou z těchto firem vyvíjené, podporované ani schválené.

## Vaše data

Mmolio neposílá vaše hodnoty nikomu dalšímu. Tečou z vašeho telefonu do vašeho vlastního
workeru na vašem účtu u Cloudflare a do vašich hodinek. Nikdo jiný k nim nemá přístup,
pokud mu adresu vašeho workeru nedáte.

**Adresa workeru je veřejně čitelná.** Kdo ji zná, může si přečíst vaši poslední hodnotu.
Zacházejte s ní jako s citlivým údajem: nedávejte ji do screenshotů, do issue na GitHubu
ani nikam, kde ji uvidí cizí lidé.
