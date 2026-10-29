# SleepHole – plán podľa buildov

Stav k 29. 10. 2026. Slovenská verzia plánu pre majiteľa. Pre agentov je zdrojom pravdy anglický plán
`docs/IMPLEMENTATION_PLAN.md`, kapitola §0b; keď sa zmení tam, zmení sa aj tu.

## Ako pracujeme

1. **Jeden build naraz.** Build, na ktorom sa robí, má pevný zoznam krokov (8a, 8b, …). Krok doňho pridávaš len ty.
   Claude môže navrhnúť jedným riadkom a čaká na tvoje slovo.
2. **Každý nový nápad – tvoj aj Claudov – ide do tohto plánu** do niektorého z ďalších buildov alebo do „Neskôr“,
   jedným riadkom. Nič nepreskočí rad bez tvojho slova. Zmrazenie rozsahu až do vydania 1.0 platí ďalej: buildy 12–16
   sú plán, nie rozrobená práca.
3. **Build je hotový**, až keď je každý krok skontrolovaný (testy zelené, texty kompletné v oboch jazykoch), je v tvojom
   telefóne, prežil jednu ostrú noc, je commitnutý, nahratý do TestFlightu a pridaný testerom so zoznamom „What to Test“.
4. **Číslo buildu je číslo v TestFlighte** (`CURRENT_PROJECT_VERSION`); krok je číslo + písmeno (8a, 8b, …).
5. **Agenda na začiatku sedenia je krátka** – len to, čo je otvorené teraz. História ide do plánu (§12).
6. **Tick-tock (tvoje pravidlo 19. 10.):** buildy sa striedajú – jeden na nové veci (11, 13, 15, …), ďalší na doladenie
   (10, 12, 14, …) s opravami a chybami, ktoré sa medzitým našli. Do dolaďovacieho buildu nová funkcia nejde. **Posun 29. 10. (tvoja voľba):** build 11 išiel bez obchodu
   so škatuľami a škatule dostali vlastný build 12 – od neho je doladenie 13, 15, … a nové veci 14, 16, …

## Prehľad

| Build | Téma | Stav |
|---|---|---|
| 8 | Pokoj a drobné opravy | hotový – dve ostré noci, commitnutý, nahratý ako 1.0 (8), u testerov (Kamaráti aj SE) |
| 9 | Sprievodca a jasné pravidlá – kandidát na verziu 1.0 | hotový – ostrá noc 18.→19. 10. bez chyby, commitnutý, nahratý ako 1.0 (9) 19. 10., u testerov (Kamaráti aj SE, „What to Test“ anglicky aj slovensky); ďalej návod pre Apple na čistom telefóne, potom build 9 namiesto 7 na kontrolu |
| 10 | **Doladenie:** vypínač systémového budíka, neskorší začiatok a otvorené chyby | **hotový 24. 10.** – ostrá noc 23.→24. 10. bez chyby, commitnutý, nahratý ako 1.0 (10), u testerov (Kamaráti aj SE, „What to Test“ anglicky aj slovensky), build 7 stiahnutý z kontroly a **1.0 (10) odoslaná na kontrolu u Apple** s ručným vydaním |
| 11 | **Nové veci:** iná budova na dnešnú noc, účet mincí; škatule vnútri bez obchodu | **u testerov od 29. 10. ~7:30** – nahratý ako 1.0 (11), „What to Test“ anglicky aj slovensky, Kamaráti aj SE; pull request do `main` si zlúčil 29. 10. ráno |
| 12 | **Nové veci:** škatule – obchod, otvorenie, zbierka | **v práci od 29. 10. ~9:55** – krok 11b4a (obchod a kúpa) v telefóne od 29. 10. 14:59, prvá škatuľa už 29. 10.; ďalej 11b4b otvorenie, 11b4c zbierka, 11b4d bublina, každý na tvoje slovo |
| 13 | **Doladenie** + prístupnosť (+ jasne povedať, na čo appka je) | návrh |
| 14 | **Nové veci:** mesto a voľné noci | návrh |
| 15 | **Doladenie** | návrh |
| 16 | **Nové veci:** živé mesto | návrh |
| Neskôr | nápady bez čísla buildu | zásobník |

## Build 8 – Pokoj a drobné opravy (hotový, u testerov)

Build 8 robí appku láskavejšou: viac odmeňuje, menej trestá, a mačka konečne hovorí ako súčasť mesta. Za každú
pokojnú hodinu noci pribudne +5 🪙. Pravidlo dní 1–3, ktoré pri zmene rozvrhu nulovalo sériu, nahradil týždeň na
zmeny: 7 dní skúšania, potom mesiac pokoj, skôr za 2 000 🪙 – a zmena rozvrhu už sériu nikdy nenuluje.

