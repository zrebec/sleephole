# SleepHole – plán

> Pracovný názov podľa adresára. Natívna iOS appka v duchu SleepTown: večer začneš stavať budovu a keď v noci necháš telefón na pokoji a ráno vstaneš načas, budova je hotová. Z jednotlivých nocí postupne rastie mesto.
>
> **Cieľ:** pravidelný čas zaspávania aj vstávania. Pomôcť má hra, ktorá motivuje, ale netrestá kruto.
>
> Stav: návrh schválený (2026-09-28). Assety hotové (2026-09-29). **Implementačný plán (EN, pre agentov):
> [`docs/IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md)**, ten má pri detailoch prednosť.

---

## 1. Rešerš (zhrnutie)

### SleepTown
- Vývojár je Seekrtech (Forest). Posledná verzia 3.4.1 vyšla v októbri 2023, odvtedy žiadny vývoj.
- Ako funguje: nastavíš si večierku a budíček a pred večierkou spustíš stavbu. Keď telefón v noci použiješ, budova sa zrúti. Ráno musíš do ~10 minút od budíčka zatriasť telefónom, inak sa tiež zrúti.
- **Kľúčové zistenie:** SleepTown ani Forest telefón neblokujú. Iba zistia, že si z appky odišiel. Na to netreba žiadne špeciálne oprávnenie, takže naše jadro funguje aj bez plateného účtu.

### Čo dovoľuje iOS (a za akú cenu)

| Schopnosť | Personal Team (zadarmo) | Developer Program ($99/rok) |
|---|---|---|
| Detekcia upozadenia appky, lokálne notifikácie, SwiftData | ✅ | ✅ |
| Background Audio (appka ostane v noci nažive, hrá ambient, zvoní budík) | ✅ | ✅ |
| Screen Time API (blokovanie appiek) | ❌ | ✅, **nepoužijeme** (rozhodnutie) |
| HealthKit (spánok z Apple Watch) | ❌ | ✅ |
| AlarmKit (systémový budík, iOS 26) | ❌ | ✅ + treba požiadať Apple o entitlement |
| Platnosť sideloadu | **7 dní**, potom znova „Run“ z Xcode (dáta ostanú) | 1 rok / TestFlight |

### Grafika
- [Kenney Isometric Tiles – Buildings / City / Vehicles / Landscape](https://kenney.nl/assets/isometric-tiles-buildings): 2D PNG, CC0, po 128 dlaždíc. (Nakoniec nepoužité, pozri ďalší bod.)
- [Kenney City Kit – Suburban / Commercial / Industrial / Roads](https://kenney.nl/assets/city-kit-commercial): 3D low-poly GLB/FBX/OBJ, CC0. **Použité:** vyrenderované vlastným SceneKit skriptom (bez Blendera) do jednotného izometrického štýlu, pozri `tools/render/`.
- Neskôr vlastný procedurálny generátor budov v Blenderi (Python `bpy`, headless render). Voliteľne [Blender MCP](https://github.com/ahujasid/blender-mcp).

---

## 2. Rozhodnutia (od vlastníka, 2026-09-28)

| # | Otázka | Rozhodnutie |
|---|---|---|
| D1 | Platforma | **Iba iPhone**, natívne Swift/SwiftUI. Android nie. PWA nie (neodlíši zamknutie od odchodu, nemá spoľahlivý budík). |
| D2 | Developer Program | **Neskôr.** Fáza zadarmo musí najprv dokázať, že appku reálne používaš. Potom HealthKit a AlarmKit. |
| D3 | Prísnosť | **Iba detekcia.** Nič sa neblokuje. Zamknutie je OK, odchod do akejkoľvek appky sa počíta. Screen Time API sa nepoužije. |
| D4 | Zlyhanie | **Stupňované**, pozri §4. |
| D5 | Štýl | **Klasické mesto, low-poly izometria.** |
| D6 | Pred spaním | **Iba pripomienka** večierky (notifikácia). |
| D7 | Ráno | **Vlastný budík + potvrdenie vstania** v rannom okne. |
| D8 | Rozvrh | **Pevný, rovnaký každý deň.** |
| D9 | Hodinky | Má **Apple Watch**. Využijeme až s plateným účtom (HealthKit). |
| D10 | Assety | **Najprv Kenney CC0, vlastné neskôr** (Blender). Hotové: 3D Kenney City Kity vyrenderované cez SceneKit do 174 izometrických spritov (`assets/sprites`), zvuky v `assets/audio`. |
| D11 | Motivácia | **Odomykanie budov + štatistiky a série + živé mesto.** Ručné ukladanie budov na mapu nie, umiestňujú sa automaticky. |
| D12 | Postup | **Po fázach s checkpointmi.** Každú fázu otestuješ na iPhone a až potom ideme ďalej. Commity robíš ty. |
| D13 | Levely budov | **L1** obyčajné budovy (domy, bytovky) · **L2** parky, osvetlené ulice, múzeá, knižnice · **L3** radnica, škola, hasiči, polícia, nemocnica · **L4** mrakodrapy. Stavebné noci 1–5 iba L1, 6–15 L1+L2, 16–30 L1–L3, od 31. noci všetko. Každú noc jedna náhodná budova (najprv sa náhodne vyberie level, potom budova). |
| D14 | Jazyk | UI po slovensky, kód a dokumentácia pre agentov po anglicky. |

---

## 3. Ako funguje jedna noc

```
  večierka −30 min        večierka                          budíček        budíček +15 min
        │                     │                                  │                 │
  🔔 „Čas sa chystať“   [Začať stavbu] ── telefón zamknutý ──── ⏰ zvoní ── [Vstal som] ─► výsledok
                              │         (ambient audio drží                          │
                              │          appku nažive)                               ▼
                              └──── odchod do inej appky → meria sa čas mimo  → budova v meste
```

1. **Pripomienka:** lokálna notifikácia 30 minút pred večierkou. Počet a časovanie sa dajú nastaviť.
2. **Štart:** tlačidlo „Začať stavbu“. Vyberie sa budova (náhodne z odomknutých, prípadne si vyberieš). Spustí sa tichý ambient (dážď, ticho…) cez `AVAudioSession(.playback)`, aby appka ostala nažive.
3. **Noc:** telefón zamkneš a položíš.
   - Zamknutie = OK.
   - Upozadenie appky bez zamknutia = začne sa merať **čas mimo**. Po 10 sekundách príde notifikácia „Tvoja budova na teba čaká 🏗️“.
   - Stiahnutie Control Center / Notification Center (iba `willResignActive` bez prechodu na pozadie) sa **nepočíta**.
4. **Budík:** o budíčku appka (vďaka audio session beží) prehrá budík **aj v tichom režime**. Záloha: lokálna notifikácia so zvukom pre prípad, že iOS appku v noci ukončil.
5. **Ranné potvrdenie:** tlačidlo alebo zatrasenie „Vstal som“ v okne budíček + 15 min.
6. **Výsledok:** vyhodnotenie podľa §4, animácia dokončenia a budova pribudne do mesta.

### Technické jadro: zamknutie verzus odchod z appky
iOS nemá oficiálne API „používateľ zamkol telefón“. Riešenie:
- **Primárne:** `UIApplication.protectedDataWillBecomeUnavailableNotification` príde pri zamknutí ešte **pred** `didEnterBackground`. Vyžaduje nastavený kód telefónu (bežne ho máš).
- **Záloha a kontrola:** `UIApplication.shared.isProtectedDataAvailable` v momente prechodu na pozadie.
- Po odomknutí sa vrátiš rovno do našej appky, lebo bola v popredí. Ak odídeš inam, dostaneme `didEnterBackground` bez predchádzajúceho zamknutia a začneme merať.
- Časy sa ukladajú ako časové značky do SwiftData, takže aj keď iOS appku v noci ukončí, výsledok sa dá dopočítať pri ďalšom spustení.
- **Nejasný prípad** (appku ukončil iOS počas zamknutia, telefón sa vybil): v súlade s „never cruel“ sa počíta **v prospech hráča**.

> ⚠️ Toto je jediné technické riziko projektu, preto ho overíme ako **prvý spike vo fáze F2** na reálnom iPhone.

---

## 4. Vyhodnotenie noci – pravidlá R2 (upravené vlastníkom 2026-09-29)

| Pravidlo | Hodnota |
|---|---|
| Začať stavbu | **iba od večierka −10 min do večierka +5 min**, inak vynechaná noc |
| Príprava | po štarte **5 min** môže byť appka v pozadí (podcast, rozprávka), potom sa musíš vrátiť |
| Noc | displej môže byť vypnutý, ale appka musí byť v popredí; **akékoľvek upozadenie stavbu zrúti** (ako SleepTown) – po upozornení máš 10 s na návrat (zistenie trvá ~3 s) |
| Výnimky | telefonát (vynútený systémom) sa nepočíta; ak appku ukončí iOS, je to v tvoj prospech |
| Ukončiť stavbu | najskôr **30 min pred budíkom**, zatrasením alebo zadaním **kódu** (je v Nastaveniach) |
| Budík | zvoní **najviac 2 minúty** |
| Hotová | potvrdené **počas zvonenia budíka** (2 min) |
| Rozostavaná | potvrdené po dozvonení budíka, najneskôr do 60 min |
| Ruina | stavba sa zrútila, zrušená noc, alebo nepotvrdené do hodiny po budíčku |

- **Séria (streak)** = počet po sebe idúcich nocí s výsledkom Hotová. Rozostavaná ju nezvýši, ale ani nepreruší.
- Ruiny sa nikdy nemažú. Po 7 dňoch zarastú kvetmi.
- Po zrútení noc pokračuje a budík ráno zazvoní, pretože aj vstávanie je súčasť návyku.

## 5. Progres a motivácia

- **Odomykanie budov:** podľa D13, teda podľa počtu stavebných nocí (hotová alebo nedokončená): 1–5 → L1, 6–15 → L1–L2, 16–30 → L1–L3, od 31. noci → L1–L4.
- **Štatistiky:** kalendár nocí (farba podľa výsledku), aktuálna a najdlhšia séria, priemerný čas štartu a vstania, **pravidelnosť** (rozptyl času štartu v minútach, hlavná metrika návyku) a graf za 30 dní.
- **Živé mesto:** deň a noc podľa reálneho času (v noci svietia okná), autíčka na cestách (Kenney Vehicles), chodci. Populácia rastie s počtom budov.
- **Umiestňovanie:** automatické. Mesto rastie od stredu po špirále okolo námestia a cesty sa dopĺňajú samé.

---

## 6. Architektúra

```
sleephole/
├── SleepHole.xcodeproj
├── SleepCore/               # Swift Package – čistá logika, žiadny UIKit/SpriteKit
│   ├── Schedule.swift       # pevná večierka/budíček, okná
│   ├── NightSession.swift   # stavový automat noci (idle → building → alarm → done)
│   ├── SleepRules.swift     # prahy + vyhodnotenie (§4)
│   ├── Progression.swift    # séria, odomykanie
│   ├── TownLayout.swift     # špirálové umiestňovanie na izometrickú mriežku
│   └── Tests/               # Swift Testing – väčšina testov je tu
├── SleepHole/               # App target
│   ├── App/                 # SwiftUI obrazovky (Dnes, Mesto, Štatistiky, Nastavenia)
│   ├── Night/               # LifecycleMonitor (lock vs. background), AudioKeeper, Alarm
│   ├── Town/                # SpriteKit scéna (SpriteView), izometrický renderer
│   ├── Persistence/         # SwiftData modely + JSON export/import (záloha)
│   └── Resources/Assets/    # Kenney sprity
└── docs/PLAN.md
```

- **Stack:** Swift 6, SwiftUI, SpriteKit (cez `SpriteView`), SwiftData, UserNotifications, AVFoundation. Cieľ je iOS 26. SceneKit nie (Apple ho odkladá) a RealityKit je na 2D izometriu zbytočne ťažký.
- **Assety cez kontrakt:** každá budova = `BuildingSprite { id, footprint (1×1 / 2×2), anchor, image, tier }`. Kenney PNG sa neskôr vymenia za vlastné rendery z Blendera bez zmeny kódu.
- **Rast počas stavby bez extra assetov:** budova sa odhaľuje zdola nahor cez `SKCropNode` a navrchu je lešenie. Kenney teda netreba kresliť po fázach.
- **Testy:** celá logika noci a pravidiel je čistá a testovateľná bez zariadenia. Čas je injektovaný (`Clock`), takže sa dá simulovať celá noc v teste.
- **Záloha dát:** export a import JSON zo Súborov, pre istotu kvôli 7-dňovému re-signu.

---

## 7. Fázy (každá končí checkpointom na tvojom iPhone)

> Aktuálne a podrobné fázy (F0–F7 + hotová fáza A = assety) sú v `IMPLEMENTATION_PLAN.md` §0 a §10.
> Tabuľka nižšie je pôvodný prehľad.

| Fáza | Obsah | Checkpoint |
|---|---|---|
| **F0 – Príprava** | Nainštalovať **Xcode** (App Store), prihlásiť Apple ID (Personal Team), na iPhone zapnúť Developer Mode. Hello-world appka na telefóne. Stiahnuť Kenney balíky. | appka beží na iPhone |
| **F1 – SleepCore** | Schedule, NightSession (stavový automat), SleepRules, Progression + testy | `swift test` zelené |
| **F2 – Noc bez grafiky** | **Spike: lock vs. odchod.** Nastavenie rozvrhu, pripomienka, Začať stavbu, AudioKeeper, budík + záložná notifikácia, ranné potvrdenie, textová obrazovka výsledku. Denník udalostí na ladenie. | **2–3 reálne noci**, overené, že detekcia sedí |
| **F3 – Mesto** | SpriteKit izometrická scéna, Kenney sprity, automatické umiestnenie, rast cez crop a lešenie, stavy hotová/nedokončená/ruiny | mesto z doterajších nocí |
| **F4 – Progres a štatistiky** | Odomykanie úrovní, séria, kalendár, pravidelnosť, graf, JSON záloha | týždeň používania |
| **F5 – Živé mesto** | Deň a noc, svietiace okná, autíčka, chodci, populácia | „chcem sa naň pozerať“ |
| **F6 – Platený účet** *(keď sa rozhodneš)* | Developer Program, HealthKit (spánok z Apple Watch ako bonus alebo overenie), AlarmKit (žiadosť o entitlement), TestFlight a koniec 7-dňového re-signu | appka vydrží, budík je systémový |
| **F7 – Vlastné assety** | Blender pipeline: Kenney City Kit 3D → vlastný jednotný render → vlastný procedurálny generátor budov | nový vizuál bez zmeny kódu |

Voliteľne neskôr: Apple Watch appka (budík vibráciou na zápästí), widget so sériou, Live Activity počas noci.

---

## 8. Otvorené, drobné (doladíme za pochodu)
- Konkrétna večierka a budíček. Nastavíš ich v appke, v kóde nebudú natvrdo.
- Prahy v §4 sa doladia po prvých nociach.
- Názov appky (SleepHole je pracovný).
- Jazyk UI: predpoklad **slovenčina**.
- Zvuk budíka a ambientu: CC0 zvuky (napr. Kenney/Freesound CC0) alebo vlastné.

## 9. Riziká
| Riziko | Dopad | Opatrenie |
|---|---|---|
| Detekcia zamknutia sa na niektorom iOS správa inak | jadro hry | spike hneď v F2, denník udalostí, pravidlo „v prospech hráča“ |
| iOS appku v noci ukončí napriek audio | budík nezazvoní | záložná notifikácia so zvukom, telefón na nabíjačke; v F6 AlarmKit |
| 7-dňová expirácia (zadarmo) | otravné, appka ráno nenaštartuje | pripomienka v appke „o 2 dni expiruje“, JSON záloha; F6 to rieši úplne |
| Budík v tichom režime zlyhá | zaspíš | v F2 otestovať s prepínačom ticha; do overenia mať aj systémový budík |
| App Store (ak by išla von) | – | nie je cieľ. Keby áno: background audio musí byť reálne využité (ambient ho je), AlarmKit namiesto hacku |

## Zdroje
- [SleepTown – App Store](https://apps.apple.com/us/app/sleeptown/id1210251567), [AppBrain (verzia 3.4.1, 10/2023)](https://www.appbrain.com/app/sleeptown/seekrtech.sleep), [recenzia Luxia Le](https://luxiale.com/2025/09/17/sleeptown-full-review/)
- [Family Controls nefunguje s Personal Team](https://hsb.horse/en/blog/personal-team-family-controls-limitation/), [Apple – Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement)
- [HealthKit nie je dostupný pre Personal Team](https://github.com/Blueturboguy07/nut-ai/pull/2)
- [AlarmKit v iOS 26 – MacRumors](https://www.macrumors.com/2025/06/11/ios-26-third-party-alarm-apps/), [AlarmKit entitlement – Apple Forums](https://developer.apple.com/forums/thread/797950)
- [Kenney Isometric Buildings](https://kenney.nl/assets/isometric-tiles-buildings), [Kenney City Kit Commercial](https://kenney.nl/assets/city-kit-commercial), [City Kit Suburban](https://kenney.nl/assets/city-kit-suburban)
- [Blender MCP](https://github.com/ahujasid/blender-mcp)
