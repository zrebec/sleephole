# Pružnejšia večierka a budík – rozbor a návrh (19. 10. 2026)

*Pre majiteľa, po slovensky. Podklad k rozhodnutiu – nič z toho sa nerobí bez tvojho slova (zmrazenie rozsahu do 1.0
platí, kým ho nezrušíš). Spec pre kód bude v pláne (§0b, §10), až keď vyberieš.*

## 1. Čo sa stalo

Druhá testerka prešla 19. 10. úvodným sprievodcom na čistom telefóne – sprievodca sa ukázal a prebehol
v poriadku. Jej postreh:

> Pevnú večierku nemám. Cez víkend mám voľno. V pracovné dni: keď sa večer osprchujem, budík si dám na 5:45; keď nie,
> na 5:20, lebo sa musím osprchovať ráno.

Tvoj záver: **toto je dôvod, prečo veľa testerov appku odložilo** – potrebujú pružnosť (mimo prísneho režimu; prísny režim
je tvoj).

A k tomu chyba **B36**: v Nastaveniach sa systémový budík dá povoliť, ale **nedá sa vypnúť** – riadok len ukazuje
„Zapnutý“. Vypnúť ho ide iba v Nastaveniach iPhonu → SleepHole.

**Dôležitá poznámka k B36:** systémový budík v SleepHole je len **záloha** nášho budíka. Nastaví sa až keď začneš stavbu,
zazvoní 30 s po čase budíka a potvrdením vstávania sa zruší. Bez začatej noci nezazvoní nič. Jej problém
(„nechcem 5:20, keď chcem vstávať 5:45“) teda vypínač sám nevyrieši – zazvonil by náš vlastný budík o 5:20. Rieši ho až
**„dnešný budík“** (návrh B nižšie). Vypínač je napriek tomu správny: čo sa dá zapnúť, musí sa dať aj vypnúť.

## 2. Čo hovorí výskum

* **Pravidelnosť je pre zdravie veľmi dôležitá.** Najväčšia štúdia (Windred a kol., *SLEEP* 2024, 60 977 ľudí z UK
  Biobank, náramky na ruke): ľudia s pravidelnejším spánkom mali o 20 – 48 % nižšie riziko úmrtia než najmenej
  pravidelní, a pravidelnosť predpovedala riziko lepšie než dĺžka spánku. Je to pozorovanie, nie dôkaz príčiny – ale
  jadro SleepHole (pravidelný čas) je správne.
* **Odborný konsenzus** (National Sleep Foundation, *Sleep Health* 2023, 63 prác): pravidelný čas spánku je dôležitý pre
  zdravie aj výkon; ak človek cez pracovné dni nespí dosť, **1 – 2 hodiny navyše vo voľné dni väčšine ľudí pomôžu**.
* **Sociálny jet lag je bežný život** (Roenneberg a kol., vyše 65 000 dospelých): **asi tretina ľudí má rozdiel 2 hodiny
  a viac** medzi pracovnými a voľnými dňami. Appka, ktorá chce jeden čas na všetky dni, zlyhá u veľkej časti ľudí hneď
  v prvý víkend.
* **Liečba nespavosti (CBT-I):** kotvou je **pevný čas vstávania**; do postele sa ide, **keď je človek ospalý**. Pre nás:
  večierka môže byť pružnejšia než budík – a malé posuny budíka (25 min) sú v poriadku, veľké už pravidelnosť rozbíjajú.

## 3. Ako to riešia iní

* **Apple Zdravie (Spánok):** viac rozvrhov – každý pre vybrané dni týždňa (napr. pracovné dni a víkend); **„zmeniť len
  najbližší budík“** – zmena platí jednu noc a potom sa vráti bežný rozvrh; budík jedného rozvrhu sa dá vypnúť bez
  zmazania rozvrhu.
* **SleepTown:** jeden čas večierky a vstávania; **až 2 voľné dni v týždni**, keď zlyhanie ani vynechanie nepreruší sériu.
  Viac sa prispôsobiť nedá (recenzie to vyčítajú).

## 4. Ako je to u nás dnes

| Čo | Dnes |
|---|---|
| Začať stavbu | večierka −10 min … +5 min (okno 15 min); skorý štart od −3 h s potvrdením |
| Budík | pevný z rozvrhu, každú noc rovnaký |
| Vstávanie | potvrdiť od −30 min; úplná noc do +10 min, nedokončená do +60 min |
| Zmena rozvrhu | len v týždni na zmeny (inak 2 000 🪙); zmena po otvorení okna platí od zajtra |
| Voľné noci | nie sú; zmeškaná noc = prerušená séria (zachráni ju len žolík) |
| Systémový budík | záloha pri začatej noci; po povolení sa v appke nedá vypnúť (**B36**) |

Prísny a mierny režim sa dnes líšia len v tom, čo spraví používanie telefónu v noci – časy sú rovnaké.

## 5. Návrhy