Mačka dostala plnú komiksovú bublinu, hovorí o oblohe (spln, nov, fázy mesiaca, slnovraty), vety sa striedajú
náhodne a novinka dňa ide prvá. Po zrútenej noci pomenuje budovu a povie pravdu o jej oprave.

| Krok | Typ | Čo | Prečo |
|---|---|---|---|
| 8a | opravené | kód sa dá zadať aj pred budíkom (B31) | tvoja noc 14.→15. 10. |
| 8a | zmenené | sekundy bez medzery („15s“) | tvoje pravidlo |
| 8a | nové | plná komiksová bublina mačky | čitateľnosť a kontrast |
| 8b | nové | +5 🪙 za každú pokojnú hodinu | odmena namiesto trestu |
| 8c | zmenené | týždeň na zmeny namiesto dní 1–3 | tvoj nápad; séria sa už nenuluje |
| 8c | odstránené | dni 1–3, ich karta a hlásenie „Nový mesiac“ | nahradil ich týždeň na zmeny |
| 8d | opravené | „⏳ Za 15s končí príprava“ len mimo appky | chodilo vždy |
| 8e | nové | skutočná fáza mesiaca aj bez mesta | predtým ozdobný kosáčik |
| 8f | nové | mačka hovorí o oblohe (13 viet) | tvoja voľba B z piatich |
| 8g | zmenené | vety mačky náhodne, novinka dňa prvá | „mačka je predvídateľná“ |
| 8h | opravené | mačka pomenuje zrútenú budovu a jej opravu | „stavbári si dali voľno“ nesedelo |
| 8i | opravené | obrazovka sa prekreslí hneď po žolíkovi (B32) | séria sa po žolíkovi neukázala |
| 8j | opravené | „kto im bol modelom“ | tvoje znenie |
| 8k | opravené | potvrdenie týždňa na zmeny: Potvrdiť / Zrušiť, Zrušiť vráti čas | iOS 26 skrýval tlačidlo Zrušiť |

**Stav 18. 10.:** dve ostré noci (16.→17. a 17.→18. 10., obe hotové, 8 z 8 pokojných hodín), commit `b7d5f75`, nahratý do App Store Connect o 07:04, „What to Test“ uložené, skupiny Kamaráti aj SE (SE pridané tvojím klikom).

## Build 9 – Sprievodca a jasné pravidlá (kandidát na verziu 1.0) – hotový, u testerov

**Stav 19. 10.:** prvá ostrá noc (18.→19. 10.) hotová a bez chyby – pravidlá 15s uložené, po budíku nič zo zamknutej
obrazovky (B26 ✓), návrat do appky hneď po rozpoznaní (9a ✓), 7 z 8 pokojných hodín; graf s deliacou bodkou si potvrdil.
Commity `2f8c5eb` (bodka v grafe), `3675e52` (build 9) a dokumenty; nahratý ako 1.0 (9) (tvoje nahratie), v skupinách
Kamaráti aj SE, „What to Test“ anglicky aj slovensky (slovenčinu si pridal sám). Ďalej: návod pre Apple na čistom telefóne
(druhý tester), potom build 9 namiesto 7 na kontrolu. Test preinštalovania (B35) 19. 10. popoludní: nič sa
nestratilo, týždeň na zmeny stále do 22. 10.; samotný prípad B35 sa na tvojom telefóne vyvolať nedal – uzavreté tvojím slovom.

Hlavnou vecou je nový sprievodca: mačka v bubline prevedie nového človeka deviatimi stranami a na konci je zoznam
všetkých pravidiel s číslami priamo z kódu. Žiadna strana sa na najmenšom iPhone nebude rolovať. Dĺžka prípravy
bude na výber (5 / 10 / 15 minút).

Sprievodca, zoznam pravidiel aj FAQ na webe povedia, že stiahnuté Centrum hlásení je odchod z appky a správa sa
číta cez pauzu – bez novej hlášky v noci. Návrat do appky sa bude potichu rátať o ~0,8s skôr (v prospech človeka).

Pred podaním na kontrolu Apple sa prepíše návod pre recenzenta: časy sa nastavia v úvodnom sprievodcovi, kde
platia hneď (tak to robí aj SleepTown), a návod sa raz vyskúša na čistej inštalácii. K tomu upratanie drobných chýb
B12, B13, B14, B15, B16, B22 a B26.

