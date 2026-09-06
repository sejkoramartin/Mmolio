# Stav projektu

Zapsáno 6. 9. 2026, kdy testování skončilo kvůli ztrátě přístupu k testovacímu iPhonu.
Slouží k tomu, aby se dalo navázat bez čtení celé historie.

Poslední nasazená verze: **0.7.0 (build 9)**, commit `2b7ab28`.

---

## Co je hotové a ověřené

### CGM dekodér — spolehlivý

Dekódování paketů z `669A9141` je ověřené proti EasyPatch:

| paket | dekódováno | EasyPatch | rozdíl |
|---|---|---|---|
| 11:44:13 | 16,43 mmol/L | 16,4 | −0,03 |
| 11:46:08 | 16,38 mmol/L | 16,4 | +0,02 |
| 11:48:09 | 16,48 mmol/L | 16,5 | +0,02 |

Odchylka je uvnitř zaokrouhlení EasyPatch na jedno desetinné místo.

Nezávislé strukturální potvrzení: reading counter roste přesně o 1 za cyklus, historické
sloty fungují jako posuvný registr (první slot = current předchozího paketu), a counter
implikuje stáří senzoru odpovídající skutečnosti.

Ty čtyři reálné pakety jsou v `MedProbeTests/MedtrumPacketDecoderTests.swift` jako testovací
vektory — je to jediná ground truth v projektu.

**Marker naší varianty je `0x06`**, zatímco xDrip reference dokumentuje `0x02`. Obojí je
přijímáno, cokoli jiného se odmítá (commit `e632f2d`).

### Protokol 669A9120 a 669A9101

Sémantika převzatá z AndroidAPS Medtrum driveru a ověřená dvěma nezávislými způsoby
(commit `0f2e25c`):

- proti testovacím vektorům z `NotificationPacketTest.kt` toho projektu, byte za bytem
- fyzikálně: mezi dvěma zachycenými rámci vzrostl podaný bolus přesně o tolik, o kolik
  klesl rezervoár (2,7 U) — což vyjde jen při správných offsetech

Framing na `669A9101` je potvrzený AAPS CRC-8: **16 ze 16** zachycených rámců prošlo.

### Infrastruktura

- build a testy na GitHub Actions bez lokálního Macu (`.github/workflows/ios-build.yml`)
- signed TestFlight distribuce (`.github/workflows/testflight.yml`), postup v README
- 87 unit testů
- dva CI guardy: žádná BLE write cesta, žádné commitnuté signing artefakty

### Bezpečnost

**Zero pump command writes** po celou dobu, ověřováno CI na každém commitu. Jediná
write-like operace je `setNotifyValue`, tedy standardní GATT subscription.

---

## Hlavní otevřená otázka

**Z `669A9141` dostáváme zhruba 8 % čtení.**

Napočítáno podle counteru napříč záznamy z 5. 9. 2026:

```
counter 5405 → 5534 = 129 cyklů (4,3 hodiny)
senzor vygeneroval : 130 čtení
zachyceno          : 10
úspěšnost          : 7,7 %
```

Data přicházejí jen v oknech, kdy je první bajt CGM pole v `669A9120` roven `0x03`.
Okno trvá kolem pěti minut a vejdou se do něj právě dva CGM cykly. Mezi okny bylo
naměřeno 128, 58 a 70 minut.

Pozorováno pětkrát nezávisle, včetně jednoho negativního případu: v běhu 6. 9. se stav
za 1 hodinu 38 minut nikdy nedostal na `0x03` a nepřišel ani jeden paket.

### Proč to nejspíš není chyba v našem kódu

- délky oken jsou **konzistentní** (vždy dva pakety), zaseknutý GATT by dával náhodné délky
- heartbeat na `669A9120` běžel dál na tomtéž peripheral objektu i deset minut po posledním
  CGM paketu — callback path, delegate i subscription byly prokazatelně živé
- audit vyloučil vícenásobné instance manageru: vzniká jednou jako `let` na `AppDelegate`,
  `CBCentralManager` za `guard centralManager == nil`, ContentView drží vše jako
  `@ObservedObject`, takže překreslení view nemůže nic zkonstruovat znovu

### Nejsilnější hypotéza

