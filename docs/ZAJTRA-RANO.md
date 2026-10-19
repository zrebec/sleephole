# Zajtra ráno – pondelok 19. 10. 2026

Návod na celý deň po noci 18. → 19. 10. Píše ho Claude 18. 10. večer. **Claude ho číta ako úplne prvú vec
sedenia a ide presne v poradí krokov.** Pri každom kroku je napísané, kto ho robí: **Claude** alebo **ty**. Krok, ktorý
mení niečo v App Store Connect, v TestFlighte alebo v tvojom telefóne, robí Claude len s tvojím áno pri tom kroku.
Hotový krok Claude odškrtne (`- [x]`) až po dôkaze, nie vopred.

Stav večer 18. 10.: v telefóne je celý build 9 (kroky 9a–9o, Debug, od 18:20), všetko commitnuté (`3a2647b` kód
9j–9o, `584ead9` dokumenty); pushuješ ty. **Staré buildy 1–7 v TestFlighte si už ukončil (expire).** Build 7 je stále
„Waiting for Review“ u Apple.

Tvoj rozvrh: večierka 21:30, budíček 6:00, odpočinok okolo 12:30–13:30. **Počas noci a odpočinku Claude nič
neinštaluje.** Týždeň na zmeny máš do 22. 10. 2026.

---

## Krok 1 – Claude: agenda a záznam noci (len čítanie)

- [x] Začni odpoveď agendou z `AGENTS.md` (pravidlo „FIRST THING EVERY SESSION“).
- [x] Až keď je majiteľ hore a noc je potvrdená (nie skôr ako 6:00): stiahni úložisko z telefónu do
      `docs/device-logs/2026-10-19-rano/` (git-ignored):
      `xcrun devicectl device copy from --device <UDID z devicectl list devices> --domain-type appDataContainer
      --domain-identifier sk.zrebec.sleephole --source "Library/Application Support/default.store"` (aj `-wal`, `-shm`),
      s `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` a bez sandboxu. Nič v telefóne nemeň.
- [x] Skontroluj noc s kľúčom `2026-10-19` (`ZNIGHTRECORD`):
  - výsledok (`ZOUTCOMERAW`), potvrdenie budíka, pokojné hodiny;
  - **pravidlá 15s:** `ZLOCKSCREENTOLERANCE` = 15 a `ZACCIDENTALTOLERANCE` = 15 (prvá ostrá noc s 9i a 9j);
  - **B26:** po zazvonení budíka nie je v udalostiach `.usedLockScreen`;
  - návrat do appky je zapísaný pri `willEnterForeground` (9a);
  - v Štatistikách: noc má svetlomodrú čiaru spánku, bielu deliacu bodku pri zaspatí a začiatok v zelenej (9n + doplnok
    s bodkou, v telefóne od 18. 10. 18:54; doplnok ešte nie je commitnutý – commit len na jeho slovo).
  - *Výsledok 19. 10. 10:45:* hotová noc (budík 6:00:00, zatrasenie 6:00:27, bez pauzy), 15 / 15 ✓, B26 ✓ (po budíku
    žiadne `.usedLockScreen`), návrat 0,15s po rozpoznaní ✓, pokojné hodiny 7 z 8 (prvú pokazili dve použitia
    telefónu 21:37–21:38). Chyba žiadna. Graf si potvrdil („presne tak“) ✓.
- [x] Povedz mu po slovensky, čo noc ukázala. **Ak noc našla chybu:** oprava ide prvá, so svojím commitom (jeho slovo),
      až potom krok 2.

## Krok 2 – Claude: build 9 na nahratie

- [x] `project.yml`: `CURRENT_PROJECT_VERSION` z `"8"` na `"9"`, `xcodegen generate`.
- [x] Testy: `cd SleepCore && DEVELOPER_DIR=… swift test`, `tools/test_app.sh`, `python3 tools/i18n/keys.py` (0 / 0 / 0).
      *19. 10.: SleepCore 412 / 0, appka 534 / 0, i18n 760 kľúčov 0 / 0 / 0 (Sonnet worker, overené).*
      Známy test časovania `SyncEngineTests.theTriesStop…` pod záťažou padá falošne – ak padne len on, spusti
      `SyncEngineTests` samostatne.
- [x] Commit „build 9: CURRENT_PROJECT_VERSION 9“ – len s jeho áno (pravidlo: commit iba na jeho slovo).
      *19. 10.: tvoje áno; `2f8c5eb` (bodka v grafe), `3675e52` (build 9), commit dokumentov.*
