# Build 9 – čo otestovať

Pre majiteľa, 18. 10. 2026. Platí pre celý build 9 (9a–9f) na tvojom telefóne (Debug build z Macu, číslo buildu sa
zmení na 9 až pri nahratí). Tvoje mesto, mince, séria aj žolíky ostávajú – inštalácia ide cez starú appku, nič sa
nemaže.

## Čo môžem otestovať hneď

1. **Nový sprievodca (9c):** Nastavenia → „Ako to funguje" (otvorí sprievodcu znova). Je to 9 strán, na každej rozpráva
   mačka v bubline. Na žiadnej strane by sa nemalo nič rolovať. Pozri hlavne stranu 6 („Chceš si prečítať správu? Ťukni na
   🌙 Pauza…") a stranu 9 s tlačidlom „Všetky pravidlá". Pri opakovanom spustení sú časy na strane 2 sivé – rozvrh sa
   mení v Nastaveniach (tak to má byť).
2. **Všetky pravidlá (9c):** Nastavenia → „Ako funguje SleepHole". Desať skupín pravidiel, všetky čísla idú priamo z kódu.
   V skupine „Noc" je nové pravidlo o Centre hlásení; na konci sú „Tipy".
3. **Čas na prípravu (9b):** Nastavenia → hneď pod rozvrhom „Čas na prípravu" 5 / 10 / 15 min. Predvolene 5 min – nechaj
   tak, ak nechceš inak. Zmena platí od najbližšieho štartu (nie je viazaná na týždeň na zmeny) a na Dnes sa podľa nej
   zmení veta „Na prípravu máš čas do …".
4. **Tab bar a detail noci (9f):** ak bude spodná lišta plná (nie priesvitná sklenená), je to oprava B15; detail noci v
   Štatistikách by sa po otvorení nemal schovať pod hornú lištu.
5. **Odpočinok:** ako zvyčajne. Počas odpočinku nič neinštalujem.

## Čo musím otestovať dnes ostrej noci

1. **Štart a príprava:** „Ísť spať" ako vždy; príprava trvá podľa nastavenia (pri 5 min do 21:35).
2. **Nič sa nemení na pravidlách noci** – len návrat do appky sa počíta o ~0,8s skôr (9a, v tvoj prospech, nič neuvidíš).
   Pri včasnom návrate po upozornení má vibrácia „uff" prísť ako doteraz.
3. **Ráno pri budíku (B26):** zdvihni zvoniaci telefón ako vždy (Face ID, odomknutie, kód alebo zatrasenie). V príbehu noci
   (Štatistiky → noc) už nemá byť „telefón použitý na zamknutej obrazovke" z chvíle po budíku.
4. **Výsledok noci:** pokojné hodiny ako doteraz (pri 5 min príprave 21:35–05:35 = 8 hodín).
5. **Centrum hlásení nesťahuj** – stále je to odchod z appky (to sa nemení, len to už hovorí sprievodca aj pravidlá).

Ráno mi nič neposielaj – denník si stiahnem sám (len čítam) a porovnám s tým, čo si videl.