| | Návrh | Čo rieši | Riziko podvádzania | Práca |
|---|---|---|---|---|
| **A** | **Vypínač systémového budíka (B36)** – klasický prepínač iPhonu v Nastaveniach: zapnutý = záloha sa nastavuje (ak treba, iOS sa spýta na povolenie); vypnutý = appka žiadny systémový budík nenastaví; zakázaný v iOS = riadok povie, kde ho povoliť | čo sa dá zapnúť, dá sa aj vypnúť | žiadne | malá |
| **B** | **Dnešný budík** – pri začatí stavby (alebo počas prípravy) posunúť budík **len na túto noc**, napr. o ±60 min oproti rozvrhu; ráno sa vráti rozvrh; nepočíta sa ako zmena rozvrhu (týždeň na zmeny sa nemení) | 5:20 / 5:45 druhej testerky; každodenné malé posuny | malé – noc má stále svoj čas a pravidlá; posun je obmedzený | stredná |
| **C** | **Širšie okno na začatie v miernom režime** – napr. večierka −60 min … +60 min namiesto −10 … +5; neskorší štart znamená menej pokojných hodín, teda menej mincí – prirodzená motivácia | večierka, ktorá kolíše („keď som ospalá“) | malé | malá – stredná (pravidlá, testy, sprievodca, zoznam pravidiel) |
| **D** | **Druhý rozvrh pre voľné dni** – ako v Apple Zdraví: vybrané noci (napr. piatok a sobota) majú vlastný čas večierky a budíka; obidva rozvrhy patria pod týždeň na zmeny | víkendy, sociálny jet lag – a stavia sa ďalej | malé | väčšia (model, synchronizácia, sprievodca, nastavenia) |
| **E** | **Voľné noci** – tvoje želanie z 18. 10.: až 2 noci do týždňa bez stavby, séria sa nepreruší (ako SleepTown) | víkendy jednoducho | stredné (nič sa nestavia, ale ani netrénuje) | stredná |
| F | „Len dĺžka spánku“ bez pevných časov | všetko | veľké | – **neodporúčam**: ide proti jadru appky aj proti výskumu |

## 6. Odporúčanie Opus

1. **A (B36) opraviť čo najskôr** – je to chyba, malá a bez rizika.
2. **B + C** spolu tvoria „mierny režim, ktorý unesie bežný život“: prípad druhej testerky (B) aj pohyblivú večierku (C).
   Prísny režim ostáva presne ako dnes – pevné okná, pevný budík.
3. **Víkendy: D namiesto E.** Druhý rozvrh drží zvyk aj cez víkend (výskum: pravidelnosť, ale 1 – 2 h navyše vo voľné
   dni pomôžu) a mestečko rastie ďalej; voľné noci len vypnú appku. E sa dá pridať neskôr, ak ho testeri budú chcieť.
4. **Kam:** všetko je nová funkcia, takže najprv tvoje slovo k zmrazeniu do 1.0. Moja rada: **A + B do buildu 10**
   ako prvé kroky (malé, a B rieši presne dôvod, prečo ľudia odchádzajú); C a D hneď za nimi; štatistiky a reroll
   z dnešného buildu 10 posunúť o build ďalej.

## 7. Otázky pre teba

1. **Vypínač (A):** má vypínať len zálohu ranného budíka, alebo aj varovný budík prísneho režimu na zamknutej obrazovke?
   (Odporúčam len zálohu – varovanie je zmysel prísneho režimu.)
2. **Dnešný budík (B):** o koľko najviac sa smie posunúť – ±30 min, ±60 min? Len skôr, alebo aj neskôr?
3. **Okno (C):** stačí ±60 min? Má platiť len v miernom režime?
4. **Víkendy:** D (druhý rozvrh), E (voľné noci), alebo oboje?
5. **Poradie:** súhlasíš, aby A + B išli do buildu 10 pred štatistikami? A má build 9 aj tak ísť na kontrolu Apple,
   alebo počkať na build s pružnosťou?

## Zdroje

* Windred a kol., Sleep regularity is a stronger predictor of mortality risk than sleep duration, *SLEEP* 47(1), 2024 –
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10782489/
* National Sleep Foundation, Sleep timing and variability consensus, *Sleep Health* 2023 –
  https://www.thensf.org/sleep-schedules-sleep-timing-guideline/
* Roenneberg / Wittmann a kol., social jetlag (prehľad v tlači) – https://healthland.time.com/?p=59335
* CBT-I: kontrola podnetov, pevný čas vstávania – https://pmc.ncbi.nlm.nih.gov/articles/PMC3632369/table/T1
* Apple: Edit sleep schedules in Health on iPhone – https://support.apple.com/guide/iphone/edit-sleep-schedules-iph304a683a0/ios
* Apple: Turn off alarms and delete sleep schedules – https://support.apple.com/guide/iphone/turn-off-alarms-and-delete-sleep-schedules-iph35e7e0e5f/ios
* SleepTown (recenzia TapSmart, voľné dni) – https://www.tapsmart.com/apps/review-sleeptown-fun-way-build-better-sleep-habit/