- [x] Archív (Release), bez sandboxu:
      `xcodebuild -project SleepHole.xcodeproj -scheme SleepHole -configuration Release -destination 'generic/platform=iOS'
      -archivePath "$HOME/Library/Developer/Xcode/Archives/2026-10-19/SleepHole 1.0 (9).xcarchive" -allowProvisioningUpdates archive`
- [x] Kontrola archívu: verzia 1.0 (9); `strings -a` nenájde žiadny nedokumentovaný názov; v balíku nie je dokument
      plánov (`PREHLAD-PLANOV.md` len v Debug); privacy manifest je tam.
- [x] Súbor `ExportOptions.plist` vytvor v scratchpade sedenia s týmto obsahom:
      ```xml
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict>
        <key>method</key><string>app-store-connect</string>
        <key>destination</key><string>upload</string>
        <key>teamID</key><string>8V2VSXHQ86</string>
        <key>signingStyle</key><string>automatic</string>
        <key>manageAppVersionAndBuildNumber</key><false/>
        <key>uploadSymbols</key><true/>
      </dict></plist>
      ```
- [x] **Ty:** nahratie spustíš sám (Claudovi ho kontrola sedenia nedovolí): Claude ti dá presný príkaz
      `xcodebuild -exportArchive -archivePath "…/SleepHole 1.0 (9).xcarchive" -exportOptionsPlist <scratchpad>/ExportOptions.plist
      -exportPath <scratchpad>/export-9 -allowProvisioningUpdates` a ty ho spustíš s `!` na začiatku. **Len raz** – pri
      builde 8 bežal omylom dvakrát. Čakáme na „Upload succeeded“ a „EXPORT SUCCEEDED“. Ak by sa objavilo okno kľúčenky
      (codesign chce kľúč Apple Distribution), potvrď „Povoliť“.

## Krok 3 – testeri (keď Apple build 9 spracuje, zvyčajne 10–30 min)

*19. 10.: „Upload succeeded“ (tvoje nahratie). Claude v App Store Connect (len čítanie): 1.0 (9) „Testing“, v skupinách
Kamaráti aj SE, „What to Test“ anglicky – presne text nižšie (1 536 znakov). Slovenčina chýba: TestFlight má zatiaľ len
anglickú lokalizáciu „Test Information“ – slovenská sa dá pridať (tvoje áno).*
*13:15: slovenčinu si pridal sám (popis bety + „What to Test“); Claude overil: 1.0 (9) má Slovak, 1 487 znakov = text nižšie.*

- [x] **Ty alebo Claude s tvojím áno:** App Store Connect → TestFlight → 1.0 (9) → pridať do skupín **Kamaráti** aj
      **SE**, odpovedať na otázku o šifrovaní ako pri builde 8, vložiť „What to Test“ (texty nižšie).
- [x] **Ty:** osobná správa trom kamarátom (text nižšie). *16:30: tvoje „DONE“.*

## Krok 4 – návod pre Apple na čistom telefóne, potom výmena buildu na kontrole

- [ ] **Druhý tester** (telefón, na ktorom SleepHole nikdy nebol) nainštaluje build 9 z TestFlightu a prejde
      `docs/REVIEW-NOTES.md` („celá noc za 15 minút“). *Druhý tester = tvoja manželka; návod s ňou prejdeš ty, slovenskú kópiu
      netreba (tvoje slovo 19. 10.).*
- [ ] Až potom **ty** (alebo Claude s tvojím áno pri každom kroku): build 7 stiahnuť z kontroly, pripojiť build 9 a vložiť
      do App Review Information → Notes text z `docs/REVIEW-NOTES.md` (súbor a pole musia byť rovnaké), znova podať
      s ručným vydaním. Pred podaním Claude zopakuje celú agendu (tvoja požiadavka zo 16. 10.).

## Krok 5 – ty, cez deň: test preinštalovania (B35) ✓

**Kedy:** cez deň, po nahratí buildu 9. Nie počas odpočinku a **nie po 18:30** (od 3 hodín pred večierkou platí
zmena rozvrhu až od zajtra a test by sa skreslil). Nesmie bežať noc ani odpočinok.

*Príprava*
1. Napíš Claudovi „idem na test“. Claude overí, že nič nebeží, a stiahne celé úložisko do Macu.
   *19. 10. 16:35 ✓: nič nebeží (posledná noc uzavretá 6:00), rozvrh 21:30 / 6:00, prísny režim zapnutý, Zdravie
   zapnuté, týždeň na zmeny od 16. 10. (do 22. 10.); úložisko je v Macu. Na telefóne je build z Macu z 18. 10. 18:54 –
   presne ten Claude po zmazaní nainštaluje.*
