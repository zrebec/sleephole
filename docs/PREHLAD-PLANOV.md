# SleepHole – prehľad plánov a návrhov

Stav k 2026-10-14. Tento dokument je prehľad pre majiteľa: čo je rozrobené, čo je navrhnuté a čo je len
nápad – s odhadom náročnosti a s prioritou. Podrobný plán a zadania pre workerov sú v
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) (§10), nákresy k návrhom z 2026-10-10 v
[`NAVRH-MESTO-STATISTIKY.md`](NAVRH-MESTO-STATISTIKY.md).

## Rozsah je zmrazený (tvoje rozhodnutie 2026-10-12)

Do vydania verzie 1.0 v App Store sa nič nové nezačína. Otvorené položky sa zatvárajú po jednej v poradí:
Dnes → riziko u Applu → obyvatelia → slovenské texty pre všetkých → kalendár → stránka v obchode a snímky → dlžné
skúšky na telefóne. Nový nápad sa zapíše jedným riadkom a počká.

## Ako to čítať

**Náročnosť**

| Značka | Čo znamená |
|---|---|
| XS | drobnosť, do 15 minút |
| S | jeden krok jedného workera + kontrola |
| M | 2 – 4 kroky s kontrolnými bodmi (jedno až dve sedenia) |
| L | samostatná fáza na viac sedení |

**Priorita**

| Značka | Čo znamená |
|---|---|
| P0 | hneď – bráni testerom alebo je rozrobené |
| P1 | pred širším testovaním a pred App Store |
| P2 | robí appku bohatšou, nič na tom nestojí |
| P3 | neskôr, nápad, alebo čaká na tvoje rozhodnutie |
| ✅ | hotové – položka má v appke zelený štítok |

Priority sú **odporúčanie Opusu**. S prehľadom a s poradím si 2026-10-12 súhlasil; meniť ho môžeš kedykoľvek.

## Tabuľka

