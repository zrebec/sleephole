# SleepHole 🌙🏗️

Osobná iPhone appka na **pravidelný spánok**, v duchu hry SleepTown. Večer začneš stavať budovu, v noci necháš telefón na pokoji a ráno vstaneš s budíkom. Z každej noci pribudne do mesta jedna budova: hotová, rozostavaná alebo ruina. Mesto tak rastie noc po noci. Tón je milý a nikdy krutý 💙

<p align="center">
  <img src="docs/previews/app-guide.png" width="240" alt="Sprievodca">
  <img src="docs/previews/app-night.png" width="240" alt="Stavba počas noci">
  <img src="docs/previews/app-town.png" width="240" alt="Mesto">
</p>

> Natívna appka vo Swifte (SwiftUI, SpriteKit, SwiftData) len pre iPhone. **Nič neblokuje**, appka iba rozpozná, či si z nej v noci odišiel.

---

## Ako funguje noc

| | Pravidlo |
|---|---|
| 🔔 **Pripomienka** | notifikácia pred večierkou (predvolene 30 min) |
| 🏗️ **Začať stavbu** | iba od **večierka − 10 min** do **večierka + 5 min**, inak je noc vynechaná |
| 🎧 **Príprava** | po štarte máš **5 minút** v inej appke (podcast, rozprávka), potom sa vráť do SleepHole |
| 📱 **Noc** | displej môže byť vypnutý, ale SleepHole musí ostať v popredí. Pri odchode príde **„⚠️ Vráť sa!“** a máš **10 s** na návrat, inak sa stavba zrúti |
| 📞 **Výnimky** | telefonát sa nepočíta. Ak appku v noci vypne iOS, počíta sa to v tvoj prospech |
| ⏰ **Budík** | zvoní najviac **2 minúty** (aj v tichom režime) a rozsvieti obrazovku. Vstanie potvrdíš **zatrasením** alebo **kódom** (najskôr 30 min pred budíčkom) |
| 🏢 **Hotová** | potvrdené počas zvonenia budíka |
| 🚧 **Rozostavaná** | potvrdené po dozvonení, najneskôr do 60 min. Ďalšia dobrá noc ju dostavia |
| 🧱 **Ruina** | stavba sa zrútila, noc bola zrušená, alebo si vstanie nepotvrdil. Po týždni zarastie kvetmi 🌸 |

**Levely** podľa počtu stavebných nocí (hotová alebo rozostavaná):

| Noci | Odomknuté | Budovy |
|---|---|---|
| 1–5 | L1 | rodinné domy, bytovky |
| 6–15 | L1–L2 | + parky, osvetlené ulice, múzeá, knižnice |
| 16–30 | L1–L3 | + radnica, škola, hasiči, polícia, nemocnica |
| 31+ | L1–L4 | + mrakodrapy |

Každú noc sa náhodne vyberie jeden z odomknutých levelov a z neho budova. Budovy, ktoré v meste ešte nemáš, majú prednosť. Posledné 3 budovy sa nikdy nezopakujú.

---

## Čo už existuje

- **Noc od začiatku do konca:** štartové okno, 5-minútová príprava, rozpoznanie zamknutia a odchodu z appky, varovanie „Vráť sa“, tolerancia na telefonát, budík, potvrdenie zatrasením alebo kódom, výsledok so zvukom.
- **Obrazovka noci:** nočná obloha s blikajúcimi hviezdami, budova rastúca odspodu na stavenisku, animovaný vežový žeriav a „dýchajúci“ nápis *Stavba prebieha*.
- **Mesto (SpriteKit):** izometrická mapa bez hraníc, ktorá rastie od stredu po blokoch 4×4 a sama si dopĺňa cesty. Posúvanie so zotrvačnosťou a zoom dvoma prstami ako v SimCity. Ťuknutím na budovu zistíš, z ktorej noci je a v akom je stave. V hlavičke je počet budov a obyvateľov.
- **190 izometrických spritov:** z Kenney 3D City Kitov (CC0) vlastným SceneKit rendererom. Budovy L1–L4 so slovenskými tabuľami, cesty, lešenie, ruiny, autá a 16-snímkový žeriav.
- **8 budíkov:**
  - jemný pizzicato (predvolený),
  - Ranná nálada (Grieg),
  - Óda na radosť (hracia skrinka),
  - Zvonkohra,
  - Retro,
  - Budíček (trúbka),
  - Digitálny,
  - Poplach (agresívny).

  Jemné budíky postupne silnejú, agresívne hrajú naplno hneď.
- **🔥 Séria** hotových nocí za sebou.
- **Sprievodca pri prvom spustení** (6 stránok). Čísla v ňom sa berú priamo z pravidiel v kóde. Pred prvou nocou sa ukáže aj kontrolný zoznam „Tvoja prvá noc“. Oboje sa zapíše do databázy.
- **Nastavenia:** večierka, budíček, pripomienka, ranný kód, zvuk v noci a budík s ukážkou, stav povolenia upozornení.
- **Vývojárske nástroje:**
  - rýchla noc (4 min) a testovacia noc (15 min),
  - jednorazové započítanie testovacej noci do mesta,
  - nočný denník,
  - test detekcie,
  - spúšťacie parametre pre agentov.