2. V appke: **Nastavenia → Záloha → Exportovať zálohu** → Uložiť do Súborov → **iCloud Drive**. (Automatická
   záloha v „Na mojom iPhone“ sa so zmazaním appky stratí.)
3. Otvor appku a minútu počkaj, nech iCloud dobehne. V Nastaveniach → Rozvrh má byť „🔧 Týždeň na zmeny … (do 22. 10. 2026)“.

*Test*

4. Nastavenia iPhonu → tvoje meno → iCloud → iCloud Drive → zoznam apiek → **SleepHole vypnúť** (presný názov sa
   podľa verzie iOS trochu líši).
5. Zmaž appku: podrž ikonu → Odstrániť apku → Vymazať apku.
6. Napíš Claudovi; nainštaluje ju z Macu (`xcrun devicectl device install app …`, rovnaký build).
7. Otvor appku – musí sa ukázať úvodný sprievodca. Na strane „Tvoj rozvrh“ nastav **22:15 a 6:45**, dokonči
   sprievodcu, potvrď povolenia (upozornenia, budík, Zdravie).
8. Zapni **SleepHole späť v iCloud Drive**, otvor appku a asi minútu počkaj.
9. Nastavenia → Rozvrh:
   - ✅ **správne:** mesto a noci sú späť, rozvrh **21:30 / 6:00**, týždeň na zmeny **do 22. 10. 2026**;
   - ❌ **chyba:** ostalo 22:15 / 6:45, alebo týždeň na zmeny končí neskôr (napr. 26. 10.).
10. Napíš Claudovi; stiahne úložisko a porovná. Ak niečo nesedí: **Nastavenia → Záloha → Obnoviť zo zálohy…**
    zo súboru v iCloud Drive; potom skontrolujete prísny režim (má byť zapnutý), zvuk budíka, Zdravie a upozornenia.

**✓ Uzavreté 19. 10. ~16:55 (tvoje slovo: „nič toto už opakovať nebudeme“).** Dvakrát: prepínač SleepHole v iCloud Drive
vypnutý → appka zmazaná → Claude ju nainštaloval z Macu (ten istý build). **Sprievodca sa ani raz neukázal** – appka hneď
načítala iCloud a vrátila všetko: mesto aj jeho názov, dnešnú stavbu, 20 nocí a 18 odpočinkov, rozvrh 21:30 / 6:00, týždeň
na zmeny do 22. 10., prísny režim, Zdravie, žolíka a mince (Claude porovnal úložisko pred a po). Nevrátilo sa len 7
vývojárskych skúšobných nocí – tie sa do iCloudu neposielajú. Pri prvom pokuse sa iOS podľa teba pýtal aj na iCloud
(dal si „Povoliť“), pri druhom nie. **Bežná cesta je teda overená, prípad B35 (sprievodca a až potom iCloud) sa na tvojom
telefóne vyvolať nedal** – len vypnutím celého iCloud Drive alebo odhlásením, a to nerobíme. Oprava B35 stojí na testoch;
sprievodcu na čistom telefóne uvidí manželka (krok 4).
*Tvoje vysvetlenie (~17:10): po zmazaní appka zo zoznamu Nastavenia → tvoje meno → iCloud → Uložené v iCloude → Zobraziť
všetko úplne zmizne a po novej inštalácii je iCloud pre ňu znova zapnutý bez otázky – preinštalovanie samo vráti voľbu na
„zapnuté“. Apple to slovami nikde nepíše, ale jeho dokumenty s tým súhlasia (zdroje v pláne §12). Nič sa nemení.*
*~17:15 si to doskúšal sám: náš prepínač „Synchronizovať cez iCloud“ nechá prepínač iPhonu zapnutý; s vypnutým prepínačom
iPhonu appka napíše „iCloud nie je dostupný“ ✓; po preinštalovaní z Xcode (teraz 1.0 (9)) sa po ~2 s všetko vrátilo a
prepínač iPhonu sa zapol sám. Claude overil úložisko: 21:30 / 6:00, týždeň do 22. 10., prísny režim – dnešná noc je v poriadku.*

## Krok 6 – ty: departures.to (kategórie Health + Audio namiesto Health + AI)

**Departures nemá účty ani prihlásenie** – preto tam žiadny login nevidíš. Zápis sa pridáva cez e-mail: „Post“ →
e-mailová adresa → príde e-mail s bezpečným odkazom → formulár. Tvoj zápis: https://departures.to/apps/23674
(SleepHole, kategórie ♥️ Health, 🧠 AI).

1. Pozri e-mail, ktorý ti departures poslali pri pridaní (hľadaj „departures“). Ak je v ňom odkaz na úpravu zápisu,
   kategórie zmeň tam.