| Krok | Typ | Čo | Stav |
|---|---|---|---|
| 9a | zmenené | návrat do appky sa ráta o ~0,8s skôr (v tvoj prospech, potichu) | hotové, testy, overené nocou 18.→19. 10. |
| 9b | nové | čas na prípravu 5 / 10 / 15 min v Nastaveniach | hotové, testy |
| 9c | nové | sprievodca: 9 strán, rozpráva mačka; „Ako funguje SleepHole“ – všetky pravidlá | hotové, testy, iPhone SE bez rolovania |
| 9d | nové | FAQ na webe: Centrum hlásení je odchod z appky | commitnuté (`454c43d`), ide von tvojím pushom |
| 9e | zmenené | návod pre Apple: časy v sprievodcovi (`docs/REVIEW-NOTES.md`) + automatický test | hotové, testy; do App Store Connect až s tvojím áno |
| 9f | opravené | B12, B13, B14, B15, B16, B22, B26 | hotové, testy; B26 overená nocou 18.→19. 10. |
| 9g | zmenené | Nastavenia: riadky „Sprievodca“ a „Všetky pravidlá“ (tvoje áno 18. 10.) | hotové, testy, v telefóne od 18. 10. ~10:55 |
| 9h | zmenené | Sprievodca podľa displeja: bez bubliny, čo najväčšie písmo, riadkovanie 1,5 kde sa zmestí, rozostupy (tvoje výhrady 18. 10.) | hotové, testy, v telefóne od 18. 10. 11:46 |
| 9i | opravené | B33 + varovanie prísneho režimu trvá 15s a zvoní až do zrútenia (tvoje slovo 18. 10.) | hotové, testy, v telefóne od 18. 10. 13:56; tvoj test 14:00: zvonil ~15s, potom zrútenie ✓ |
| 9j | zmenené | aj odchod z appky (a zatvorenie appky) má 15s namiesto 10s; staré noci po starom, limit 30s za noc ostáva (tvoje áno 18. 10.) | hotové, testy, v telefóne od 18. 10. 14:29 |
| 9k | zmenené | kratšie strany sprievodcu vycentrované na výšku (tvoje áno 18. 10.) | hotové, testy, v telefóne od 18. 10. 15:22 |
| 9l | opravené + nové | graf nocí kompletný (B34: chýbalo 6 začatých nocí) a bohatší: aj vstávanie – potvrdenie budíka, inak koniec spánku z Apple Health – žltou čiarou od zaspatia (tvoje želanie 18. 10.) | hotové, testy, v telefóne od 18. 10. 15:49 |
| 9m | opravené | sprievodca otvorený z Nastavení: večierka, budík aj pripomenutie sa dajú nastaviť priamo v ňom, podľa pravidiel týždňa na zmeny (tvoje želanie 18. 10., ako SleepTown) | hotové, testy, v telefóne od 18. 10. 16:35, doplnok „platí od zajtra“ od 16:58 |
| 9n | zmenené | graf nocí vo variante A: spánok tichou modrou namiesto žltej, začiatok vždy vo farbe kalendára, body zaspatia a vstávania len pri vybranej noci, noc bez Apple Zdravia prechodom vo farbe výsledku, pod grafom najprv značky, potom slová (tvoje rozhodnutie 18. 10.) + pravidelnosť s hodinami a slovom podľa čísla; doplnok: deliaca bodka pri zaspatí a jasnejšia čiara spánku | hotové, testy, v telefóne od 18. 10. 18:10 (bodka 18:54); potvrdil si 19. 10. |
| 9o | opravené | B35: preinštalovanie appky s vypnutým iCloudom už neotvorí nový týždeň na zmeny (tvoje áno 18. 10.) | hotové, testy, v telefóne od 18. 10. 18:20; tvoj test 19. 10.: dvakrát sa vrátilo všetko, prípad B35 sa vyvolať nedal (stojí na testoch) |

**Tvoje odpovede 18. 10.:** spodná lišta plná je OK; build 7 zajtra vymeníme za build 9 a dáme k nemu nový návod pre Apple – najprv ho vyskúša druhý tester na svojom telefóne (build 9 z TestFlightu). **B28 je overená na tvojom telefóne** (test 18. 10. 12:00–12:06: „Zastaviť“, zhasnutie aj nechať tak – appka budík vypne načas). Test našiel **B33**: varovanie sľubuje 10s, ale zvoní len ~7,5s (začne o 2,5s neskôr a stíchne 3s pred zrútením) – tvoje rozhodnutie: 15s a zvoniť až do zrútenia, ide do buildu 9 ako krok 9i. **9i je v telefóne od 13:56 a tvoj test o 14:00 to potvrdil:** varovanie nechané tak zvonilo ~15s, potom testovacia stavba spadla a hlásenie prišlo aj na hodinky.