Odlišná firmware varianta. xDrip na hardwaru s markerem `0x02` hlásí kontinuální příjem
každé dvě minuty (PR #718 toho projektu, ověřeno na 9+ párovaných vzorcích). Naše varianta
má marker `0x06` a kalibrační faktor 1037, zatímco xDrip dokumentuje 8932 a 10333 — řádově
jinde. Veřejný zdroj mapující `0x06` na konkrétní firmware se najít nepodařilo.

Alternativa, kterou data nerozliší: pumpa nebo EasyPatch pouští druhého klienta jen v oknech.

---

## Nedokončený test

Dvouhodinový diagnostický běh měl změřit, kolik oken se otevře a co jim předchází na
`669A9101`. Proběhl 6. 9., ale ten den došel inzulin a **vyměnila se patch pumpa** — senzor
nebyl navázaný, kalibrační faktor 1037 z dat úplně zmizel a stav se držel na `0x01`/`0x02`.
Test tedy odpověď nedal a je potřeba ho zopakovat s navázaným senzorem.

---

## Kudy dál

1. **Zopakovat dvouhodinový diagnostický běh** s navázaným senzorem. Otázky: kolik oken,
   jak dlouhá, a jestli jim něco na `669A9101` předchází.

2. **Ověřit `28 41` zprávy na 669A9101.** V záznamu z 13:49:32 nesla taková zpráva kompletní
   CGM paket — raw hodnota z ní byla přesně první historický slot následujícího 9141 paketu
   a celá historie posunutá o jeden cyklus. Jeden vzorek, ale strukturálně přesvědčivý.
   Pokud takové zprávy chodí pravidelně, je to použitelný druhý zdroj glykemie.

3. **Zneplatnit uložený peripheral identifier po výměně pumpy.** Nová pumpa má nové BLE UUID,
   ale `medtrum.peripheralIdentifier` v UserDefaults zůstává od staré a sám se nezneplatní.
   Fallback na `retrieveConnectedPeripherals` zafungoval, takže to zatím neškodí — ale je to
   slabé místo.

4. **Ukládat peripheral UUID do capture souboru.** Z CSV dnes nelze ověřit, ke které pumpě
   jsme byli připojeni. Po výměně patche to chybělo.

5. **Ověřit přežití na pozadí.** `bluetooth-central` a state restoration jsou nastavené, ale
   nikdy se neprokázalo, že se aplikace po ukončení systémem vrátí. Jednou byla nalezena
   ukončená po ~38 minutách ticha.

---

## Poznámky k nástrojům

**Listening mode** (0.7.0, commit `2b7ab28`) přepíná, k čemu se aplikace přihlašuje:

- `xDrip parity` — pouze `669A9141`, jako upstream. Záměrně slepý: bez `669A9120` nelze
  odlišit ticho způsobené naší chybou od pumpy, která nevysílá.
- `production` — `669A9141` + `669A9120` (výchozí)
- `diagnostic` — navíc `669A9101`, jediný režim, který vidí fragmentovaný stream

**Capture** se zapisuje průběžně do `Documents/medprobe-capture.jsonl`, řádek po řádku, a je
dostupný i z Files.app. Export do CSV má sloupce `timestamp,characteristic,length,hex`
s milisekundami. Ručně označené hodnoty z EasyPatch jsou ve stejném souboru pod
`EASYPATCH_MMOL_L` a aplikace je nikdy nečte zpět.

**Watchdog** recykluje spojení po sedmi minutách bez platného CGM paketu, ale jen když stav
dovoluje vysílání — mimo okno by reconnect nic nespravil a jen by zatěžoval spojení sdílené
s EasyPatch (commit `f763e80`).

---

## Reference

- `JohanDegraeve/xdripswift` — `CGMMedtrumTouchCareNanoTransmitter.swift`, PR #718,
  commit `06da42cf` (background recovery: watchdog 7 min, backoff 5/10/15 s)
- `nightscout/AndroidAPS` — `pump/medtrum/`, zejména `NotificationPacket.kt`,
  `ReadDataPacket.kt`, `CrcUtil.kt` a jejich unit testy
- `Artificial-Pancreas/MedtrumKit` — pouze BLE lifecycle principy, nic z pump-control vrstvy

Pole, které AndroidAPS nazývá `MASK_UNUSED_CGM`, ten projekt vědomě nedekóduje. U nás se
mění jen jeho první bajt a s glykemií nekoreluje — jako zdroj glukózy je to slepá ulička,
ale právě ten bajt je zatím jediný předvídatel provozu na `669A9141`.