2. Ak nie: departures.to → **Post** → zadaj **tú istú adresu** ako vtedy → v e-maile zvoľ cestu pre vývojára a pozri,
   či ponúka úpravu existujúcej appky.
3. Ak ani to nie, napíš im na **team@departures.to** (adresa z ich stránky Privacy Policy):

   > Subject: SleepHole (apps/23674) – please change a category
   >
   > Hi, I listed my TestFlight app SleepHole (https://departures.to/apps/23674) and picked the wrong category by
   > mistake. Could you please change "AI" to "Audio"? The app has no AI; it plays sleep sounds and rings an alarm.
   > Health stays. Thank you! – <tvoje meno>

Claude môže v tvojom Chrome otvoriť stránky a ukázať, kde čo je. E-mail a formuláre s tvojou adresou vyplníš ty.

---

## „What to Test“ pre build 9

TestFlight → 1.0 (9) → Test Details. Ak má Test Information slovenskú lokalizáciu, vlož aj slovenský text, inak
anglický. Limit je 4 000 znakov (oba texty sú kratšie).

### English

```
Build 9 – the candidate for version 1.0.

NEW
• A first-run guide: the cat walks you through nine short pages. Settings → All rules lists every rule with its real numbers.
• Setup time of 5, 10 or 15 minutes (Settings).
• Leaving the app at night: you now have 15 seconds to come back (was 10).
• Statistics: the chart shows every night – when you started, fell asleep and got up.
• Bedtime and wake-up can also be set in the guide (the change-week rules apply).

TRY A WHOLE NIGHT IN ABOUT 15 MINUTES
1. More than 3 hours before your bedtime, open Settings → Schedule, set Bedtime about 3 minutes from now and Wake-up about 20 minutes from now, and tap Save (the first change opens a 7-day change week – set your real times again right after the test; Settings says whether they apply tonight or from tomorrow). On a fresh install set the times on the guide's page "Your schedule" instead.
2. Tap "Go to sleep". The first 5 minutes are setup time; then lock the phone. SleepHole has to stay the open app – the screen can be off.
3. When the alarm rings, shake the phone or type the code from Settings → Morning confirmation. The building appears in your town.

HOW TO SEND FEEDBACK
Take a screenshot in SleepHole, tap the preview and choose "Share Beta Feedback". Or open the TestFlight app → SleepHole → "Send Beta Feedback". One sentence helps.

THREE QUESTIONS
1. Did the guide make clear what to do tonight?
2. Did the alarm ring, and could you confirm that you got up?
3. Will you start a building again tomorrow? Why, or why not?
```

### Slovensky

```
Build 9 – kandidát na verziu 1.0.

NOVÉ
• Úvodný sprievodca: mačka ťa prevedie deviatimi krátkymi stranami. Nastavenia → Všetky pravidlá ukážu každé pravidlo so skutočnými číslami.
• Čas na prípravu 5, 10 alebo 15 minút (Nastavenia).
• Odchod z appky v noci: na návrat máš teraz 15 sekúnd (predtým 10).
• Štatistiky: graf ukazuje každú noc – kedy si začal, zaspal a vstal.
• Večierku a budík nastavíš aj v sprievodcovi (platia pravidlá týždňa na zmeny).

VYSKÚŠAJ CELÚ NOC ZA ASI 15 MINÚT
1. Viac ako 3 hodiny pred svojou večierkou otvor Nastavenia → Rozvrh, nastav večierku asi o 3 minúty a budík asi o 20 minút a ťukni na Uložiť (prvá zmena otvorí 7-dňový týždeň na zmeny – hneď po teste si nastav svoje skutočné časy; Nastavenia ukážu, či platia dnes alebo od zajtra). Pri novej inštalácii nastav časy radšej v sprievodcovi na strane „Tvoj rozvrh“.
2. Ťukni na „Ísť spať“. Prvých 5 minút je čas na prípravu, potom zamkni telefón. SleepHole musí ostať otvorená appka – displej môže byť zhasnutý.
3. Keď zazvoní budík, zatras telefónom alebo zadaj kód z Nastavenia → Ranné potvrdenie. Budova pribudne v tvojom meste.

AKO POSLAŤ SPÄTNÚ VÄZBU
Urob v SleepHole snímku obrazovky, ťukni na náhľad a zvoľ „Poslať spätnú väzbu (beta)“. Alebo otvor appku TestFlight → SleepHole → „Poslať spätnú väzbu“. Stačí jedna veta.

TRI OTÁZKY
1. Pochopil si zo sprievodcu, čo máš večer robiť?
2. Zazvonil budík a podarilo sa ti potvrdiť, že si vstal?
3. Začneš zajtra znova stavbu? Prečo áno, prečo nie?
```

Názvy v textoch (Rozvrh, Ranné potvrdenie, Ísť spať, Všetky pravidlá, Čas na prípravu, Uložiť, Tvoj rozvrh) sú overené
v String Catalog 18. 10. večer. Zmena rozvrhu viac ako 3 h pred večierkou platí hneď. Či skutočné časy nastavené hneď
po teste platia ešte v ten večer, Claude neoveril – preto text odkazuje na Nastavenia (ukážu „platí od zajtra“, ak áno).
Ak chceš, Claude to ráno overí testom pred vložením textu.

---

## Osobná správa trom kamarátom

Pošli ju každému zvlášť (WhatsApp, Messenger, SMS – kde sa bežne píšete):

```
Ahoj! Dnes vyšiel nový build SleepHole (1.0 (9)) – kandidát na App Store. Mám k tebe malú prosbu:
vyskúšaj ho prosím 3 noci (stačí do nedele) a potom mi odpovedz na 3 otázky:
1. Pochopil(a) si zo sprievodcu, čo máš večer robiť?
2. Zazvonil budík a podarilo sa ti potvrdiť, že si vstal(a)?
3. Začneš aj ďalší večer stavbu? Prečo áno / prečo nie?
Aktualizácia: appka TestFlight → SleepHole → Aktualizovať. Ak chceš vidieť celú noc hneď, v „What to Test“
je postup na 15 minút. Ďakujem, veľmi mi to pomôže! 🌙
```

---

## Necommitnuté z večera 18. 10. – stav 19. 10.

- **Deliaca bodka v grafe** (doplnok 9n: biela/čierna bodka pri zaspatí, svetlejšia azúrová čiara spánku, legenda
  „Prišiel spánok“) – `SleepHole/UI/StatsView.swift`, `SleepHoleTests/ViewsTests.swift`; v telefóne od 18:54; testy
  534 / 534. **Commitnuté 19. 10. na tvoje áno (`2f8c5eb`).**
- **Dokumenty:** tento súbor, pokyn v `AGENTS.md`, zápisy v `docs/IMPLEMENTATION_PLAN.md` – commitnuté 19. 10.
- **`tools/audio/make_train.py`** – prototyp zvuku vlaku (pozri nižšie). **Ostáva necommitnutý (tvoje slovo 19. 10.).**

## Nočný vlak – prototyp zvuku (nie do appky, len na počúvanie)

**Odložené 19. 10. (tvoje slovo): teraz to nie je priorita.** Stránka ostáva, ako je, k výberu klapotu sa vrátime
na tvoje slovo.


- Stránka s prehrávačom: https://claude.ai/artifact/UYXN2wvYWdLPnLgLpMrZsY – 20 minút (verzia B) + porovnanie klapotu
  **A drevo / B oceľ s dlhým doznievaním / C oceľ s krátkym „tk“** (30 s, 13:50–14:20). Kópia 20 minút v iCloude
  `SleepHole/Nocny-vlak-prototyp.m4a`.
- **Čaká na tvoje ucho:** ktorý klapot (A / B / C, prípadne s poznámkou) – Claude potom vyrobí celých 20 minút s ním a
  doladí, čo napíšeš (píšťala, státie, pohupovanie, most).
- Generátor: `tools/audio/make_train.py` (deterministický, seed 20261018; `HIT_MODEL=v1|v2|v2b python3 make_train.py`
  v pracovnom priečinku; `--analyze` vypíše ťažisko spektra a doznievanie). Zvukové súbory boli v dočasnom priečinku
  sedenia 18. 10. a po vyčistení kontextu tam už nebudú – vyrobia sa znova skriptom. Kódovanie: MP3 pre stránku
  (`ffmpeg -codec:a libmp3lame -b:a 80k`, stránky m4a neprehrávajú), m4a pre iCloud (`afconvert -f m4af -d aac -b 80000`).
- Do appky až po 1.0 a na tvoje slovo (plán §0b „Later“).

## Čo ostáva otvorené (na tvoje slovo)

- **Voľné noci** (tvoje želanie): voľná noc, alebo druhý rozvrh na piatok a sobotu? Claude odporúča druhý rozvrh, build 10.
- **Pre testerov neskôr** (zmrazenie rozsahu do 1.0): krátka testovacia noc hneď pre nového človeka; jemná karta po
  prvej hotovej noci s prosbou o jednu vetu e-mailom.
- Graf vo svetlom motíve: tenká modrá a indigová sa líšia hlavne hrúbkou – ak ti to bude prekážať, upravíme.