## Build 10 – Doladenie: vypínač budíka, neskorší začiatok a otvorené chyby (hotový 24. 10.: u testerov a na kontrole u Apple)

**Tvoje slovo 19. 10. ~19:30** (po prečítaní `docs/NAVRH-FLEXIBILITA.md`; zmrazenie do 1.0 si pre tieto dva kroky zrušil):

| Krok | Typ | Čo | Stav |
|---|---|---|---|
| 10a | opravené | B36: systémový budík má klasický prepínač iPhonu. Vypnutý = ráno žiadna záloha ani poistný budík po skoršom potvrdení; varovanie prísneho režimu na zamknutej obrazovke ostáva (tvoja voľba); platí hneď, aj počas noci | hotové, **commitnuté samostatne (`5421f1d`)**, v telefóne od 22. 10. 7:03 |
| 10b | zmenené | začať stavbu do **+30 min** po večierke v miernom režime; prísny režim ostáva +5; skorší začiatok sa nemení (−10 min, skorý štart od −3 h) | hotové, v telefóne od 22. 10. 7:03; **potvrdené 23. 10.** („do 22:00 je OK“), prvá noc v jemnom móde hotová |
| 10c | opravené | B10: odpočinok sa dá potvrdiť v posledných 20 % – pri 30 min od 24. minúty, pri 60 min od 48. minúty; dĺžky 30 / 60 min sa nemenia; skoršie potvrdenie = hotový odpočinok za 50 🪙 (tvoje áno 19. a 20. 10.) | hotové, v telefóne od 22. 10. 7:03; **potvrdené 23. 10.** (odpočinok 22. 10. potvrdený po 48 min) |
| 10d | opravené | B8: batéria – ostrovček na Dnes sa nebude prekresľovať 20× za sekundu, počty sa nebudú stále prepočítavať, záloha sa pripraví až pri exporte; vzhľad ostane rovnaký (tvoje áno 20. 10.). Ostrovček už na Dnes nie je, takže tam nebolo čo opravovať; živé nebo ostáva, ako je | hotové, v telefóne od 22. 10. 7:03 |
| 10e | opravené | B30: appka si pamätá pohľad na mesto a doskroluješ ku každej budove; oddialenie sa nemení – celé veľké mesto sa nezmestí a skrolovať je súčasť hry (tvoje slovo 20. 10.); po každej novej budove sa mesto raz presunie k nej (tvoje áno 22. 10.); karta hore ostáva, vrchol každej veže sa dá potiahnuť pod ňu | hotové, v telefóne od 22. 10. 7:03 |
| 10f | zmenené | sprievodca otvorený znova z Nastavení už rozvrh nemení – časy len ukáže a povie „Rozvrh zmeníš v Nastaveniach → Rozvrh.“; pri prvom spustení sa časy nastavujú ako doteraz (tvoje slovo 22. 10., ruší krok 9m z 18. 10.; do buildu 10 tvoje áno 22. 10.) | hotové, v telefóne od 22. 10. 10:55; **sprievodca z Nastavení potvrdený 22. 10.**; prvé spustenie na čistej inštalácii ešte treba vyskúšať (druhá testerka s buildom 10 z TestFlightu) |
| 10g | opravené | B37 (tvoj nález 23. 10.): čas prípravy na Dnes ide s hodinami – pred večierkou večierka + tvoj čas, po nej teraz + tvoj čas (o 21:40 „do 21:45“), mení sa sám v celú minútu; tri vety v sprievodcovi: „… od večierky, alebo od štartu, ak začneš neskôr“ (tvoje áno 23. 10.) | hotové a commitnuté (`b5ff74c`), v telefóne od 23. 10. 12:47; večer po 21:30 pozri Dnes |
| 10h | zmenené | noc a odpočinok viditeľnejšie: asi 3× vyšší ukazovateľ priebehu pri nočnej stavbe aj pri odpočinku; okolo budovy hneď od štartu lešenie (vyrastie za pár sekúnd), budova rastie v ňom a lešenie zmizne, keď je čas stavby hotový (tvoj nápad a tvoje „stojí mi to za ten deň“ 23. 10.) | hotové, v telefóne od 23. 10. 14:17, commitnuté; noc 23.→24. 10. aj odpočinok 24. 10. s 10g a 10h hotové bez chyby v zázname |

Druhá testerka si systémový budík zatiaľ vypne v Nastaveniach iPhonu → Aplikácie → SleepHole. Neskorší začiatok nemá vlastnú pokutu: príprava beží od začiatku a pokojné hodiny sa rátajú až od jej konca, takže neskorší štart prinesie menej mincí. „Dnešný budík“ (B) si nechcel; druhý rozvrh (D) nie – namiesto neho voľné noci (E) v builde 11.

