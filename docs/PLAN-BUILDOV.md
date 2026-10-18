# SleepHole – plán podľa buildov

Stav k 18. 10. 2026. Slovenská verzia plánu pre majiteľa. Pre agentov je zdrojom pravdy anglický plán
`docs/IMPLEMENTATION_PLAN.md`, kapitola §0b; keď sa zmení tam, zmení sa aj tu.

## Ako pracujeme

1. **Jeden build naraz.** Build, na ktorom sa robí, má pevný zoznam krokov (8a, 8b, …). Krok doňho pridávaš len ty.
   Claude môže navrhnúť jedným riadkom a čaká na tvoje slovo.
2. **Každý nový nápad – tvoj aj Claudov – ide do tohto plánu** do niektorého z ďalších buildov alebo do „Neskôr“,
   jedným riadkom. Nič nepreskočí rad bez tvojho slova. Zmrazenie rozsahu až do vydania 1.0 platí ďalej: buildy 10–12
   sú plán, nie rozrobená práca.
3. **Build je hotový**, až keď je každý krok skontrolovaný (testy zelené, texty kompletné v oboch jazykoch), je v tvojom
   telefóne, prežil jednu ostrú noc, je commitnutý, nahratý do TestFlightu a pridaný testerom so zoznamom „What to Test“.
4. **Číslo buildu je číslo v TestFlighte** (`CURRENT_PROJECT_VERSION`); krok je číslo + písmeno (8a, 8b, …).
5. **Agenda na začiatku sedenia je krátka** – len to, čo je otvorené teraz. História ide do plánu (§12).

## Prehľad

| Build | Téma | Stav |
|---|---|---|
| 8 | Pokoj a drobné opravy | hotový – dve ostré noci, commitnutý, nahratý ako 1.0 (8), u testerov (Kamaráti aj SE) |
| 9 | Sprievodca a jasné pravidlá – kandidát na verziu 1.0 | 9a–9f postavené a skontrolované; v tvojom telefóne od 18. 10. 09:03; ďalej tvoja noc, commit, nahratie |
| 10 | Štatistiky a nový žreb | návrh |
| 11 | Mesto | návrh |
| 12 | Živé mesto | návrh |
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

## Build 9 – Sprievodca a jasné pravidlá (kandidát na verziu 1.0)

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
| 9a | zmenené | návrat do appky sa ráta o ~0,8s skôr (v tvoj prospech, potichu) | hotové, testy |
| 9b | nové | čas na prípravu 5 / 10 / 15 min v Nastaveniach | hotové, testy |
| 9c | nové | sprievodca: 9 strán, rozpráva mačka; „Ako funguje SleepHole“ – všetky pravidlá | hotové, testy, iPhone SE bez rolovania |
| 9d | nové | FAQ na webe: Centrum hlásení je odchod z appky | commitnuté (`454c43d`), ide von tvojím pushom |
| 9e | zmenené | návod pre Apple: časy v sprievodcovi (`docs/REVIEW-NOTES.md`) + automatický test | hotové, testy; do App Store Connect až s tvojím áno |
| 9f | opravené | B12, B13, B14, B15, B16, B22, B26 | hotové, testy |

## Build 10 – Štatistiky a nový žreb (návrh)

Skutočný mesačný kalendár s obdobiami a detail noci ako samostatná obrazovka s časovou osou. Graf spánku v jednej
čiare so štyrmi farbami (šiel si spať, zaspal si, budíček, kedy si naozaj vstal).

**Nový žreb počas prípravy:** keď sa ti dnešná budova nepáči, môžeš si za mince vyžrebovať inú, len z úrovní, ktoré
už máš odomknuté. Claude odporúča: žiadny zadarmo, prvý žreb noci 100 🪙 a každý ďalší o 100 drahší (200, 300 …),
ako pri pauze – aby si to človek rozmyslel a nežreboval až do mrakodrapu. **Cenu rozhodneš ty.**

Ak sa zmestí, aj zoznam chýb v appke (Nastavenia → Vývoj, ako „Plány a návrhy“) – tvoj nápad zo 16. 10.; len na
čítanie z jedného .md súboru. Návrh Claude: obrazovka „Plány a návrhy“ bude čítať tento plán buildov namiesto starého
prehľadu z 12. 10. (čaká na tvoje slovo).

Navrch prístupnosť (VoiceOver, väčšie písmo) na obrazovkách Dnes, noc a Štatistiky – appka je pre veľa ľudí.

## Build 11 – Mesto (návrh)

Celé veľké mesto bude vidieť naraz a appka si zapamätá pohľad (chyba B30, týka sa miest od asi 45 nocí). Viac
budov úrovne 3 – dnes sa ich päť opakuje. Ostrov, ktorého pobrežie kopíruje mesto (čaká na tvoju odpoveď: voda
všade, alebo horizont).

## Build 12 – Živé mesto (návrh)

Dážď a sneh nad mestom, deň a noc so svetlami lámp a okien. Live Activity a Dynamic Island s odpočtom noci (najprv
skúška). Skúška pohybu cez noc – od nej závisí +11 🪙, keď telefón len leží.

## Neskôr (bez čísla buildu)

- prísny režim ako záväzok; zvyšok stavebného úradu (výber budovy za jej cenu, zbierka, jedinečné budovy);
  mestské služby (Claude nesúhlasí s „nezaplatené poplatky pália budovy“)
- štart noci z Apple Watch (najprv skúška)
- zvieratká v meste (Cube Pets), téma Fantasy Town, robotický hlas hlásateľa
- počasie cez celú obrazovku Dnes (najprv vysvetli „ako stierač na aute“)
- láskavý posun večierky po viacerých skorších nociach; skoršie ukončenie odpočinku (B10)
- najnovšia budova namiesto mačky na Dnes; čínština (teraz neodporúčané); výskumné centrum
- batéria (B8); varovný budík prísneho režimu (B27, B28) znova preveriť

## Vydanie v App Store

Vydanie je oddelené od buildov. Verzia 1.0 pôjde von až na tvoje slovo o cene. Build 7 čaká na kontrolu Apple
s ručným vydaním – schválenie nič nezverejní. Ktorý build pôjde von, sa rozhodne, keď Apple odpovie a návod pre
recenzenta bude opravený – najpravdepodobnejšie build 9.
