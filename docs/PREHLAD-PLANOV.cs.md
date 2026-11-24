# SleepHole – přehled plánů a návrhů

Stav k 2026-10-14. Tento dokument je přehled pro majitele: co je rozdělané, co je navržené a co je jen
nápad – s odhadem náročnosti a s prioritou. Podrobný plán a zadání pro workery jsou v
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) (§10), nákresy k návrhům z 2026-10-10 v
[`NAVRH-MESTO-STATISTIKY.md`](NAVRH-MESTO-STATISTIKY.md).

## Rozsah je zmrazený (tvé rozhodnutí 2026-10-12)

Do vydání verze 1.0 v App Storu se nic nového nezačíná. Otevřené položky se zavírají po jedné v pořadí:
Dnes → riziko u Applu → obyvatelé → slovenské texty pro všechny → kalendář → stránka v obchodě a snímky → zbývající
zkoušky na telefonu. Nový nápad se zapíše jedním řádkem a počká.

## Jak to číst

**Náročnost**

| Značka | Co znamená |
|---|---|
| XS | drobnost, do 15 minut |
| S | jeden krok jednoho workera + kontrola |
| M | 2 – 4 kroky s kontrolními body (jedno až dvě sezení) |
| L | samostatná fáze na více sezení |

**Priorita**

| Značka | Co znamená |
|---|---|
| P0 | hned – brání testerům nebo je rozdělané |
| P1 | před širším testováním a před App Storem |
| P2 | dělá appku bohatší, nic na tom nestojí |
| P3 | později, nápad, nebo čeká na tvé rozhodnutí |
| ✅ | hotovo – položka má v appce zelený štítek |

Priority jsou **doporučení Opusu**. S přehledem a s pořadím jsi 2026-10-12 souhlasil; měnit ho můžeš kdykoli.

## Tabulka

