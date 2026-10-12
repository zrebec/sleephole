# SleepHole – prehľad plánov a návrhov

Stav k 2026-10-12 ráno. Tento dokument je prehľad pre majiteľa: čo je rozrobené, čo je navrhnuté a čo je len
nápad – s odhadom náročnosti a s prioritou. Podrobný plán a zadania pre workerov sú v
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) (§10), nákresy k návrhom z 2026-10-10 v
[`NAVRH-MESTO-STATISTIKY.md`](NAVRH-MESTO-STATISTIKY.md).

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
| 3 | **TODAY – kompaktná obrazovka Dnes** | S – M | P1 | Obe tlačidlá v jednej karte, kratšie popisy, hlavička s mestom a teplotou. Dnes sa tlačidlo Odpočinok na iPhone 16 Pro schová pod spodnú lištu. |
| 4 | **POP – obyvatelia** | S | P1 | Budovy úrovne 2 a 3 majú dnes 0 obyvateľov – vyzerá to ako chyba. Nové počty podľa druhu budovy, názvy veľkosti mesta, „Mesto v číslach". |
| 5 | **CAL – mesačný kalendár a obdobia** | M | P1 | Skutočný kalendár po mesiacoch a rokoch; priemery a graf za zobrazený mesiac. Dnes po 35 dňoch staršie noci nikde nevidno. |
| 6 | **CARE-2a – mince za pokojné hodiny (+10)** | S – M | P1 | Potvrdil si to 2026-10-09, postavené to nie je. Každá hodina noci s vypnutou obrazovkou +10 🪙. Hodiny sa počítajú od večierky, aby skorší štart nezarábal viac. |
| 7 | **App Store stránka – texty a zásady súkromia** | S | P1 | Návrhy textov máš v iCloude. Treba tvoj výber podtitulu, kde bude stránka so zásadami súkromia a ktorý kontakt smie byť verejný. Bez kódu. |
| 8 | **Riziko pri kontrole Applu** | S | P1 | Dve veci môže Apple spochybniť: signály zamknutia obrazovky a tichý zvuk, ktorý drží appku nažive. Rozbor a záložný plán skôr, než pôjde appka do App Store. |
| 9 | **Dlžné skúšky na telefóne** | tvojich 20 – 30 min | P1 | Zavretá appka a nevrátiť sa → zrútenie; systémový budík; synchronizácia na dvoch zariadeniach; pauza. Bez kódu. |
| 10 | **NIGHT – detail noci ako vlastná obrazovka** | M | P2 | Karty namiesto jedného bloku textu, potom časová os noci. Sám si povedal, že detail sa nedá čítať. |
| 11 | **ZOOM – kamera mesta (chyba B30)** | S | P2 | Veľké mesto sa nedá vidieť celé (od asi 45. noci). Oddialenie rastie s mestom, appka si pamätá pohľad, po novej budove sa naň kamera posunie. |
| 12 | **Štatistiky zo spánku** | S každá | P2 | Čas zaspávania ako vlastný graf, najlepšie okno na spánok, koľko si naozaj spal, pracovné dni proti víkendom. Tvoj smer „štatistiky, štatistiky, štatistiky". |
| 13 | **TALK – kamoš hovorí o meste** | M | P2 | Bublina pod mačkou na Dnes: jedna veta denne o meste, sérii a včerajšej noci. Až po POP. |
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
| 31 | **Slovenské texty pre všetkých** | S – M | P2 | Appka po slovensky oslovuje každého v mužskom rode („zaspal si", „vstal som", „postavil si"). Buď texty prepísať neutrálne, alebo pridať voľbu oslovenia. Nový návrh Opusu z revízie textov 2026-10-12. |
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

**8 · Riziko pri kontrole Applu.** Vonkajší testeri prechádzajú kontrolou Applu (Beta App Review), App Store
prísnejšou. Appka používa dva postupy, na ktoré sa Apple môže opýtať. Rozbor povie, čo sa dá vysvetliť v poznámke
pre kontrolu a čo by sme robili, keby to Apple odmietol. Lepšie to vedieť teraz ako pri podaní do App Store.

**9 · Dlžné skúšky.** Zoznam je v agende v `AGENTS.md`. Najdôležitejšie: appku zavrieť a nevrátiť sa (má sa
zrútiť), systémový budík po skorom potvrdení, tester s telefónom a tabletom.

### P2 – robí appku bohatšou

**10 · NIGHT.** Krok 1: detail ako samostatná obrazovka s kartami (súhrn, príprava, po príprave, ráno, spánok).
Krok 2: časová os. Po CAL, lebo sa naň z kalendára kliká.

**11 · ZOOM.** Testeri majú zatiaľ malé mestá, preto P2. Ty to pocítiš prvý.

**12 · Štatistiky zo spánku.** Každá je malý samostatný krok; dajú sa pridávať po jednej. Majú zmysel len pre
ľudí so zapnutým Apple Health.

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

1. ✅ Hotovo 2026-10-12: tvoja skúška EARLY na telefóne a build 4 nahraný do TestFlightu.
2. TODAY a POP súbežne (dvaja workeri, iné súbory).
3. CAL (dva kroky), popri tom tvoje odpovede k App Store stránke.
4. CARE-2a a rozbor rizika pri kontrole Applu.
5. NIGHT, potom podľa chuti: ZOOM, štatistiky zo spánku, počasie v meste.

## Čo potrebujem od teba

* Či sa mačka na Dnes smie zmenšiť na asi 200 bodov (pre TODAY).
* Súhlas s rozsahmi obyvateľov a s názvami veľkosti mesta (pre POP).
* Podtitul, miesto pre zásady súkromia a verejný kontakt (pre App Store).
* Zvyšných šesť otázok z návrhu z 2026-10-10 – stačí postupne, keď na ne príde rad.