## Build 11 – Nové veci: ekonomika so škatuľami (u testerov od 29. 10.)

**Vydaný 29. 10. ~7:30 bez obchodu so škatuľami (tvoja voľba ráno: „build 11 as-is daj na test, bez škatúľ, so žrebom pre novú budovu“).** Celý kód je v telefóne od 6:55. Archív 1.0 (11) je skontrolovaný a nahratý o 7:23. Texty „What to Test“ sú anglicky aj slovensky; App Store Connect neprijal emoji mince, preto „coins“ a „mincí“. Build je v skupinách Kamaráti aj SE. Testeri vidia: inú budovu na dnešnú noc, štítok „Nová v meste“, účet mincí a opravu B38. Záznamy, pravidlá a obsah škatúľ sú vnútri, ale bez obchodu sa škatuľa nedá kúpiť. Obchod a otvorenie (11b4) sú teraz **build 12**. Stránka buildu 11: https://claude.ai/artifact/Xhg4qaa1hW9tSfKnb5Uxbo, príprava buildu 12: https://claude.ai/artifact/HA3T7auWRYkfkhLfHRoY6h.

**Zúžený 28. 10. (tvoja voľba):** build 11 budú škatule a to, čo je už hotové. Prístupnosť (11d) ide do buildu 12 – je to doladenie, nie nová funkcia. Voľné noci (11c) idú do buildu 13. S celým pôvodným rozsahom by build išiel testerom asi 7. – 10. 11., len so škatuľami asi 1. – 2. 11. (odhad).

**Tvoj rozsah 22. 10.:** prístupnosť, kontrola ekonomiky s tajomnými škatuľami za mince a dva voľné dni v týždni – „to asi bude dosť na jeden build“. **Začal sa 25. 10. ráno na tvoje slovo** (build 10 je u testerov a na kontrole u Apple). Podrobný návrh s otázkami: stránka https://claude.ai/artifact/Xhg4qaa1hW9tSfKnb5Uxbo.

**Tvoje konečné odpovede (25. 10.):** štatistiky, zoznam chýb a Plány → build 13; účet mincí aj nový žreb; cena škatule pomerne k minciam – 20 % za prvé 3 škatule v mesiaci, 40 % za ďalšie 3, 60 % za ďalšie 3, počítadlo sa raz za mesiac vynuluje; žolík zo škatule platí do konca budúceho mesiaca, najviac jeden navyše od druhu, zlatý nie; vo výhrach šťastná noc, pohľadnice, ozdoby mesta, doplnky mačky, nočná obloha – žetón žrebu nie („chceš inú budovu? zaplať“); voľná noc pomerne 75 / 50 %, začiatok 18:00–3:00, bez budíka, potvrdiť do 14:00; víkendové stavby áno.

**Tvoje odpovede k 11b (25. 10. ~11:50):** najviac jedna škatuľa denne a len ráno po kompletnej noci, k tomu ceny 20 / 40 / 60 %; po 9. škatuli do konca mesiaca už žiadna; **najnižšia cena 400 🪙**; nový žreb najviac raz za noc počas setupu za 100 🪙 (26. 10. si to zmenil, pozri 11b6); **doplnky mačky a nočná obloha už v builde 11**. Grafika: nočná obloha žiadnu nepotrebuje, obloha sa v appke kreslí kódom (padajúce hviezdy, polárna žiara, súhvezdie, kométa). Doplnky mačky sa dajú zložiť z Kenney 3D modelov (šiltovka, prilba staviteľa, cylinder, okuliare, vankúš, koberček, lampa, miska s rybou, darček, hviezda) a nočná čiapka z vlastných tvarov. Najprv dostaneš ukážku na mačke a vyberieš si. **Tvoj výber (25. 10.):** na hlavu nočná čiapka, cylinder a prilba staviteľa; na tvár slnečné okuliare; pri posteli miska s rybou a koberček. Mačka môže mať naraz jednu vec z každej skupiny (hlava + tvár + pri posteli). Ukážka je v iCloude v priečinku `SleepHole/doplnky-macky-ukazka/`.

