# SleepHole – čo môže Apple spochybniť a ako sa dostať na review

Stav k 12. 10. 2026. Rozbor k položke 8 z [`PREHLAD-PLANOV.md`](PREHLAD-PLANOV.md). Návody, na ktoré nadväzuje, máš
v iCloude: `SleepHole/APPSTORE-NAVOD.md` (texty a polia) a `SleepHole/TESTFLIGHT-NAVOD.md` (nahratie, testeri).

## Verdikt v skratke

- **Ľahšia kontrola (Beta App Review) appku pustila dvakrát.** Zostavenia 2 aj 4 sú v externej skupine v stave
  „Testing". Je to dobrý signál, nie záruka – kontrola pre App Store je prísnejšia.
- **Skutočné riziká sú tri:** nezdokumentované signály zámku, zvuk na pozadí v tichu a to, že kontrolór nevie,
  ako uvidieť celú noc. K tomu jedna vec, ktorá s istotou chýba: odkaz na zásady súkromia priamo v appke.
- **Ani jedno nie je slepá ulička.** Pre signály zámku existuje záložná cesta len so zdokumentovanými signálmi.
  Podľa záznamov z Tvojho telefónu je lacnejšia, než plán doteraz tvrdil.
- **Odporúčanie:** malé zostavenie 5 (bez nových funkcií), potom podať do App Store s **ručným vydaním**. Schválenie
  tak appku nezverejní a skutočnú odpoveď Applu budeš mať do pár dní, nie až na konci.

## Čo som overil

| Čo | Výsledok |
|---|---|
| Ostré zostavenie 4 (archív z 12. 10.) | Obsahuje **7** názvov `com.apple.…`. Appka používa 3. Zvyšné 4 patria vývojárskemu laboratóriu zamknutej obrazovky, ktoré sa v ostrom zostavení nedá spustiť. V binárke sú aj vývojárske obrazovky (nedosiahnuteľné). |
| Zamietnutie v minulosti | Apple zamietol appku presne za `lockcomplete` a `lockstate` podľa pravidla 2.5.1 (vlákno z roku 2018, Apple v ňom žiadnu náhradu neponúkol). |
| Záznamy z Tvojho telefónu (iOS 27; 29. 9. aj 9. 10.) | Zdokumentovaný signál zámku prichádza **o 0,05 až 0,15 s skôr** než nezdokumentovaný. Komentár v kóde, že mešká asi 10 s, neplatí. |
| Predvolený zvuk novej inštalácie | Hnedý šum celú noc. Pri kontrole teda appka naozaj počuteľne hrá. |
| Odkaz na zásady súkromia v appke | **Nie je.** Pravidlo 5.1.1 ho žiada v obchode aj v appke. |
| Dĺžka noci | Nemá minimum. Kontrolór vie prejsť celú noc za asi 15 minút (večierka o 3 min, budíček o 15 min). Treba to raz vyskúšať na čistej inštalácii. |
| Text povolenia pre systémový budík a poznámky pre kontrolu | Hovoria len o záložnom budíku. Prísny režim ho používa aj ako výstrahu – to v nich chýba. |

## Riziká

| # | Čo | Pravidlo | Riziko | Čo s tým |
|---|---|---|---|---|
| 1 | Signály zámku `com.apple.springboard.*` | 2.5.1 | **vysoké** – jediné s doloženým zamietnutím | A: vyhodiť z ostrého zostavenia 4 laboratórne názvy a vývojárske obrazovky. B: mať pripravenú záložnú detekciu. Podrobne nižšie. |
| 2 | Zvuk na pozadí, keď je ticho | 2.5.4 | stredné | Vysvetlenie v poznámkach (je), predvolený zvuk hrá (je). Pri zamietnutí najprv odpoveď, až potom zmena. |
| 3 | Kontrolór neuvidí celú noc | 2.1 | stredné | Recept „noc za 15 minút" do poznámok a krátke video. |
| 4 | Odkaz na zásady súkromia chýba v appke | 5.1.1 | **isté**, ak si to kontrolór pozrie | Riadok v Nastavenia → O aplikácii. Potrebuje adresu stránky. |
| 5 | Systémový budík ako výstraha v Prísnom režime | 2.5.1, 2.3.1 | nízke až stredné | Doplniť text povolenia a poznámky pre kontrolu. |
| 6 | Appka len pre iPhone spustená na iPade | 2.4.1 | nízke až stredné | Kontrolóri to skúšajú. Jedna skúška v simulátore iPadu. |
| 7 | Apple Zdravie | 2.5.1, 5.1.3 | nízke | Popis ho spomína, údaje nejdú do iCloudu, zásady to hovoria – všetko je v návrhoch. |
| 8 | Skryté príkazy pri spustení (odpustenie noci a pod.) | 2.3.1 | nízke | Používateľ ich zadať nevie. Zavrieť do vývojárskeho zostavenia spolu s bodom 1A. |
| 9 | Podobnosť so SleepTown | 4.1 | nízke | Vlastná grafika aj pravidlá. V obchode nikde nespomínať cudzie appky. |
| 10 | Zdravotné sľuby | 1.4.1 | nízke | Návrhy textov ich nemajú a hovoria „nie je merač spánku". |
| 11 | Štítok súkromia „Data Not Collected" | 5.1.2 | nízke | Súradnice vybraného mesta idú službe počasia. Zásady to priznávajú. |
| 12 | Platená appka: zmluva, banka, dane, obchodník v EÚ | – | brzdí vydanie, nie kontrolu | Tvoje kroky v App Store Connect. Začni nimi, spracovanie trvá dni. |

