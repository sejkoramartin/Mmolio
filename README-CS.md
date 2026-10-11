# Mmolio

[English](README.md) · **Čeština**

**Instalace do hodinek:** [česky](docs/GARMIN-INSTALL-CS.md) · [English](docs/GARMIN-INSTALL.md).

Glykemie z kontinuálního senzoru tam, kam se běžně nedostane: na hodinkách Garmin, na
starém telefonu jako displeji na stole a v liště Ubuntu.

> ⚠️ **Mmolio není zdravotnický prostředek.** Jen zobrazuje hodnoty, které naměřil váš
> senzor. Nerozhodujte podle něj o léčbě a nechte si zapnuté alarmy v oficiální aplikaci
> senzoru. Přečtěte si [upozornění](docs/DISCLAIMER-CS.md), je krátké.

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
| [`garmin/`](garmin/README-CS.md) | Tři aplikace pro Forerunner 165 a fēnix 7X Pro (včetně varianty bez Wi-Fi): **Mmolio Bridge** přijímá měření z telefonu i na pozadí, **Mmolio WatchFace** je ciferník, **Mmolio DataField** datové pole do aktivit |
| [`worker/`](worker/README-CS.md) | Cloudflare Worker, který se tváří jako Nightscout, přijímá měření a servíruje displej i `/api/glucose` |
| `gnome-extension/` | Rozšíření GNOME: hodnota v docku, barvy podle rozsahu a stáří, volitelné upozornění |
| [`docs/`](docs/INSTALL-CS.md) | Instalace, FAQ, právní upozornění |

Odesílatel do hodinek tady není. Je to fork xDrip4iOS
[`sejkoramartin/xdripswift`](https://github.com/sejkoramartin/xdripswift), větev
`feature/garmin-connectiq-upstream`, protože xDrip je samostatný projekt pod GPL a musí se
synchronizovat s upstreamem. Formát zpráv mezi telefonem a hodinkami je zapsaný
v [`garmin/wire-protocol.md`](garmin/wire-protocol.md).

## Instalace

Postup krok za krokem je v [`docs/INSTALL.md`](docs/INSTALL-CS.md): Cloudflare Worker,
displej na telefonu, rozšíření do GNOME a hodinky Garmin. Části jsou nezávislé, postavte
si jen to, co chcete. Když něco nefunguje, koukněte do [FAQ](docs/FAQ-CS.md).

Pro Garmin jsou dostupné [testovací instalační balíčky](https://github.com/sejkoramartin/Mmolio/releases)
s návody, licencí a upozorněním, bez zdrojových kódů, workeru a rozšíření GNOME.
Fyzické ověření aktuálního kandidáta na všech modelech stále čeká.
Zdrojový kód je dostupný samostatně; volitelné webové a desktopové části si provozuje každý sám.

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