| # | Co | Náročnost | Priorita | Popis |
|---|---|---|---|---|
| 1 | **EARLY – „Dnes jít spát dřív“** | S – M | P0 ✅ | **Hotovo 2026-10-12.** Noc se dá začít nejdřív 3 h před večerkou, bez postihu, příprava 15 min od startu. Tvá noc z 11. na 12. 10. to potvrdila na telefonu (dřívější start, budík, budova, mince). Texty prošly revizí a šest drobných úprav z kontroly je hotových a otestovaných. |
| 2 | **Build 1.0 (4) do TestFlightu** | XS | P0 ✅ | **Hotovo 2026-10-12.** Build 4 je nahraný do App Store Connect (08:41, „Upload succeeded“). Přidat ho do skupin testerů zůstává na tobě – teprve pak dostane opravu i testerka, která problém nahlásila. |
| 3 | **TODAY – kompaktní obrazovka Dnes** | S – M | P1 ✅ | **Hotovo 2026-10-12.** Obě tlačítka jsou v jedné kartě, kočka má 200 bodů, tlačítka jsou níž a dva popisy kratší. Na telefonu jsi potvrdil, že je všechno nad spodní lištou i při třech řádcích textu. Hlavička s městem a teplotou se nedělala – není potřeba. |
| 4 | **POP – obyvatelé** | S | P1 | Build 7, krok 7b – postaveno a zkontrolováno 14. 10. večer (Osada … Metropole v hlavičce města, „Město v číslech“ po klepnutí). Budovy úrovně 2 a 3 mají dnes 0 obyvatel – vypadá to jako chyba. Nové počty podle druhu budovy, názvy velikosti města, „Město v číslech“. |
| 5 | **CAL – měsíční kalendář a období** | M | P1 | Skutečný kalendář po měsících a letech; průměry a graf za zobrazený měsíc. Dnes po 35 dnech starší noci nikde není vidět. |
| 6 | **CARE-2a – mince za klidné hodiny (+10)** | S – M | P1 | Potvrdil jsi to 2026-10-09 a znovu 14. 10. (+10 za klidnou hodinu, +11, když telefon jen leží); postavené to není. Každá hodina noci s vypnutou obrazovkou +10 🪙. Hodiny se počítají od večerky, aby dřívější start nevydělával víc. |
| 7 | **Stránka v App Storu – texty a zásady ochrany soukromí** | S | P1 | Texty jsou v App Store Connect a sedí do písmene, stránka podpory a zásady ochrany soukromí jsou zveřejněné, věkové hodnocení vyšlo 9+, soukromí je zveřejněné jako „Data Not Collected“. Prohlášení podle DSA (nejsem obchodník) a 175 zemí jsou hotové. Novou licenční smlouvu Applu jsi přijal 14. 10. a build 6 je připojený k verzi 1.0. Zbývá tvé rozhodnutí o ceně (smlouva o placených appkách není podepsaná). |
| 8 | **Riziko při kontrole Applu** | S | P1 ✅ | **Hotovo 2026-10-12.** Rozbor je v `ROZBOR-APP-REVIEW.md` (dvanáct rizik, záložní cesta, kroky k podání). Rozhodl jsi: podat se třemi signály zámku a s přiznáním v poznámkách, záložní detekci postavit, dokud Apple kontroluje. Co z rozboru je třeba udělat v kódu, je řádek 32. |
| 9 | **Zbývající zkoušky na telefonu** | tvých 20 – 30 min | P1 | 14. 10. potvrzeno: zavřená appka a nevrátit se → zřícení; pojistný budík po brzkém potvrzení. Zbývá: pauza (zkus ji v rychlé testovací noci – města se nedotkne) a test systémového budíku v sekci Vývoj. Dvě zařízení: zatím nikdo nehlásí problém. Bez kódu. |
| 10 | **NIGHT – detail noci jako vlastní obrazovka** | M | P2 | Karty místo jednoho bloku textu, potom časová osa noci. Sám jsi řekl, že se detail nedá číst. |
| 11 | **ZOOM – kamera města (chyba B30)** | S | P2 | Velké město se nedá vidět celé (zhruba od 45. noci). Oddálení roste s městem, appka si pamatuje pohled, po nové budově se na něj kamera posune. |
| 12 | **Statistiky ze spánku** | S každá | P2 | **Jeden graf noci, ne více grafů (tvé slovo 12. 10.):** na dnešní čáře každé noci čtyři barvy – zelená = kdy jsi šel spát (jako dnes), modrá = kdy jsi usnul (jako dnes), růžová = budíček, čtvrtá = kdy jsi opravdu vstal (její barvu ještě vybereme). Všechno spojené v jedné linii, ať je na první pohled vidět, jak dlouho jsi spal. Později: nejlepší okno pro spánek, pracovní dny proti víkendům. Tvůj směr „statistiky, statistiky, statistiky“. |
| 13 | **TALK – kámoš mluví o městě** | M | P1 | Postaveno 14. 10. večer (build 7, krok 7d): 28 vět kočky, filtr „Kočka“ na obrazovce Texty. Chceš to (14. 10.: „už kočka dává smysl“): kočka na Dnes mluví o městě a o tom, co si „říkají obyvatelé“. Texty píše Opus, ty je přečteš na obrazovce Texty. Build 7, krok 7d – po obyvatelích. |
| 14 | **TOWN-W krok 3 – déšť a sníh ve městě** | M | P2 | Částice nad městem, ležící sníh, šedivější obloha. Počasí appka už zná. |
| 15 | **TOWN-W krok 4 – den a noc ve městě** | M | P2 | Město k večeru zteplá a v noci ztmavne; potom světla lamp a oken. |
| 16 | **CARE-3 – Live Activity / Dynamic Island** | S zkouška, M funkce | P2 | Odpočítávání noci na zamčené obrazovce a v ostrůvku. Zkouška ukáže, jestli se zobrazí i nad Fotoaparátem. |
| 17 | **Úklid drobných chyb** | S | P2 | B12, B13, B14, B15 (průvodce nezmiňuje žolíky), B16, B22, B26 v jednom kroku; B8 (baterie) přeměřit zvlášť. |
| 18 | **SENSE – zkouška pohybu celou noc** | S | P2 | Jedna noc s měřením pohybu proti jedné bez: kolik to stojí baterie. Na výsledku závisí „+11, když se telefon nepohnul“ (CARE-2b). |
| 19 | **Přístupnost** | S – M | P2 | VoiceOver a větší písmo na hlavních obrazovkách. Nový návrh Opusu – appka je pro hodně lidí. |
| 20 | **ISLAND – ostrov a voda** | M | P3 | Pobřeží kopíruje město, okolo voda. Před krokem 4 nebo s ním. Čeká na tvou odpověď (voda všude, nebo horizont). |
| 21 | **ECON E1 – Přísný režim jako závazek** | S | P3 | Zapnout zdarma, vypnout mimo volné dny za 1 000 🪙. Čeká na tvou odpověď. |
| 22 | **ECON E2 – stavební úřad** | M | P3 | K čemu jsou mince: jiné losování za 25 🪙, výběr budovy za její cenu, sbírka druhů. |
| 23 | **ECON E3 – městské služby** | L | P3 | Týdenní rozpočet na hasiče, policii, nemocnici… Opus navrhuje zásadu: budovu může vzít jen noc, nikdy mince. |
| 24 | **Počasí přes celou obrazovku Dnes** | M | P3 | Pozastaveno. Nejdřív je třeba vědět, co znamená „jako stěrač na autě“. |
| 25 | **Apple Watch – start noci z hodinek** | S zkouška, M funkce | P3 | Nejdřív zkouška, jestli to iOS vůbec dovolí s appkou otevřenou na telefonu. |
| 26 | **Po EARLY: posun večerky a dřívější ráno** | S | P3 | Po několika dřívějších nocích laskavě nabídnout posun večerky; případně otevřít ranní potvrzení dřív. Počkat na zkušenost testerů. |
| 27 | **F7 – více budov úrovně 3** | M | P3 | Úroveň 3 má jen 5 budov a město je opakuje (pošta, kostel, hotel, nádraží…). |
| 28 | **Robotický hlas hlasatele** | S – M | P3 | Vlastní hlas v duchu hry M.A.X., vyrobený v telefonu. |
| 29 | **Téma Fantasy Town** | M – L | P3 | Druhá sada budov. Nejsou to jen obrázky – každou budovu je třeba poskládat. |
| 30 | **B10 – odpočinek ukončit dřív** | XS | P3 | Rozhodnutí: smí se odpočinek potvrdit zhruba v posledních 20 % času? |
| 31 | **Slovenské texty pro všechny** | S – M | P1 | Tabulku jsi schválil 14. 10. – build 7, krok 7c, postaveno ten večer. Appka po slovensky oslovuje každého v mužském rodě („zaspal si“, „vstal som“, „postavil si“). Buď texty přepsat neutrálně, nebo přidat volbu oslovení. Nový návrh Opusu z revize textů 2026-10-12. |
| 32 | **Sestavení 5 pro kontrolu Applu** | S | P0 ✅ | **Hotovo 2026-10-12.** Nahráno do App Store Connect ve 14:42 a nainstalováno na tvůj telefon. Obsahuje kompaktní Dnes, odkaz na zásady ochrany soukromí v Nastavení → O appce, ostré sestavení bez vývojářských věcí (ověřeno na nahraném archivu) a přesnější text povolení pro systémový budík. 498 testů zelených. |
| 33 | **Záložní detekce zamknutí** | M | P0 | Tvé ano 14. 10. – build 7, krok 7e postavený a zkontrolovaný ten večer (jen zdokumentované signály, oprava pauzy, 30minutová testovací noc). **14. 10.: Apple binárku zamítl (ITMS-90699) – bez tohoto build 7 do App Storu nepůjde.**  Pojistka z rozboru rizik: appka by rozlišovala „zamkl jsem“ od „odešel jsem“ jen zdokumentovanými signály. Staví se, dokud Apple kontroluje; nasadí se jen tehdy, když Apple tři dnešní signály odmítne. Ztratila by se připomínka a siréna na zamčené obrazovce. |
| 34 | **Snímky a podání do App Storu** | S | P1 | Anglické snímky ze simulátoru (dvě velikosti), potom podání s ručním vydáním – schválení tak nic nezveřejní. Před podáním: zkouška appky na iPadu a recept „noc za 15 minut“ na čisté instalaci. |
| 35 | **Budova místo kočky na Dnes** | M | P3 | Nahrazeno řádkem 13 (14. 10.). Tvůj nápad z 2026-10-12: hrdinou obrazovky Dnes by byla poslední postavená budova, také s reakcí na klepnutí. Zmrazeno do vydání 1.0. |
| 36 | **Osvětlená ulice ne jako noční stavba** | XS – S | P0 | Tvá noc z 13. na 14. 10. postavila „Osvětlenou ulici“ – podle tebe vtip, ne budova ani park. Odsouhlasil jsi 14. 10.: vyřadit ji z losování, každá noc postaví budovu nebo park; lampy přibudou v ulicích samy později (krok 4 – den a noc ve městě). Build 7, krok 7a – postaveno a zkontrolováno 14. 10. večer (testy zelené), na tvém telefonu od 17:18. |
| 37 | **Čínština** | M | P3 | Jediná zpětná vazba z TestFlightu (anonym, 13. 10.). Teď nedoporučuji: asi 655 textů + stránka v obchodě a snímky, nikdo na kontrolu tónu, a pevninská Čína stejně vyžaduje registraci ICP. |
| 38 | **Obrazovka Texty (Vývoj)** | S | P1 | Postaveno 14. 10. večer (build 7, krok 7c). Tvé přání z 14. 10.: v Nastavení → Vývoj vedle „Plány a návrhy“ všechny texty appky, anglicky a slovensky, každý v samostatném boxu, s hledáním. Čteš je svým tempem a řekneš, co je špatně. Build 7, krok 7c. |
| – | Povolené appky během noci | – | nedoporučuji | Vyžaduje Screen Time API – to je proti pevnému pravidlu projektu. |