## Riziko 1 podrobne: signály zámku

iOS nemá verejný spôsob, ako sa appka dozvie „telefón sa zamkol" alebo „displej svieti". Appka preto počúva tri
systémové oznámenia, ktoré Apple nezdokumentoval. Funkcia, ktorou ich počúva, verejná je; názvy nie.

| Signál | Na čo ho appka potrebuje | Zdokumentovaná náhrada | Čo by sa stratilo |
|---|---|---|---|
| `lockcomplete` | rozlíšiť „zamkol som telefón" od „odišiel som z appky" | oznámenie o zamknutí údajov – na Tvojom telefóne rovnako rýchle | telefón **bez kódu zámku** tento signál nemá: appka by tam odchody nevedela rozlíšiť a rozhodla by v prospech človeka |
| `lockstate` | „odomkol som a nevrátil sa do appky" | oznámenie o odomknutí údajov + appka do 5 s nie je aktívna | nič podstatné |
| `hasBlankedScreen` | displej svieti na zamknutej obrazovke (Fotoaparát) – pravidlá 8 s a 12 s | **žiadna** | jemná pripomienka aj siréna Prísneho režimu na zamknutej obrazovke; fotenie zo zamknutej obrazovky by appka nevidela |

**Krok A (malý, bez zmeny správania):** z ostrého zostavenia vyhodiť štyri laboratórne názvy, vývojárske obrazovky
a príkazy pri spustení. Tebe vo vývojárskom zostavení z Macu ostane všetko. Namiesto siedmich názvov ostanú tri
a každý má v poznámkach pre kontrolu svoje vysvetlenie.

**Krok B (stredný): záložná detekcia len so zdokumentovanými signálmi.** Prepínač pri zostavení, nie nová funkcia.
Meranie je zatiaľ z jedného telefónu – pred nasadením ho treba zopakovať aspoň na jednom ďalšom zariadení.

**Čo nerobiť:** názvy v kóde skrývať (skladať ich z kúskov, šifrovať). Je to vedomé klamanie kontroly a Apple za
to podľa vlastných pravidiel môže zrušiť celý vývojársky účet.

Dve cesty, rozhodnutie je Tvoje:

- **(a) Podať s tromi signálmi a s priznaním v poznámkach; krok B postaviť, kým Apple kontroluje.** Ak prejde,
  Prísny režim aj pripomienka ostávajú. Ak neprejde, prepneme a podáme znova do dňa. Odporúčam túto.
- **(b) Krok B hneď a podať úplne bez nezdokumentovaných názvov.** Najistejšie voči Applu. Cena: Prísny režim
  stratí zamknutú obrazovku hneď v 1.0 a fotenie zo zamknutej obrazovky sa nebude dať zistiť.

Pri ceste (a) ostáva jedna vec, ktorú treba povedať nahlas: schválenie verzie 1.0 nezaručuje ďalšie verzie. Preto
má krok B zmysel postaviť aj vtedy, keď 1.0 prejde – ako poistku v zásuvke.

## Riziko 2 podrobne: zvuk na pozadí

Pravidlo hovorí, že zvuk na pozadí je pre appky, ktoré používateľovi niečo počuteľne prehrávajú. Appka v noci
prehráva zvuky na spanie a ráno zvoní budíkom – to účel spĺňa. Slabé miesto je voľba „Ticho" a čas po vypršaní
časovača: vtedy beží zvuková relácia bez zvuku, aby appka videla odchody a ráno zazvonila.

