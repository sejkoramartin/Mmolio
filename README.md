# Mmolio

Glykemie z kontinuálního senzoru tam, kam se běžně nedostane: na hodinkách Garmin, na
starém telefonu jako displeji na stole a v liště Ubuntu.

> ⚠️ **Mmolio není zdravotnický prostředek.** Jen zobrazuje hodnoty, které naměřil váš
> senzor. Nerozhodujte podle něj o léčbě a nechte si zapnuté alarmy v oficiální aplikaci
> senzoru. Přečtěte si [upozornění](docs/DISCLAIMER.md), je krátké.

```
Dexcom G7 ──BLE──► xDrip4iOS (iPhone) ──┬──► Connect IQ ──► Garmin FR165
                                        │                   Bridge + ciferník + datové pole
                                        └──► HTTPS ──► Cloudflare Worker ──┬──► telefon jako displej
                                                                           └──► rozšíření do GNOME
```

Mmolio si data nikde nebere samo, nechává si je posílat. Neptá se žádné cizí služby,
nepotřebuje vaše heslo k senzoru a nikam nic neodesílá.

## Co je uvnitř

| Složka | Co to je |
|---|---|
| [`garmin/`](garmin/README.md) | Tři aplikace pro Forerunner 165: **Mmolio Bridge** přijímá měření z telefonu i na pozadí, **Mmolio WatchFace** je ciferník, **Mmolio DataField** datové pole do aktivit |
| [`worker/`](worker/README.md) | Cloudflare Worker, který se tváří jako Nightscout, přijímá měření a servíruje displej i `/api/glucose` |
| `gnome-extension/` | Rozšíření GNOME: hodnota v docku, barvy podle rozsahu a stáří, volitelné upozornění |
| [`docs/`](docs/INSTALL.md) | Instalace, FAQ, právní upozornění |

Odesílatel do hodinek tady není. Je to fork xDrip4iOS
[`sejkoramartin/xdripswift`](https://github.com/sejkoramartin/xdripswift), větev
`feature/garmin-watch`, protože xDrip je samostatný projekt pod GPL a musí se
synchronizovat s upstreamem. Formát zpráv mezi telefonem a hodinkami je zapsaný
v [`garmin/wire-protocol.md`](garmin/wire-protocol.md).

## Instalace

Postup krok za krokem je v [`docs/INSTALL.md`](docs/INSTALL.md): Cloudflare Worker,
displej na telefonu, rozšíření do GNOME a hodinky Garmin. Části jsou nezávislé, postavte
si jen to, co chcete. Když něco nefunguje, koukněte do [FAQ](docs/FAQ.md).

Zveřejňuje se zdrojový kód, ne hotové balíčky. Každý si Mmolio sestaví a provozuje sám
pro sebe, na svém účtu a se svým vývojářským klíčem.

## Pravidlo, které platí všude

**Stará hodnota se nikdy netváří jako aktuální.** Stáří se počítá od okamžiku měření,
nikdy od chvíle, kdy hodnota dorazila. Hodinky starou hodnotu zešediví, označí `STALE`
a schovají trendovou šipku. Worker raději vrátí chybu, než aby mlčky poslal zastaralý
údaj.

Vzniklo to z konkrétní zkušenosti: worker tu jednou měsíc nefungoval a nikdo si toho
nevšiml, protože displej dál ukazoval poslední známé číslo.

## Licence

[GNU GPL v3](LICENSE). Software je poskytován bez jakékoli záruky.

Dexcom, FreeStyle Libre, Garmin, Connect IQ a Cloudflare jsou ochranné známky svých
vlastníků a používají se tu jen popisně. Mmolio není žádnou z těchto firem vyvíjené,
podporované ani schválené.