**Dáta:** noci a stav sprievodcu sú v SwiftData (SQLite) v priečinku appky, nastavenia v UserDefaults. Mesto sa neukladá, pri každom otvorení sa poskladá z uložených nocí.

---

## Projekt

```
SleepCore/        Swift balík: pravidlá noci, rozvrh, levely, výber budovy, rozloženie mesta, projekcia (bez UI)
SleepHole/        iOS appka: SwiftUI obrazovky, AppModel, SpriteKit mesto, zvuk, detekcia, notifikácie
SleepHoleTests/   testy appky (hostované, Swift Testing)
assets/sprites/   190 PNG spritov + catalog.json      assets/audio/  budíky a zvuky (CAF)
tools/render/     Kenney OBJ → izometrické sprity (SceneKit), náhľady, rozloženie mesta
tools/audio/      syntéza budíkov (numpy)
docs/             PLAN.md (rozhodnutia, SK) · IMPLEMENTATION_PLAN.md (pre agentov, EN) · RUN_ON_IPHONE.md
project.yml       XcodeGen (.xcodeproj sa generuje, nie je v gite)
```

### Spustenie

```bash
brew install xcodegen
xcodegen generate && open SleepHole.xcodeproj     # potom ▶ Run na iPhone (návod: docs/RUN_ON_IPHONE.md)
```

### Testy

```bash
tools/coverage.sh     # SleepCore: 67 testov, ~96 % riadkov
tools/test_app.sh     # appka na simulátore iPhone 16 Pro: 47 testov, ~89 % riadkov
```

Ďalšie nástroje:
- `tools/sim_shot.sh`: screenshot zo simulátora (napr. `-seedNights 60 -openTab town`), simulátor po sebe vždy vypne.
- `python3 tools/render/make_recipes.py` a `render_sprites.swift`: nové sprity.
- `python3 tools/audio/make_alarms.py`: nové budíky.

**Pre AI agentov:** začni v [`AGENTS.md`](AGENTS.md). Stav fáz a všetky zistenia sú v [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md).

---

## Stav

| Fáza | | Stav |
|---|---|---|
| A | assety (sprity, zvuky, pipeline) | ✅ |
| F0 | nástroje, appka na iPhone | ✅ |
| F1 | SleepCore a testy | ✅ |
| F2 | noc bez grafiky mesta | ✅ testy na zariadení, ⏳ prvá skutočná noc |
| F3 | mesto (SpriteKit) | ✅ postavené, ⏳ čaká na skutočné noci |
| F4 | levely, štatistiky, záloha | ⬜ |
| F5 | živé mesto | ⬜ |
| F6 | platený Apple účet | ⬜ na rade |
| F7 | nové budovy | ⬜ |

## Čo nás čaká

**Najbližšie**
- **Vyhodnotenie prvej skutočnej noci:** vydrží appka celú noc, zobudí budík?
- **Apple Developer Program (F6):**
  - appka nebude po 7 dňoch expirovať,
  - upozornenia *time-sensitive* prebijú Sústredenie,
  - **AlarmKit** (systémový budík, zazvoní aj po reštarte iOS),
  - neskôr HealthKit a Apple Watch (overenie spánku, budík vibráciou na zápästí),
  - TestFlight.

**F4: motivácia a prehľad**
- Oslava odomknutého levelu.
- Štatistiky: séria (najdlhšia aj aktuálna), kalendár nocí, priemerný čas štartu a vstania, **pravidelnosť**, graf za 30 dní.
- **Oprava ruiny:** dobrá noc môže ruinu znovu postaviť.
- Záloha a obnova do súboru (JSON). Pripomienka 7-dňovej expirácie (kým nie je platený účet).
- Možno celkový limit času mimo appky za noc (teraz sa tolerancia ráta pre každý odchod zvlášť).

**F5: živé mesto**
- Deň a noc podľa skutočného času, svietiace lampy a okná.
- Autíčka jazdiace po cestách, rastúci počet obyvateľov.

**F7: viac budov**
- Hlavne L3: pošta, kostol, hotel, štadión, železničná stanica, kino, kúpalisko.
- Viac variantov L2 a L4, neskôr vlastné modely z Blendera.

**Nápady (XS → XXL)**
| | |
|---|---|
| XS | zavibrovanie pri štarte stavby a pri zamknutí |
| S | úspechy („Prvá budova“, „7 nocí v rade“, „Prvý mrakodrap“), vlastný názov mesta |
| M | widget na ploche so sériou a odpočtom do večierky, týždenný „mestský denník“ |
| L | ročné obdobia: sneh a vianočné stromčeky v zime, jesenné farby |
| XL | Live Activity s rastúcou budovou na zamknutej obrazovke, appka pre Apple Watch |
| XXL | spoločné mesto s partnerom alebo kamarátmi (iCloud), vydanie v App Store |

---

## Licencie a poďakovanie

- **Grafika a časť zvukov:** [Kenney](https://kenney.nl) (CC0). Vyrenderované a poskladané vlastnými skriptmi v `tools/`.
- **Melódie budíkov:** E. Grieg (*Peer Gynt*, 1875) a L. van Beethoven (*9. symfónia*, 1824), obe voľné dielo. Trúbka a Poplach sú vlastné skladby. Všetko je syntetizované v `tools/audio/make_alarms.py`.
- **Inšpirácia:** [SleepTown](https://apps.apple.com/app/sleeptown/id1210251567) od Seekrtech.