**Tvoje odpovede k prepočtu mincí 11b1 (26. 10. ~13:55):** šance **D** (viac vecí do zbierky, menej mincí, najvyššia výhra 3× cena); vec do zbierky, ktorú ešte nemáš, príde prvá – opakovanie sa mení na mince, až keď je zbierka celá; **rezerva 1 000 🪙** – škatuľa sa ponúkne, len ak ti po kúpe zostane aspoň 1 000 (na strieborného žolíka); platí len pre škatule, žreb a pauzu platíš z celého zostatku; **úplne prvá škatuľa mesta je bez rezervy** (tvoja voľba ~14:00 – inak by ju nový hráč mal až asi po týždni, takto po 2. až 3. noci); zbierky ako v pláne: 30 pohľadníc, 12 ozdôb, 6 doplnkov, 4 oblohy. **Tvoja poznámka:** aj hráč s 0 mincami má vedieť, že sú tu škatule a výhry, inak ho to po troch nociach prestane baviť → obchod so škatuľami bude vidno vždy, aj pri 0 minciach: čo v škatuli môže byť, šance a koľko mincí ešte chýba (krok 11b4), bez odpočítavania a bez nátlaku. Prepočet: stránka https://claude.ai/artifact/9LZJ8RKQYyf9BJ6nr57tz4.

**Kedy uvidíš škatule (tvoja voľba 27. 10. ráno): až s celým obsahom.** Poradie: 11b2 záznamy → 11b3 pravidlá → 11b5 obsah (pohľadnice s radami o spánku, nočná obloha, ozdoby mesta, doplnky mačky) → 11b4 obchod a otvorenie nakoniec. Prvá škatuľa asi v piatok alebo sobotu 30. – 31. 10. (odhad) – ráno po kompletnej noci, keď bude 11b4 v telefóne; šance D presne podľa tvojej voľby. Každý krok na tvoje slovo. Krok 11b1 (prepočet) ani 11b6b (štítok „Nová v meste“) škatule neboli.

**Aby sa to nepomiešalo (tvoja obava):** appka si nebude pamätať žiadne počítadlo, ktoré by sa mohlo rozísť. Počet škatúľ v mesiaci, žolíky zo škatúľ aj mince sa vždy znova spočítajú z datovaných záznamov – tak ako dnes mince z nocí. Každý záznam ide do pamäte telefónu, do iCloudu aj do zálohy JSON. Prechod cez koniec mesiaca dostane vlastné testy. Najprv údaje a pravidlá, obrazovky nakoniec; po každom malom kroku kontrola.

