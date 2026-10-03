# SleepHole – čo ďalej: zvieratká, spáč a živé mesto

*Návrh na večerné čítanie · 2. 10. 2026 · napísal Claude pre majiteľa appky*

---

## 1. Kde sme dnes

| Fáza | Stav |
|---|---|
| A, F0–F2 | ✅ assety, appka v iPhone, noc a detekcia |
| F3 mesto, F4 levely/štatistiky | ✅ hotové, čaká sa na reálne noci |
| I18N, LIM | ✅ |
| **UI** (obloha, sklo, ostrovček, efekty, hlas, téma, žolíky, mince podľa levelu) | ✅ postavené, **čaká na tvoj test** |
| **Pauza v noci (D17)** | rozhodnuté, nepostavené |
| F5 živé mesto | ⬜ |
| R&D centrum / obchod | otvorené |
| F6 platený Apple účet | neskôr |
| F7 nové budovy | neskôr |

## 2. Tvoje odpovede (2. 10.)

1. **Mesto + zvieratká, bez lesa.**
2. Zvieratká majú odrážať **pravidelnosť** a **nerušené noci**.
3. Interakcia: **občas niečo ťukne**. Žiadne povinnosti ani tresty.
4. **Spáč áno**: jedno zvieratko spí s tebou na nočnej obrazovke.

### Čo z toho vyplýva

- Mesto ostáva „hlavnou postavou“. Les som nezahodil, je odložený v kapitole 7.
- **Pravidelnosť** už appka meria (rozptyl začiatku noci za 14 nocí, napr. „±12 min“). Netreba nič nové, len to použiť.
- **Nerušená noc** potrebuje pauzu (D17). Bez pauzy sa „nerušená“ nedá definovať férovo, lebo každý krátky odchod by ju pokazil. **Pauza preto musí byť pred zvieratkami.**
  - Navrhovaná definícia: *nerušená noc = hotová noc bez použitej pauzy.* Pozretie na hodiny (odomknutie a hneď návrat) sa nepočíta. Je to v duchu „nikdy kruto“.
- „Občas ťukne“ znamená: zvieratko pohladkáš (srdiečka + zvuk), pozrieš si jeho kartu (meno, kedy prišlo, prečo prišlo) a vyberieš si spáča. Nič viac.
- **Spáč** je najsilnejšie prepojenie so spánkom: zvieratko robí to isté, čo ty.

### Overené obmedzenia

- **Cube Pets nemajú animácie.** Pohyb robíme sami: poskakovanie (stlačenie a natiahnutie), otáčanie a pohyb po bunkách ako autá. Kockatým zvieratkám to sedí.
- **Spiace zvieratko**: Cube Pets nemajú zavreté oči. Vyrenderujem ich „na boku“ (renderer treba naučiť náklon modelu, malá zmena), plus dýchanie a „Zzz“. Prípadne čiapočku na spanie z kociek.
- **Nočné zvieratá** (sova, ježko, netopier) v Kenney nie sú. Ako vzácnych hostí preto použijeme exotiku z Cube Pets (panda, koala, tučniak…).
- Zvieratká **nikdy neodídu** (nikdy kruto). Pri nepravidelnom spánku sú len ospalé.

---

## 3. Spoločné stavebné kamene

Všetky tri plány sa skladajú z týchto blokov, líšia sa rozsahom a poradím.

### 🌙 Pauza (D17)
- Tlačidlo „🌙 Pauza“ na nočnej obrazovke až **po skončení prípravy**, 10 min.
- 1. pauza zadarmo, potom 50 / 100 / 150 🪙…
- Noc bez pauzy dáva **+30 🪙**.
- Odpočinok pauzu nemá.
- Odhad: **1 sedenie**.

### 😴 Spáč (sleep buddy)
- Vyberieš si zvieratko spomedzi tých, ktoré sa už nasťahovali. Na začiatku dostaneš kuriatko.
- **Večer** sa uloží na stavenisko vedľa žeriava a dýcha.
- **V noci** drieme. Ak odídeš z appky, prebudí sa a pozerá na dvere. Keď sa vrátiš, radostne poskočí.
- **Ráno** sa pri budíku natiahne a vyskočí. Pri WOW tancuje.
- Na obrazovke Dnes sedí na ostrovčeku.
- Odhad: **1–2 sedenia** (render pozícií + animácie).

### 🐾 Obyvatelia (Cube Pets v meste)
Zvieratká sa sťahujú podľa pravidiel, ktoré merajú to, čo chceš:

