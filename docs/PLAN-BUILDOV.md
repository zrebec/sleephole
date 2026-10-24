# SleepHole – plán podľa buildov

Stav k 18. 10. 2026. Slovenská verzia plánu pre majiteľa. Pre agentov je zdrojom pravdy anglický plán
`docs/IMPLEMENTATION_PLAN.md`, kapitola §0b; keď sa zmení tam, zmení sa aj tu.

## Ako pracujeme

1. **Jeden build naraz.** Build, na ktorom sa robí, má pevný zoznam krokov (8a, 8b, …). Krok doňho pridávaš len ty.
   Claude môže navrhnúť jedným riadkom a čaká na tvoje slovo.
2. **Každý nový nápad – tvoj aj Claudov – ide do tohto plánu** do niektorého z ďalších buildov alebo do „Neskôr“,
   jedným riadkom. Nič nepreskočí rad bez tvojho slova. Zmrazenie rozsahu až do vydania 1.0 platí ďalej: buildy 11–15
   sú plán, nie rozrobená práca.
3. **Build je hotový**, až keď je každý krok skontrolovaný (testy zelené, texty kompletné v oboch jazykoch), je v tvojom
   telefóne, prežil jednu ostrú noc, je commitnutý, nahratý do TestFlightu a pridaný testerom so zoznamom „What to Test“.
4. **Číslo buildu je číslo v TestFlighte** (`CURRENT_PROJECT_VERSION`); krok je číslo + písmeno (8a, 8b, …).
5. **Agenda na začiatku sedenia je krátka** – len to, čo je otvorené teraz. História ide do plánu (§12).
6. **Tick-tock (tvoje pravidlo 19. 10.):** buildy sa striedajú – jeden na nové veci (11, 13, 15, …), ďalší na doladenie
   (10, 12, 14, …) s opravami a chybami, ktoré sa medzitým našli. Do dolaďovacieho buildu nová funkcia nejde.

## Prehľad

| Build | Téma | Stav |
|---|---|---|
| 8 | Pokoj a drobné opravy | hotový – dve ostré noci, commitnutý, nahratý ako 1.0 (8), u testerov (Kamaráti aj SE) |
| 9 | Sprievodca a jasné pravidlá – kandidát na verziu 1.0 | hotový – ostrá noc 18.→19. 10. bez chyby, commitnutý, nahratý ako 1.0 (9) 19. 10., u testerov (Kamaráti aj SE, „What to Test“ anglicky aj slovensky); ďalej návod pre Apple na čistom telefóne, potom build 9 namiesto 7 na kontrolu |
| 10 | **Doladenie:** vypínač systémového budíka, neskorší začiatok a otvorené chyby | v práci od 19. 10.; ostrá noc 23.→24. 10. bez chyby, číslo buildu 10 commitnuté 24. 10.; ďalej nahratie, testeri a kontrola u Apple |
| 11 | **Nové veci:** voľné noci, štatistiky a nový žreb | návrh |
| 12 | **Doladenie** (+ jasne povedať, na čo appka je) | návrh |
| 13 | **Nové veci:** mesto | návrh |
| 14 | **Doladenie** | návrh |
| 15 | **Nové veci:** živé mesto | návrh |
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

## Build 10 – Doladenie: vypínač budíka, neskorší začiatok a otvorené chyby (v telefóne od 22. 10. 7:03, 10f od 10:55; 10a–10f commitnuté 22. 10., 10g 23. 10., 10h sa robí; k testerom a na kontrolu k Apple po noci s 10g a 10h)

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

## Build 11 – Nové veci: prístupnosť, ekonomika so škatuľami a voľné noci (návrh)

**Tvoj rozsah 22. 10.:** prístupnosť, kontrola ekonomiky s tajomnými škatuľami za mince a dva voľné dni v týždni – „to asi bude dosť na jeden build“. Začne sa, až keď bude build 10 u testerov a na kontrole u Apple. Podrobný návrh s otázkami: stránka https://claude.ai/artifact/Xhg4qaa1hW9tSfKnb5Uxbo.

| Krok | Typ | Čo | Stav |
|---|---|---|---|
| 11a | nové | účet mincí po noci – každá časť mincí na vlastnom riadku (tvoj nápad 22. 10.) | návrh |
| 11b | nové | ekonomika: prepočet mincí, potom tajomné škatule za mince (nikdy za peniaze, pravdepodobnosti vždy viditeľné, jedna denne po hotovej noci); vnútri mince (zriedka aj viac než cena) a žolík navyše, nie budovy; možno aj nový žreb | návrh, tvoje odpovede na stránke |
| 11c | nové | voľné noci: najviac 2 dni v týždni, len bez prísneho režimu; začneš, kedy chceš; 6 h a viac hotová budova, 4 h rozostavaná, menej nič | návrh, tvoje odpovede na stránke |
| 11d | nové | prístupnosť: VoiceOver, väčšie písmo, obmedzený pohyb, nielen farbou, kontrast; potom vyplniť v App Store Connect | návrh |

**Lootbox?** Nie, kým sa mince nedajú kúpiť (žiadne nákupy v appke – pevné pravidlo): škatule otvárané menou, ktorá sa dá len zarobiť, nie sú hazard. Pravdepodobnosti aj tak ukážeme vždy.

**Návrh presunúť do buildu 13:** mesačný kalendár, detail noci, graf so štyrmi farbami, zoznam chýb vo Vývoji, obrazovka Plánov (čaká na tvoje slovo).

## Build 12 – Doladenie (návrh)

Opravy po builde 11 a chyby, ktoré sa medzitým nájdu.

**Návrh: jasne povedať, na čo appka je (tvoj nápad 24. 10.).** Testeri čakajú, že appka bude fungovať sama alebo brať spánok z hodiniek, a v miernom režime im „nechodia upozornenia“. Do appky jedna jasná veta: SleepHole spánok nemeria, učí chodiť spať načas, každú noc spúšťaš sám a hodinky netreba. Patrí na prvú stranu sprievodcu a pod prísny režim v Nastaveniach, kde treba dopísať, čo mierny režim nestráži. Ešte skôr to patrí do popisu v App Store a v TestFlighte – to nepotrebuje build, stačia tvoje kliky pri builde 10. Silnejší mierny režim (druhé pokojné pripomenutie, ráno ukázať, koľko si v noci bol na telefóne) počká na podrobnosti od testerov.


## Build 13 – Nové veci: mesto (návrh)

Pohľad na mesto (B30) sa presunul do buildu 10. Viac
budov úrovne 3 – dnes sa ich päť opakuje. Ostrov, ktorého pobrežie kopíruje mesto (čaká na tvoju odpoveď: voda
všade, alebo horizont).

## Build 14 – Doladenie (návrh)

Opravy po builde 13.

## Build 15 – Nové veci: živé mesto (návrh)

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

## Vydanie v App Store

Vydanie je oddelené od buildov. Verzia 1.0 pôjde von až na tvoje slovo o cene. Build 7 čaká na kontrolu Apple
s ručným vydaním – schválenie nič nezverejní. Ktorý build pôjde von, sa rozhodne, keď Apple odpovie a návod pre
recenzenta bude opravený – najpravdepodobnejšie build 9.