- Dnes: poznámky pre kontrolu to priznávajú, predvolený zvuk hrá celú noc a voľba „Ticho" to hovorí aj
  používateľovi („appka ostáva v noci hore").
- Ak to Apple zamietne: najprv odpoveď v Resolution Center (zvuky na spanie a budík sú prehrávanie zvuku).
- Až potom zmena. Úplne bez zvuku na pozadí by appka potrebovala prerobiť jadro (budík cez systémový budík,
  odchody vyhodnotené až pri návrate). To je veľká práca a nerobil by som ju vopred.

## Ako to dostať na review

Kontroly sú dve. **Beta App Review** už prebehla (externá skupina). **App Review** príde pri podaní verzie do App
Store. Pri podaní zvoľ **„Manually release this version"**: po schválení ostane appka v stave „Pending Developer
Release" a zverejníš ju, až keď budeš chcieť. Apple po 30 dňoch pošle pripomienku; lehotu, po ktorej by schválenie
prepadlo, neuvádza.

| # | Krok | Kto | Veľkosť |
|---|---|---|---|
| 1 | Kompaktná obrazovka Dnes | worker, Ty skontroluješ | S – rozrobené 12. 10. |
| 2 | Zmluva o platených appkách, banka, dane, obchodník v EÚ | Ty | Tvoje kliky; spracovanie trvá dni |
| 3 | Tri rozhodnutia: kde bude stránka so zásadami, ktorý kontakt je verejný, podtitul | Ty | 10 minút |
| 4 | Stránka so zásadami a podporou (po anglicky a po slovensky) | pripravím | S |
| 5 | Zostavenie 5: odkaz na zásady v appke, krok A, text povolenia pre systémový budík | worker | S |
| 6 | Skúšky: appka v simulátore iPadu; recept „noc za 15 minút" na čistej inštalácii | worker + Ty | S |
| 7 | Snímky obrazovky 6,9" po anglicky a po slovensky | worker, Ty vyberieš | S |
| 8 | App Store Connect: texty, kategória, vek, štítok súkromia, cena, poznámky pre kontrolu, zostavenie 5, ručné vydanie, **Submit** | Ty, prejdeme spolu | 30 – 45 minút |
| 9 | Kým Apple kontroluje: krok B do zásuvky | worker | M |

Kroky 2 a 3 môžeš robiť hneď, nezávisia od kódu. Položky POP, kalendár a slovenské texty pre všetkých sa dajú
doplniť do toho istého podania, ak budú hotové skôr než krok 8 – alebo prídu ako ďalšie zostavenie.

## TestFlight: zostavenie 2

Zostavenie sa nedá zmazať, dá sa mu ukončiť testovanie (zostavenie → **Expire Build**). Apple píše len toľko, že
sa potom nedá nainštalovať. Čo sa stane s už nainštalovanou kópiou, neuvádza a neoveroval som to.

Bezpečné poradie: tester v externej skupine najprv prejde na zostavenie 4 (pri zostavení 4 zatiaľ nie je žiadne
spustenie, pri zostavení 2 ich je 14), až potom zostaveniu 2 ukonči testovanie.

## Poznámky pre kontrolu – čo doplniť

Text v `TESTFLIGHT-NAVOD.md` (časť 5) je dobrý základ. Pre App Store do neho treba doplniť:

1. **Celá noc za 15 minút:** večierka o 3 minúty, budíček o 15 minút; „Go to sleep"; po príprave zamknúť telefón;
   pri budíku zatriasť alebo zadať kód z Nastavení; budova pribudne na karte Mesto. Vložiť až po skúške.
2. **Prísny režim:** je vypnutý; kto si ho zapne, tomu pri používaní zamknutej obrazovky zazvoní krátka výstraha
   cez systémový budík.
3. **Skorší štart noci** (od zostavenia 4) a že pohyb telefónu sa číta len pri rozsvietenej zamknutej obrazovke.
4. Odkaz na krátke video celej noci.

## Čo potrebujem od Teba

1. Cesta **(a)** alebo **(b)** pri signáloch zámku.
2. Súhlas so zostavením 5 v rozsahu kroku 5 (žiadna nová funkcia).

Rozhodnuté 12. 10.: stránka podpory a zásad bude na GitHube (obsah je v priečinku `site/`, zverejní ho
`.github/workflows/pages.yml`), verejný kontakt je na nej uvedený, podtitul je „Sleep on time, grow a town".
Anglické texty na vloženie do App Store Connect sú v iCloude: `SleepHole/APPSTORE-TEXTY-EN.md`.

## Zdroje

- Apple, pravidlá kontroly: developer.apple.com/app-store/review/guidelines (2.1, 2.3.1, 2.5.1, 2.5.4, 5.1.1, 5.1.3)
- Zamietnutie za `lockcomplete` a `lockstate`: developer.apple.com/forums/thread/106982
- Ručné vydanie verzie: developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option
- Ukončenie testovania zostavenia: developer.apple.com/help/app-store-connect/test-a-beta-version/stop-testing-a-build