| # | Čo | Náročnosť | Priorita | Popis |
|---|---|---|---|---|
| 1 | **EARLY – „Dnes ísť spať skôr"** | S – M | P0 ✅ | **Hotovo 2026-10-12.** Noc sa dá začať až 3 h pred večierkou, bez postihu, príprava 15 min od štartu. Tvoja noc z 11. na 12. 10. to potvrdila na telefóne (skorší štart, budík, budova, mince). Texty prešli revíziou a šesť drobných úprav z kontroly je spravených a otestovaných. |
| 2 | **Build 1.0 (4) do TestFlightu** | XS | P0 ✅ | **Hotovo 2026-10-12.** Build 4 je nahraný do App Store Connect (08:41, „Upload succeeded"). Pridať ho do skupín testerov ostáva na tebe – vtedy dostane opravu aj testerka, ktorá problém nahlásila. |
| 3 | **TODAY – kompaktná obrazovka Dnes** | S – M | P1 ✅ | **Hotovo 2026-10-12.** Obe tlačidlá sú v jednej karte, mačka má 200 bodov, tlačidlá sú nižšie a dva popisy kratšie. Na telefóne si potvrdil, že je všetko nad spodnou lištou aj pri troch riadkoch textu. Hlavička s mestom a teplotou sa nerobila – netreba ju. |
| 4 | **POP – obyvatelia** | S | P1 | Build 7, krok 7b. Budovy úrovne 2 a 3 majú dnes 0 obyvateľov – vyzerá to ako chyba. Nové počty podľa druhu budovy, názvy veľkosti mesta, „Mesto v číslach". |
| 5 | **CAL – mesačný kalendár a obdobia** | M | P1 | Skutočný kalendár po mesiacoch a rokoch; priemery a graf za zobrazený mesiac. Dnes po 35 dňoch staršie noci nikde nevidno. |
| 6 | **CARE-2a – mince za pokojné hodiny (+10)** | S – M | P1 | Potvrdil si to 2026-10-09 a znova 14. 10. (+10 za pokojnú hodinu, +11 keď telefón len leží); postavené to nie je. Každá hodina noci s vypnutou obrazovkou +10 🪙. Hodiny sa počítajú od večierky, aby skorší štart nezarábal viac. |
| 7 | **App Store stránka – texty a zásady súkromia** | S | P1 | Texty sú v App Store Connect a sedia do písmena, stránka podpory a zásady súkromia sú zverejnené, vekové hodnotenie vyšlo 9+, súkromie je zverejnené ako „Data Not Collected". Vyhlásenie podľa DSA (nie som obchodník) a 175 krajín sú hotové. Novú licenčnú zmluvu Applu si prijal 14. 10. a build 6 je pripojený k verzii 1.0. Ostáva tvoje rozhodnutie o cene (zmluva o platených appkách nie je podpísaná). |
| 8 | **Riziko pri kontrole Applu** | S | P1 ✅ | **Hotovo 2026-10-12.** Rozbor je v `ROZBOR-APP-REVIEW.md` (dvanásť rizík, záložná cesta, kroky k podaniu). Rozhodol si: podať s tromi signálmi zámku a s priznaním v poznámkach, záložnú detekciu postaviť, kým Apple kontroluje. Čo z rozboru treba spraviť v kóde, je riadok 32. |
| 9 | **Dlžné skúšky na telefóne** | tvojich 20 – 30 min | P1 | 14. 10. potvrdené: zavretá appka a nevrátiť sa → zrútenie; poistný budík po skorom potvrdení. Ostáva: pauza (skús ju v rýchlej testovacej noci – mesta sa nedotkne) a test systémového budíka vo Vývojárovi. Dve zariadenia: zatiaľ nikto nehlási problém. Bez kódu. |
| 10 | **NIGHT – detail noci ako vlastná obrazovka** | M | P2 | Karty namiesto jedného bloku textu, potom časová os noci. Sám si povedal, že detail sa nedá čítať. |
| 11 | **ZOOM – kamera mesta (chyba B30)** | S | P2 | Veľké mesto sa nedá vidieť celé (od asi 45. noci). Oddialenie rastie s mestom, appka si pamätá pohľad, po novej budove sa naň kamera posunie. |
| 12 | **Štatistiky zo spánku** | S každá | P2 | **Jeden graf noci, nie viac grafov (tvoje slovo 12. 10.):** na dnešnej čiare každej noci štyri farby – zelená = kedy si šiel spať (ako dnes), modrá = kedy si zaspal (ako dnes), ružová = budíček, štvrtá = kedy si naozaj vstal (jej farbu ešte vyberieme). Všetko spojené v jednej línii, nech na prvý pohľad vidno, ako dlho si spal. Neskôr: najlepšie okno na spánok, pracovné dni proti víkendom. Tvoj smer „štatistiky, štatistiky, štatistiky". |
| 13 | **TALK – kamoš hovorí o meste** | M | P1 | Chceš to (14. 10.: „už mačka dáva zmysel"): mačka na Dnes hovorí o meste a o tom, čo si „hovoria obyvatelia". Texty píše Opus, ty ich prečítaš na obrazovke Texty. Build 7, krok 7d – po obyvateľoch. |
| 14 | **TOWN-W krok 3 – dážď a sneh v meste** | M | P2 | Častice nad mestom, ležiaci sneh, sivšia obloha. Počasie appka už pozná. |
| 15 | **TOWN-W krok 4 – deň a noc v meste** | M | P2 | Mesto podvečer oteplie a v noci stmavne; potom svetlá lámp a okien. |
| 16 | **CARE-3 – Live Activity / Dynamic Island** | S skúška, M funkcia | P2 | Odpočet noci na zamknutej obrazovke a v ostrovčeku. Skúška ukáže, či sa zobrazí aj nad Fotoaparátom. |
| 17 | **Upratovanie drobných chýb** | S | P2 | B12, B13, B14, B15 (sprievodca nespomína žolíky), B16, B22, B26 v jednom kroku; B8 (batéria) premerať zvlášť. |
| 18 | **SENSE – skúška pohybu celú noc** | S | P2 | Jedna noc s meraním pohybu proti jednej bez: koľko to stojí batérie. Od výsledku závisí „+11 keď sa telefón nepohol" (CARE-2b). |
| 19 | **Prístupnosť** | S – M | P2 | VoiceOver a väčšie písmo na hlavných obrazovkách. Nový návrh Opusu – appka je pre veľa ľudí. |
| 20 | **ISLAND – ostrov a voda** | M | P3 | Pobrežie kopíruje mesto, okolo voda. Pred krokom 4 alebo s ním. Čaká na tvoju odpoveď (voda všade alebo horizont). |
| 21 | **ECON E1 – Prísny režim ako záväzok** | S | P3 | Zapnúť zadarmo, vypnúť mimo voľných dní za 1 000 🪙. Čaká na tvoju odpoveď. |
| 22 | **ECON E2 – stavebný úrad** | M | P3 | Na čo sú mince: iný žreb za 25 🪙, výber budovy za jej cenu, zbierka druhov. |
| 23 | **ECON E3 – mestské služby** | L | P3 | Týždenný rozpočet na hasičov, políciu, nemocnicu… Opus navrhuje zásadu: budovu môže vziať len noc, nikdy mince. |
| 24 | **Počasie cez celú obrazovku Dnes** | M | P3 | Pozastavené. Najprv treba vedieť, čo znamená „ako stierač na aute". |
| 25 | **Apple Watch – štart noci z hodiniek** | S skúška, M funkcia | P3 | Najprv skúška, či to iOS vôbec dovolí s appkou otvorenou na telefóne. |
| 26 | **Po EARLY: posun večierky a skoršie ráno** | S | P3 | Po viacerých skorších nociach láskavo ponúknuť posun večierky; prípadne otvoriť ranné potvrdenie skôr. Počkať na skúsenosť testerov. |
| 27 | **F7 – viac budov úrovne 3** | M | P3 | Úroveň 3 má len 5 budov a mesto ich opakuje (pošta, kostol, hotel, stanica…). |
| 28 | **Robotický hlas hlásateľa** | S – M | P3 | Vlastný hlas v duchu hry M.A.X., vyrobený v telefóne. |
| 29 | **Téma Fantasy Town** | M – L | P3 | Druhá sada budov. Nie sú to len obrázky – každú budovu treba poskladať. |
| 30 | **B10 – odpočinok ukončiť skôr** | XS | P3 | Rozhodnutie: smie sa odpočinok potvrdiť v posledných asi 20 % času? |
| 31 | **Slovenské texty pre všetkých** | S – M | P1 | Tabuľku si schválil 14. 10. – build 7, krok 7c. Appka po slovensky oslovuje každého v mužskom rode („zaspal si", „vstal som", „postavil si"). Buď texty prepísať neutrálne, alebo pridať voľbu oslovenia. Nový návrh Opusu z revízie textov 2026-10-12. |
| 32 | **Zostavenie 5 pre kontrolu Applu** | S | P0 ✅ | **Hotovo 2026-10-12.** Nahraté do App Store Connect o 14:42 a nainštalované na tvoj telefón. Obsahuje kompaktné Dnes, odkaz na zásady súkromia v Nastavenia → O aplikácii, ostré zostavenie bez vývojárskych vecí (overené na nahratom archíve) a presnejší text povolenia pre systémový budík. 498 testov zelených. |
| 33 | **Záložná detekcia zamknutia** | M | P1 | Poistka z rozboru rizík: appka by rozlišovala „zamkol som" od „odišiel som" len zdokumentovanými signálmi. Stavia sa, kým Apple kontroluje; nasadí sa len vtedy, keď Apple tri dnešné signály odmietne. Stratila by sa pripomienka a siréna na zamknutej obrazovke. |
| 34 | **Snímky a podanie do App Store** | S | P1 | Anglické snímky zo simulátora (dve veľkosti), potom podanie s ručným vydaním – schválenie tak nič nezverejní. Pred podaním: skúška appky na iPade a recept „noc za 15 minút" na čistej inštalácii. |
| 35 | **Budova namiesto mačky na Dnes** | M | P3 | Nahradené riadkom 13 (14. 10.). Tvoj nápad z 2026-10-12: hrdinom obrazovky Dnes by bola posledná postavená budova, tiež s reakciou na ťuknutie. Zmrazené do vydania 1.0. |
| 36 | **Osvetlená ulica nie ako nočná stavba** | XS – S | P0 | Tvoja noc z 13. na 14. 10. postavila „Osvetlenú ulicu" – podľa teba vtip, nie budova ani park. Odsúhlasil si 14. 10.: vyradiť ju zo žrebu, každá noc postaví budovu alebo park; lampy pribudnú v uliciach samy neskôr (krok 4 – deň a noc v meste). Build 7, krok 7a – postavené a skontrolované 14. 10. večer (testy zelené), na tvojom telefóne od 17:18. |
| 37 | **Čínština** | M | P3 | Jediná spätná väzba z TestFlightu (anonym, 13. 10.). Neodporúčam teraz: asi 655 textov + stránka v obchode a snímky, nikto na kontrolu tónu, a pevninská Čína aj tak vyžaduje registráciu ICP. |
| 38 | **Obrazovka Texty (Vývojár)** | S | P1 | Tvoje želanie z 14. 10.: v Nastavenia → Vývojár vedľa „Plány a návrhy" všetky texty appky, anglicky a slovensky, každý v samostatnom boxe, s hľadaním. Čítaš ich svojím tempom a povieš, čo je zlé. Build 7, krok 7c. |
| – | Povolené appky počas noci | – | neodporúčam | Vyžaduje Screen Time API – to je proti pevnému pravidlu projektu. |

## Popis po skupinách

### P0 – hotovo ✅

**1 · EARLY.** Podnet prišiel od testerky. Pravidlo, ktoré si dnes rozhodol: tlačidlo je dostupné od večierky − 3 h
až po chvíľu, keď sa otvorí bežný štart (večierka − 10 min). Noc sa počíta celá – budova, mince, séria. Ráno sa
nemení. Príprava po skoršom štarte trvá 15 minút od štartu; pri bežnom štarte ostáva „do večierky + 5 minút".
Pred štartom sa appka krátko opýta, aby sa noc nezačala omylom o tri hodiny skôr. Pripomienka večierky sa pre noc,
ktorá už beží, neposiela. Nič nové sa neukladá – skorší štart sa pozná z času štartu, takže to netreba
synchronizovať.

**Potvrdené 2026-10-12.** Tvoja noc z 11. na 12. 10. bola skorší štart: začal si pred bežným oknom, všetko
používanie telefónu sa zmestilo do 15 minút prípravy, budík zazvonil v obvyklom čase, budova stojí a mince sedia.

Šesť drobností z kontroly kódu je spravených a otestovaných 2026-10-12: popis na Dnes po zrušenej skoršej noci
(hovoril „ešte nemôžeš ísť spať", hoci dnešná noc už bola odohraná), pripomienka večierky po zrušenej skoršej noci,
zbytočné prekresľovanie Dnes každú sekundu počas skoršieho okna, dve vety v sprievodcovi a ťuknutie na odkaz na
obrazovke plánov, ktoré by počas noci vyviedlo z appky. Navyše: riadok sprievodcu „pripoj iPhone k Macu" už
testeri neuvidia (platí len pre inštaláciu z Xcode).

**Dobré vedieť:** skorší štart je ostrá noc daného dňa. Keď ju zrušíš, ostane ruina.

**2 · Build 4.** Nahraný 2026-10-12 o 08:41 z príkazového riadku. Pridanie buildu do skupín testerov ostáva na
tebe (App Store Connect → TestFlight). Ďalšie nahratie bude potrebovať číslo buildu 5.

### P1 – pred širším testovaním a pred App Store

**3 · TODAY.** Dnes je prvá obrazovka, ktorú každý tester vidí každý večer. Na iPhone 16 Pro sa tlačidlo
Odpočinok schová pod spodnú lištu a popisy sú dlhé – EARLY k nim pridal ďalší. Preto to dávam pred kalendár, hoci
včera som odporúčal začať kalendárom: medzitým pribudli vonkajší testeri a kalendár začne chýbať až po 35 nociach.
Potrebujem tvoju odpoveď, či sa mačka smie zmenšiť z 250 na asi 200 bodov (vzhľad si už schválil, bez tvojho áno
sa nemení). Polkruh so slnkom a mesiacom sa nedotkne.

**4 · POP.** Malý krok s viditeľným výsledkom. Môže bežať súbežne s TODAY – sú to iné súbory. Potrebujem tvoj
súhlas s rozsahmi a s názvami veľkosti mesta (Osada, Dedina, Mestečko, Mesto, Veľké mesto, Veľkomesto, Metropola).

**5 · CAL.** Dva kroky: najprv mesačná mriežka s prepínaním mesiacov a rokov, potom priemery a graf podľa
zobrazeného mesiaca. Podľa neho sa potom spravia aj snímky pre App Store.

**6 · CARE-2a.** Potvrdil si „súhlasím a potvrdzujem" a myslel si, že je to hotové – nie je. Delím to na dve časti:
+10 🪙 za hodinu s vypnutou obrazovkou sa dá postaviť hneď; „+11 keď sa telefón ani nepohol" potrebuje merať pohyb
celú noc, a to najprv treba vyskúšať na batérii (riadok 18).

**7 · App Store stránka.** Návod s návrhmi textov po anglicky a po slovensky je v iCloude
(`SleepHole/APPSTORE-NAVOD.md`). Snímky obrazovky až po TODAY a CAL, nech sa nerobia dvakrát.

**8 · Riziko pri kontrole Applu.** Rozbor je hotový (`ROZBOR-APP-REVIEW.md`). Jediné riziko s doloženým
zamietnutím sú tri nezdokumentované signály zámku; Beta App Review ich pustila dvakrát, čo je dobrý signál, nie
záruka. Podľa záznamov z tvojho telefónu má zdokumentovaný signál zámku rovnakú rýchlosť, takže záložná cesta
existuje (riadok 33). Zvuk na pozadí v tichu je stredné riziko a poznámky pre kontrolu ho priznávajú.

**32 – 34 · Cesta do App Store.** Zostavenie 5 je malé a nič nové neprináša. Podanie pôjde s voľbou ručného
vydania: odpoveď Applu budeš mať do pár dní a appka sa sama nezverejní. Záložná detekcia je poistka do zásuvky.

**9 · Dlžné skúšky.** Zoznam je v agende v `AGENTS.md`. Najdôležitejšie: appku zavrieť a nevrátiť sa (má sa
zrútiť), systémový budík po skorom potvrdení, tester s telefónom a tabletom.

### P2 – robí appku bohatšou

**10 · NIGHT.** Krok 1: detail ako samostatná obrazovka s kartami (súhrn, príprava, po príprave, ráno, spánok).
Krok 2: časová os. Po CAL, lebo sa naň z kalendára kliká.

**11 · ZOOM.** Testeri majú zatiaľ malé mestá, preto P2. Ty to pocítiš prvý.

**12 · Štatistiky zo spánku.** Prvý krok je tvoj graf (12. 10. 2026): žiadny samostatný graf zaspávania, ale
jedna čiara na noc ako dnes, a na nej farby – zelená „šiel si spať" a modrá „zaspal si" ostávajú, ružová je
budíček a štvrtá ukáže, kedy si naozaj vstal (tvoje „áno" z toho istého večera; jej farbu ešte vyberieme).
Farby sa môžu ešte zmeniť. Zmysel: na prvý pohľad vidieť, ako dlho si spal. Ďalšie štatistiky sú malé samostatné
kroky; dajú sa pridávať po jednej. Zaspávanie a dĺžka spánku majú zmysel len pre ľudí so zapnutým Apple Health.

**13 · TALK.** Tvoj príklad: „nemáme ešte hasičov – obyvateľov to môže trápiť; ale máme dva krásne parky". Potrebuje
obyvateľov (POP) a neskôr sa spojí s obchodom.

**14 – 15 · Počasie a svetlo v meste.** Pokračovanie fázy TOWN-W. Krok 3 má kontrolný bod B, krok 4 bod C.

**16 · CARE-3.** Skúška rozhodne, ktoré upozornenia môže nahradiť živý odpočet a či dokáže nahradiť sirénu
v Prísnom režime.

**17 · Upratovanie.** Samé drobnosti, žiadna nestojí noc. Jeden worker ich spraví naraz.

**18 · SENSE.** Odpoveď na tvoju otázku o senzoroch: svetelný senzor iOS aplikáciám nedáva; mikrofón by šiel, ale
neodporúčam ho (oranžová bodka celú noc, dôvera ľudí). Pohyb je rozumná cesta – treba zmerať cenu.

**19 · Prístupnosť.** V pláne to doteraz nebolo. Pri appke pre veľa ľudí sa na to príde skôr či neskôr; prvý
prechod je malý.

**31 · Slovenské texty pre všetkých.** Vyšlo to z revízie všetkých textov: slovenčina v appke hovorí „zaspal si",
„vstal som", „chorý alebo na dovolenke?". Testerka, ktorá nahlásila skoršiu večierku, to číta každý deň. Anglická
verzia tento problém nemá.

### P3 – neskôr alebo čaká na teba

**20 – 23 · Ostrov a mince.** Všetko je opísané v návrhu z 2026-10-10 a čaká na tvojich osem odpovedí. Pri
mestských službách trvám na jednom: neplatené poplatky nemajú páliť budovy – protirečí to smeru „starostlivosť
namiesto vynucovania".

**26 · Po EARLY.** Dve veci som zámerne nechal na neskôr. Kto ide spať skôr väčšinu dní, má v skutočnosti inú
večierku – appka mu môže ponúknuť jej posun zadarmo. A kto zaspal o dve hodiny skôr, môže sa o dve hodiny skôr
zobudiť a čakať na potvrdenie. Oboje má zmysel rozhodnúť, až keď uvidíme, ako to testeri používajú.

**Ostatné (24, 25, 27 – 30)** sú nápady bez termínu. Žiadny nezačínam bez tvojho slova.

## Odporúčané poradie najbližších krokov

1. ✅ Hotovo 2026-10-12: tvoja skúška EARLY na telefóne, build 4 v TestFlighte, rozbor rizika pri kontrole Applu.
2. ✅ Hotovo 2026-10-12: kompaktné Dnes a zostavenie 5 (riadky 3 a 32).
3. Snímky, polia v App Store Connect a podanie s ručným vydaním (riadky 7 a 34); kým Apple kontroluje, záložná
   detekcia (riadok 33).
4. Obyvatelia, slovenské texty pre všetkých, kalendár (riadky 4, 31, 5) – ďalšie zostavenie.
5. Dlžné skúšky na telefóne (riadok 9). Všetko ostatné až po vydaní 1.0.

## Čo potrebujem od teba

* Áno / nie k riadku 36 (osvetlená ulica mimo žrebu) a súhlas s rozsahmi obyvateľov a názvami veľkosti mesta.
* Zmluva o platených appkách, banka a dane v App Store Connect – spracovanie u Applu trvá dni.
* Rozhodnutie, či appka začne zadarmo alebo platená (podľa neho vyhlásenie DSA a krajiny).
* Pohľad na zostavenie 5 na telefóne: Dnes a odkaz na zásady súkromia v Nastaveniach.
* Súhlas s rozsahmi obyvateľov a s názvami veľkosti mesta (pre POP), keď naň príde rad.
* Otázky z návrhu z 2026-10-10 počkajú do vydania 1.0.