| Zvieratko | Kedy príde | Čo meria |
|---|---|---|
| 🐥 Kuriatko | prvá postavená budova | začiatok |
| 🐰 Zajac | 3 hotové noci v rade | séria |
| 🐱 Mačka | 5 nerušených nocí (spolu) | nerušené noci |
| 🐶 Pes | pravidelnosť do ±15 min za 14 nocí | pravidelnosť |
| 🦊 Líška | 7 nerušených nocí v rade | nerušené noci |
| 🦌 Jeleň | 10 nocí začatých do 10 min od večierky | pravidelnosť |
| 🐝 Včela | 5 hotových odpočinkov | odpočinok |
| 🦫 Bobor | prvý park s jazierkom | mesto |
| 🐄🐷 Krava, prasa | 10 rodinných domov | mesto |
| 🐼 Vzácny hosť | **mesiac s pravidelnosťou do ±15 min** → raz za mesiac príde exotika (panda, koala, tučniak, papagáj…) | dlhodobá pravidelnosť |

- Zvieratká sa prechádzajú po tráve a chodníkoch blízko svojho „domova“ (park alebo dom).
- Po ťuknutí ukážu kartu s menom, dátumom príchodu a dôvodom, a dajú sa pohladkať.
- **Album obyvateľov** v Štatistikách: siluety tých, čo ešte neprišli, s nápovedou, čo treba spraviť.
- Odhad: **2–3 sedenia** (SleepCore pravidlá + render 4 smerov + pohyb v SpriteKit + album).

### 🌗 Živé mesto (pôvodné F5)
- Mesto sa tónuje podľa dennej doby (logika oblohy `Sky` je hotová).
- V noci svietia lampy a okná.
- Po cestách jazdia autá.
- Zvieratká v noci spia pri svojom domove.
- Odhad: **2 sedenia**.

### 🍂 Ročné obdobia
- Kenney má stromy v letnej, tmavej a **jesennej** farbe, takže jeseň je takmer zadarmo.
- Zima: sneh na strechách a zemi (prefarbenie dlaždíc) a ľadový medveď ako zimný hosť.
- Odhad: **1–2 sedenia**.

### 🏛️ R&D / obchod s balíčkami
- Budovy aj zvieratká v **balíčkoch** (3–5 variantov naraz), aby mesto nebolo jednotvárne.
- Vyšší level platí viac (už platí).
- Odhad: **2 sedenia** a rozhodovanie s tebou.

---

## 4. Plán A – „Spáč a obyvatelia“ ⭐ odporúčam

**Myšlienka:** najprv to, čo spája hru so spánkom (pauza, spáč, zvieratká za pravidelnosť), potom oživenie mesta. Každá fáza sa dá otestovať jednou nocou.

| # | Fáza | Čo uvidíš | Sedenia |
|---|---|---|---|
| 1 | **Pauza (D17)** | tlačidlo Pauza, +30 🪙 za nerušenú noc, pauzy v príbehu noci | 1 |
| 2 | **Spáč** | kuriatko s tebou spí na nočnej obrazovke, ráno sa zobudí | 1–2 |
| 3 | **Obyvatelia I** | zvieratká sa sťahujú do mesta podľa pravidiel, prechádzajú sa, dajú sa pohladkať | 2 |
| 4 | **Album + výber spáča** | album obyvateľov, spáčom môže byť ktokoľvek z mesta, vzácny hosť mesiaca | 1 |
| 5 | **Živé mesto (F5)** | deň a noc v meste, lampy, okná, autá, zvieratká v noci spia | 2 |
| 6 | *voliteľne* **Jeseň a zima** | sezónne stromy, sneh | 1–2 |

- **Spolu:** 7–9 sedení, rozložiteľných na 2–3 týždne podľa tvojej energie.
- **Riziko:** malé. Mesto ostáva, nič sa neprepisuje a staré noci sa automaticky premietnu (zvieratká, ktoré si si už zaslúžil, prídu hneď).
- **Prečo odporúčam:**
  - spáč dáva dôvod mať appku večer otvorenú,
  - zvieratká odmeňujú presne pravidelnosť a nerušené noci,
  - všetko je „nikdy kruto“.

## 5. Plán B – „Mesto s náladou“ (väčší)

**Myšlienka:** plán A plus **nálada mesta a malé príbehy**. Mesto reaguje na to, ako spíš, a obyvatelia majú drobné želania.

Navyše oproti A:
- **Nálada mesta** podľa pravidelnosti za 14 nocí:
  - **±15 min**: slnečno a zvieratká sa hrajú,
  - **±30 min**: bežný deň,
  - **horšie**: hmla a zvieratká driemu cez deň.
  - Nikdy nič nezmizne, mesto je len ospalé.