## Popis po skupinách

### P0 – hotovo ✅

**1 · EARLY.** Podnět přišel od testerky. Pravidlo, o kterém jsi dnes rozhodl: tlačítko je dostupné od večerky − 3 h
až do chvíle, kdy se otevře běžný start (večerka − 10 min). Noc se počítá celá – budova, mince, série. Ráno se
nemění. Příprava po dřívějším startu trvá 15 minut od startu; při běžném startu zůstává „do večerky + 5 minut“.
Před startem se appka krátce zeptá, aby noc omylem nezačala o tři hodiny dřív. Připomínka večerky se pro noc,
která už běží, neposílá. Nic nového se neukládá – dřívější start se pozná z času startu, takže to není třeba
synchronizovat.

**Potvrzeno 2026-10-12.** Tvá noc z 11. na 12. 10. byla dřívější start: začal jsi před běžným oknem, veškeré
používání telefonu se vešlo do 15 minut přípravy, budík zazvonil v obvyklém čase, budova stojí a mince sedí.

Šest drobností z kontroly kódu je hotových a otestovaných 2026-10-12: popis na Dnes po zrušené dřívější noci
(říkal „ještě nemůžeš jít spát“, ačkoli dnešní noc už byla odehraná), připomínka večerky po zrušené dřívější noci,
zbytečné překreslování Dnes každou sekundu během dřívějšího okna, dvě věty v průvodci a klepnutí na odkaz na
obrazovce plánů, které by během noci vyvedlo z appky. Navíc: řádek průvodce „připoj iPhone k Macu“ už
testeři neuvidí (platí jen pro instalaci z Xcode).