| Krok | Typ | Čo | Stav |
|---|---|---|---|
| 11a | nové | účet mincí po noci – každá časť mincí na vlastnom riadku (tvoj nápad 22. 10.) | ✅ hotový, v telefóne od 25. 10. 11:40, **potvrdený tebou po noci 26. 10.** (100 + 30 + 35 = 165) |
| 11a2 | oprava | B38: na výsledku noci sa skryje spodná lišta, „Pokračovať“ je vždy celé vidno (tvoj krok 25. 10.) | ✅ hotový, v telefóne od 25. 10. 12:28, **potvrdený tebou** na odpočinku 25. 10. aj na výsledku noci 26. 10. |
| 11b6 | nové | **iná budova na dnešnú noc** (tvoj krok 26. 10., „podmienka dnešného dňa“): počas setupu noci tlačidlo „Iná budova“ – prvý žreb 400 🪙, druhý 800 🪙, potom v tú noc už nie (číslo sa môže neskôr zmeniť); vyberá sa ako pri večernom žrebe (úrovne rovnako, najprv budovy, ktoré ešte nemáš), nikdy budova, ktorá už v tú noc padla; mince sa minú, aj keby sa noc nepodarila; testovacia noc zdarma | hotový a skontrolovaný 26. 10. ~09:05, **v telefóne od 26. 10. 11:39**; **v noci 26. → 27. 10. funguje**: dva žreby (400 + 800 🪙), potom už žiadny. Tvoje hodnotenie: „neoplatilo sa“. Večerný žreb ti dal Múzeum B, jedinú budovu úrovne 2, ktorú si ešte nemal. Prvý žreb dal dom úrovne 1, druhý park s fontánou, ktorý už máš. Tvoja voľba 27. 10.: žreb ostáva, ako je; pribudne len štítok „Nová v meste“ (11b6b). |
| 11b6b | nové | **štítok „Nová v meste“** (tvoja voľba 27. 10. po prvých žreboch): počas setupu noci sa pri mene dnešnej budovy ukáže štítok, keď ju v meste ešte nemáš – aby si novú budovu omylom nevymenil; žreb ostáva náhodný ako večerný, 400 / 800 🪙 | hotový a skontrolovaný 27. 10. ~07:45, v telefóne od 27. 10. 07:48; **potvrdený tebou 28. 10.** („tlačidlo s novými budovami funguje dobre“) – v noci 27. → 28. 10. si dvoma žrebmi (400 + 800 🪙) vymenil dve nové budovy úrovne 1 za nové Múzeum B (úroveň 2) |
| 11b | nové | ekonomika po malých krokoch: 11b1 prepočet mincí, 11b2 záznamy (nákup škatule, žolík zo škatule), 11b3 pravidlá (cena, šance, losovanie), 11b4 obchod a otvorenie, 11b5 obsah (pohľadnice, ozdoby, doplnky mačky, nočná obloha), 11b6 nový žreb za mince (vytiahnutý dopredu, riadok vyššie) | tvoje odpovede 25. 10. sú zapísané; **11b1 hotový 26. 10. ~12:15**, tvoje odpovede k nemu 26. 10. ~13:55 (šance D, najprv vec, ktorú ešte nemáš, rezerva 1 000 okrem prvej škatule, zbierky 30 / 12 / 6 / 4); **11b2 záznamy hotový 27. 10. ~08:30, v telefóne od 08:40** (nič neuvidíš; tvoje mesto sa s novou tabuľkou škatúľ otvorilo celé); **11b3 pravidlá hotové a skontrolované 28. 10. ~07:15** (cena, rezerva, jedna denne, deväť mesačne, šance D, losovanie, šťastná noc ×2 – aj v týždennom denníku a štatistikách); v telefóne zatiaľ nič neuvidíš. **11b5 obsah od 28. 10. ~08:50 na tvoje slovo:** 11b5a 30 pohľadníc s radou o spánku a zdrojom (NHS, CDC, NIH, Mayo Clinic) hotové ~09:55; 11b5b šesť doplnkov mačky (koberček šalviovo zelený, tvoja voľba) hotové ~11:20; 11b5c 12 ozdôb mesta podľa tvojho výberu (s tabuľou SleepHole namiesto majáka) hotové ~12:05; 11b5d štyri nočné oblohy (padajúce hviezdy, polárna žiara, súhvezdie Mačky, kométa) hotové ~13:00; 11b5e obrazovka „Obsah škatúľ“ vo Vývoji, kde celý obsah uvidíš v telefóne, hotové ~13:45 (Nastavenia → Vývoj → „Obsah škatúľ“; v telefóne ešte nie je). Potom 11b4 obchod a otvorenie |
| 11c | nové | voľné noci: najviac 2 dni v týždni, len bez prísneho režimu; začneš 18:00–3:00; 75 % vlastného rozvrhu hotová budova, 50 % rozostavaná, menej nič; víkendové stavby | **presunuté do buildu 13** (tvoja voľba 28. 10.); odpovede hotové |
| 11d | nové | prístupnosť: VoiceOver, väčšie písmo, obmedzený pohyb, nielen farbou, kontrast; potom vyplniť v App Store Connect | **presunuté do buildu 12** (tvoja voľba 28. 10.) |

**Lootbox?** Nie, kým sa mince nedajú kúpiť (žiadne nákupy v appke – pevné pravidlo): škatule otvárané menou, ktorá sa dá len zarobiť, nie sú hazard. Pravdepodobnosti aj tak ukážeme vždy.

**Presunuté do buildu 13 (tvoja odpoveď 25. 10.):** mesačný kalendár, detail noci, graf so štyrmi farbami, zoznam chýb vo Vývoji, obrazovka Plánov.

## Build 12 – Nové veci: škatule (v práci)

**Tvoja voľba 29. 10.:** škatule dostanú vlastný build. Obsah (11b5), pravidlá (11b3) aj záznamy (11b2) sú hotové už v builde 11. Zostáva **11b4**: obchod so škatuľami (vždy viditeľný, aj pri 0 minciach: čo môže v škatuli byť, šance a koľko mincí ešte chýba), otvorenie (krátke, ťuknutím preskočiť), zbierka (pohľadnice, ozdoby, výber doplnkov mačky a oblohy) a bublina mačky, ktorá dnes zakrýva pelech. Pred kontrolou u Apple: vekové hodnotenie „Loot Boxes“ áno a odpoveď na „Simulated Gambling“ (tvoje áno). Päť otázok je na stránke prípravy. Začne sa na tvoje slovo, prvá škatuľa asi 31. 10. – 1. 11. (odhad).

**Začatý 29. 10. ~9:55 (tvoje „Spusti 11b4a“).** Tvoje odpovede: obchod je vlastná záložka v spodnej lište, mačka škatuľu rozbalí, zbierka je v obchode, „Simulated Gambling“ nie, začať ešte dnes. Použitie žolíka zo škatule ide do 11b4c, prvá škatuľa hneď s 11b4a, zatiaľ bez mačky.