- **Ranné noviny**: po potvrdení „Vstal som“ krátka karta, napríklad „Líška dnes v noci prespala celú noc v parku. Mesto je pokojné (±12 min).“
- **Želania obyvateľov**: „Bobor by chcel jazierko“. Ak sa nočná budova trafí do želania, dostaneš bonus. Prepája sa to s **R&D balíčkami**, keďže si môžeš vyvinúť, čo si zvieratká želajú.
- **Ročné obdobia** natrvalo a sviatky (Vianoce: stromček na námestí).

| # | Fáza | Sedenia |
|---|---|---|
| 1–5 | ako plán A | 7–8 |
| 6 | Nálada mesta + ranné noviny | 2 |
| 7 | R&D balíčky (budovy aj zvieratká) | 2 |
| 8 | Želania obyvateľov | 2 |
| 9 | Ročné obdobia + sviatky | 2 |

- **Spolu:** 15–16 sedení.
- **Riziko:** stredné. Viac pravidiel na vysvetlenie a R&D ešte treba doladiť (cena, balíčky).
- Hodí sa, ak SleepHole raz pôjde do App Store, lebo má „hĺbku“ na mesiace.

## 6. Plán C – „Rýchla radosť“ (najmenší)

**Myšlienka:** čo najrýchlejšie niečo milé, potom platený účet a systémové veci.

| # | Fáza | Sedenia |
|---|---|---|
| 1 | Pauza (D17) | 1 |
| 2 | Spáč (iba kuriatko alebo mačka, bez výberu) | 1 |
| 3 | Dekoratívne zvieratká: 1 zvieratko na každých 5 postavených nocí, náhodné druhy, prechádzajú sa, bez pravidiel a albumu | 1 |
| 4 | F6 platený účet: AlarmKit (budík prežije aj reštart iOS), dôležité notifikácie, TestFlight | 1–2 |
| 5 | Widget a Live Activity so spáčom na zamknutej obrazovke *(overiť, čo dovolí bezplatný účet)* | 2 |

- **Spolu:** 6–7 sedení.
- **Riziko:** malé, ale zvieratká **nemerajú** pravidelnosť ani nerušené noci, takže to je skôr ozdoba než motivácia.
- Platený účet (99 €/rok) je tvoje rozhodnutie.

---

## 7. Odložené: les (aby sa nápad nestratil)

Ak sa raz vrátime k lesu, takto by som ho spravil. Kenney na to má všetko:
- **Noc zasadí semienko.** Strom rastie viac nocí za sebou: malá borovica → stredná → vysoká. **Rast = séria.**
- **Odpočinok polieva**: dážď nad lesom, kvety, huby.
- **Nevydarená noc** nič nespáli. Strom spadne a vznikne **kmeň s hubami**, ktorý je tiež súčasťou ekosystému. Nikdy kruto.
- **Biómy podľa levelov:**
  - lúka (zajac, včela),
  - les a rieka (jeleň, líška, bobor),
  - sneh (ľadový medveď, tučniak),
  - džungľa (lev, žirafa, papagáj).
- Mesto by ostalo ako „dedinka na okraji lesa“.

Pre tento rozsah je to podľa mňa nová hra (8+ sedení). Mesto je jednoduchšie pochopiteľné, ako si sám povedal.

---

## 8. Moje odporúčanie a otázky na zajtra

**Odporúčam plán A.** Je to najkratšia cesta k tomu, čo si vybral: spáč, zvieratká za pravidelnosť a nerušené noci, len ťukanie a nič kruté. Keď to bude fungovať, z plánu B sa dá kedykoľvek pridať nálada mesta, noviny a želania. Nič z plánu A sa nezahodí.

Pred štartom potrebujem od teba:
1. **Ktorý plán** (A / B / C, alebo mix)?
2. **Definícia nerušenej noci**: stačí „bez pauzy“, alebo aj „bez pozerania na mobil“ (odomknutie s návratom)? Ja odporúčam iba „bez pauzy“, pozretie na hodiny je ľudské.
3. **Prvý spáč**: kuriatko (príde s prvou budovou), alebo si ho vyberieš hneď zo všetkých?
4. **Mená zvieratiek**: automatické (Mia, Bobo, Ferko…), alebo ich pomenuješ sám?
5. Má **vzácny hosť mesiaca** chodiť naozaj iba za ±15 min, alebo je to prísne?

*Náhľady zvieratiek:* `docs/previews/animals_in_town.png` a `docs/previews/animals_cube_pets.png` v repozitári.