**Dobré vědět:** dřívější start je ostrá noc daného dne. Když ji zrušíš, zůstane ruina.

**2 · Build 4.** Nahraný 2026-10-12 v 08:41 z příkazového řádku. Přidání buildu do skupin testerů zůstává na
tobě (App Store Connect → TestFlight). Další nahrání bude potřebovat číslo buildu 5.

### P1 – před širším testováním a před App Storem

**3 · TODAY.** Dnes je první obrazovka, kterou každý tester vidí každý večer. Na iPhonu 16 Pro se tlačítko
Odpočinek schová pod spodní lištu a popisy jsou dlouhé – EARLY k nim přidal další. Proto to dávám před kalendář, i když
jsem včera doporučoval začít kalendářem: mezitím přibyli externí testeři a kalendář začne chybět až po 35 nocích.
Potřebuji tvou odpověď, jestli se kočka smí zmenšit z 250 zhruba na 200 bodů (vzhled jsi už schválil, bez tvého ano
se nemění). Půlkruhu se sluncem a měsícem se nedotknu.

**4 · POP.** Malý krok s viditelným výsledkem. Může běžet souběžně s TODAY – jsou to jiné soubory. Potřebuji tvůj
souhlas s rozsahy a s názvy velikosti města (Osada, Vesnice, Městečko, Město, Velké město, Velkoměsto, Metropole).