| Krok | Čo | Stav |
|---|---|---|
| 11b4a | obchod a kúpa: záložka Škatule, dnešná škatuľa s cenou a potvrdením, šance všetkých 11 možností, výhra jasne napísaná | hotový a skontrolovaný ~11:27, **v telefóne od 29. 10. 14:59**; testy na stránke buildu 12: https://claude.ai/artifact/HA3T7auWRYkfkhLfHRoY6h |
| 11b4b | otvorenie: mačka rozbalí škatuľu, ťuknutím preskočiť | na tvoje slovo |
| 11b4c | zbierka v obchode + použitie žolíka zo škatule | na tvoje slovo |
| 11b4d | bublina mačky sa posunie, keď má mačka niečo pri pelechu | na tvoje slovo |

## Build 13 – Doladenie a prístupnosť (návrh)

Opravy po builde 11 a chyby, ktoré sa medzitým nájdu. (B38 si 25. 10. presunul do buildu 11 ako krok 11a2.) „Zrušiť noc“ je počas prípravy noci schované pod spodnou lištou na iPhone 17e aj 16 Pro.

**Prístupnosť (z buildu 11, tvoja voľba 28. 10.):** VoiceOver (aj hrubý pásik postupu z 10h), väčšie písmo, obmedzený pohyb, nielen farbou, kontrast; potom v App Store Connect vyplniť len to, čo naozaj funguje (tvoje kliky alebo tvoje áno).

**Návrh: jasne povedať, na čo appka je (tvoj nápad 24. 10.).** Testeri čakajú, že appka bude fungovať sama alebo brať spánok z hodiniek, a v miernom režime im „nechodia upozornenia“. Do appky jedna jasná veta: SleepHole spánok nemeria, učí chodiť spať načas, každú noc spúšťaš sám a hodinky netreba. Patrí na prvú stranu sprievodcu a pod prísny režim v Nastaveniach, kde treba dopísať, čo mierny režim nestráži. Ešte skôr to patrí do popisu v App Store a v TestFlighte – to nepotrebuje build, stačia tvoje kliky pri builde 10. Silnejší mierny režim (druhé pokojné pripomenutie, ráno ukázať, koľko si v noci bol na telefóne) počká na podrobnosti od testerov.


## Build 14 – Nové veci: mesto a voľné noci (návrh)

**Voľné noci (z buildu 11, tvoja voľba 28. 10.):** najviac 2 dni v týždni, len bez prísneho režimu; začneš 18:00–3:00, bez budíka, potvrdiť do 14:00; 75 % vlastného rozvrhu hotová budova, 50 % rozostavaná, menej nič; víkendové stavby. Tvoje odpovede sú hotové.

Pohľad na mesto (B30) sa presunul do buildu 10. **Z buildu 11 sem prišli (25. 10.):** mesačný kalendár, detail noci, graf so štyrmi farbami, zoznam chýb a Plány vo Vývoji. Viac
budov úrovne 3 – dnes sa ich päť opakuje. Ostrov, ktorého pobrežie kopíruje mesto (čaká na tvoju odpoveď: voda
všade, alebo horizont).

## Build 15 – Doladenie (návrh)

Opravy po buildoch 12 a 14.

## Build 16 – Nové veci: živé mesto (návrh)

Dážď a sneh nad mestom, deň a noc so svetlami lámp a okien. Live Activity a Dynamic Island s odpočtom noci (najprv
skúška). Skúška pohybu cez noc – od nej závisí +11 🪙, keď telefón len leží.

## Neskôr (bez čísla buildu)

- prísny režim ako záväzok; zvyšok stavebného úradu (výber budovy za jej cenu, zbierka, jedinečné budovy);
  mestské služby (Claude nesúhlasí s „nezaplatené poplatky pália budovy“)
- štart noci z Apple Watch (najprv skúška)
- zvieratká v meste (Cube Pets), téma Fantasy Town, robotický hlas hlásateľa
- počasie cez celú obrazovku Dnes (najprv vysvetli „ako stierač na aute“)
- láskavý posun večierky po viacerých skorších nociach
- najnovšia budova namiesto mačky na Dnes; čínština (teraz neodporúčané); výskumné centrum
- zvuk nočného vlaku na spánok – prototyp na stránke (20 min + klapot A / B / C); odložené 19. 10., teraz nie je priorita
- maják ako ozdoba mesta „na pobrežie“ (tvoje slovo 28. 10. pri výbere 12 ozdôb do škatúľ) – je už vykreslený, počká na pobrežie alebo vodu v meste

## Vydanie v App Store

Vydanie je oddelené od buildov. Verzia 1.0 pôjde von až na tvoje slovo o cene. **Od 24. 10. čaká na kontrolu Apple
build 10** (build 7 stiahnutý) s ručným vydaním – schválenie nič nezverejní.