**5 · CAL.** Dva kroky: nejdřív měsíční mřížka s přepínáním měsíců a let, potom průměry a graf podle
zobrazeného měsíce. Podle něj se pak udělají i snímky pro App Store.

**6 · CARE-2a.** Potvrdil jsi „souhlasím a potvrzuji“ a myslel sis, že je to hotové – není. Dělím to na dvě části:
+10 🪙 za hodinu s vypnutou obrazovkou se dá postavit hned; „+11, když se telefon ani nepohnul“ potřebuje měřit pohyb
celou noc, a to je nejdřív třeba vyzkoušet na baterii (řádek 18).

**7 · Stránka v App Storu.** Návod s návrhy textů anglicky a slovensky je v iCloudu
(`SleepHole/APPSTORE-NAVOD.md`). Snímky obrazovky až po TODAY a CAL, ať se nedělají dvakrát.

**8 · Riziko při kontrole Applu.** Rozbor je hotový (`ROZBOR-APP-REVIEW.md`). Jediné riziko s doloženým
zamítnutím jsou tři nezdokumentované signály zámku; Beta App Review je pustila dvakrát, což je dobrý signál, ne
záruka. Podle záznamů z tvého telefonu má zdokumentovaný signál zámku stejnou rychlost, takže záložní cesta
existuje (řádek 33). Zvuk na pozadí v tichu je střední riziko a poznámky pro kontrolu ho přiznávají.

**32 – 34 · Cesta do App Storu.** Sestavení 5 je malé a nic nového nepřináší. Podání půjde s volbou ručního
vydání: odpověď Applu budeš mít do pár dní a appka se sama nezveřejní. Záložní detekce je pojistka do šuplíku.

**9 · Zbývající zkoušky.** Seznam je v agendě v `AGENTS.md`. Nejdůležitější: appku zavřít a nevrátit se (má se
zřítit), systémový budík po brzkém potvrzení, tester s telefonem a tabletem.

### P2 – dělá appku bohatší

**10 · NIGHT.** Krok 1: detail jako samostatná obrazovka s kartami (souhrn, příprava, po přípravě, ráno, spánek).
Krok 2: časová osa. Po CAL, protože se na něj z kalendáře klepá.

**11 · ZOOM.** Testeři mají zatím malá města, proto P2. Ty to pocítíš první.

**12 · Statistiky ze spánku.** První krok je tvůj graf (12. 10. 2026): žádný samostatný graf usínání, ale
jedna čára na noc jako dnes, a na ní barvy – zelená „šel jsi spát“ a modrá „usnul jsi“ zůstávají, růžová je
budíček a čtvrtá ukáže, kdy jsi opravdu vstal (tvé „ano“ z téhož večera; její barvu ještě vybereme).
Barvy se ještě mohou změnit. Smysl: na první pohled vidět, jak dlouho jsi spal. Další statistiky jsou malé samostatné
kroky; dají se přidávat po jednom. Usínání a délka spánku mají smysl jen pro lidi se zapnutým Apple Health.

**13 · TALK.** Tvůj příklad: „nemáme ještě hasiče – obyvatele to může trápit; ale máme dva krásné parky“. Potřebuje
obyvatele (POP) a později se spojí s obchodem.

**14 – 15 · Počasí a světlo ve městě.** Pokračování fáze TOWN-W. Krok 3 má kontrolní bod B, krok 4 bod C.

**16 · CARE-3.** Zkouška rozhodne, která upozornění může nahradit živé odpočítávání a jestli dokáže nahradit sirénu
v Přísném režimu.

**17 · Úklid.** Samé drobnosti, žádná nestojí noc. Jeden worker je udělá najednou.

**18 · SENSE.** Odpověď na tvou otázku o senzorech: světelný senzor iOS aplikacím nedává; mikrofon by šel, ale
nedoporučuji ho (oranžová tečka celou noc, důvěra lidí). Pohyb je rozumná cesta – je třeba změřit cenu.

**19 · Přístupnost.** V plánu to doteď nebylo. U appky pro hodně lidí se na to přijde dřív nebo později; první
průchod je malý.

**31 · Slovenské texty pro všechny.** Vyšlo to z revize všech textů: slovenština v appce říká „zaspal si“,
„vstal som“, „chorý alebo na dovolenke?“. Testerka, která nahlásila dřívější večerku, to čte každý den. Anglická
verze tento problém nemá.

### P3 – později nebo čeká na tebe

**20 – 23 · Ostrov a mince.** Všechno je popsáno v návrhu z 2026-10-10 a čeká na tvých osm odpovědí. U
městských služeb trvám na jednom: neplacené poplatky nemají pálit budovy – odporuje to směru „péče
místo vynucování“.

**26 · Po EARLY.** Dvě věci jsem záměrně nechal na později. Kdo jde spát dřív většinu dní, má ve skutečnosti jinou
večerku – appka mu může nabídnout její posun zdarma. A kdo usnul o dvě hodiny dřív, může se o dvě hodiny dřív
probudit a čekat na potvrzení. Obojí má smysl rozhodnout, až uvidíme, jak to testeři používají.

**Ostatní (24, 25, 27 – 30)** jsou nápady bez termínu. Žádný nezačínám bez tvého slova.

## Doporučené pořadí nejbližších kroků

1. ✅ Hotovo 2026-10-12: tvá zkouška EARLY na telefonu, build 4 v TestFlightu, rozbor rizika při kontrole Applu.
2. ✅ Hotovo 2026-10-12: kompaktní Dnes a sestavení 5 (řádky 3 a 32).
3. Snímky, pole v App Store Connect a podání s ručním vydáním (řádky 7 a 34); dokud Apple kontroluje, záložní
   detekce (řádek 33).
4. Obyvatelé, slovenské texty pro všechny, kalendář (řádky 4, 31, 5) – další sestavení.
5. Zbývající zkoušky na telefonu (řádek 9). Všechno ostatní až po vydání 1.0.

## Co potřebuji od tebe

* Ano / ne k řádku 36 (osvětlená ulice mimo losování) a souhlas s rozsahy obyvatel a názvy velikosti města.
* Smlouva o placených appkách, banka a daně v App Store Connect – zpracování u Applu trvá dny.
* Rozhodnutí, jestli bude appka zpočátku zdarma, nebo placená (podle něj prohlášení DSA a země).
* Pohled na sestavení 5 na telefonu: Dnes a odkaz na zásady ochrany soukromí v Nastavení.
* Souhlas s rozsahy obyvatel a s názvy velikosti města (pro POP), až na to přijde řada.
* Otázky z návrhu z 2026-10-10 počkají do vydání 1.0.
