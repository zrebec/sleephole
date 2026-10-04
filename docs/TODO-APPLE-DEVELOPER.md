# TO-DO: Apple Developer Program (platený účet)

> **Stav 4. 10. 2026 večer:** členstvo je aktívne a potvrdené podpísaným zostavením s funkciou plateného účtu
> (upozornenia cez Sústredenie). Team ID sa nezmenil, takže bundle id aj dáta appky ostávajú. Xcode to videl až po
> reštarte. Profil platí do 4. 10. 2027. Hotové z časti B: Time Sensitive Notifications. Ostáva AlarmKit (fáza F6b),
> neskôr HealthKit a TestFlight.

Cena: **99 USD / rok** (v eurozóne Apple účtuje približne **99 €** vrátane DPH, presná suma sa ukáže pri platbe).
Registruješ sa ako **Individual** (fyzická osoba), bez firmy.

## A. Registrácia (ty, asi 15 minút, potom čakanie)
- [x] Na iPhone si nainštaluj z App Storu appku **Apple Developer**.
      Najrýchlejšia cesta: registrácia aj overenie totožnosti prebehnú priamo v telefóne.
- [x] Skontroluj, že Apple ID má zapnuté **dvojfaktorové overenie**
      (Nastavenia → tvoje meno → Prihlásenie a zabezpečenie).
- [x] V appke Apple Developer: **Účet → Zaregistrovať sa** (Enroll now) → **Individual**.
- [x] Vyplň **skutočné meno a adresu**, rovnaké ako v doklade (Apple ich kontroluje).
- [x] Ak si to Apple vypýta, **naskenuj občiansky preukaz** (fotka dokladu a tváre).
- [x] **Zaplať** kartou priamo v appke. Platba je cez Apple ID.
- [x] Počkaj na email **„Welcome to the Apple Developer Program“**. Zvyčajne príde do 24–48 h, niekedy do pár hodín.
- [ ] Na [developer.apple.com/account](https://developer.apple.com/account) sa prihlás a **potvrď zmluvy** (Agreements), ak nejaké čakajú.
- [x] Pošli mi **Team ID** (10 znakov). Nájdeš ho v developer.apple.com → Membership details.

## B. Prepnutie projektu (ja, keď bude účet aktívny)
- [x] **Záloha dát z telefónu** (denník nocí, mesto, nastavenia) cez `devicectl`, ešte pred prepnutím.
- [x] Nový `DEVELOPMENT_TEAM` do `project.yml`. Xcode vytvorí profil na **1 rok**.
- [x] Ak Apple nedovolí ponechať bundle id `sk.zrebec.sleephole` (patrí k Personal Teamu),
      použijem nové id a **zálohu vrátim** do nového kontajnera appky (`devicectl device copy to`).
      Dáta sa nestratia.
- [x] Zapnem **Time Sensitive Notifications**: upozornenia „Vráť sa“ a budík prebijú Sústredenie.
- [ ] **AlarmKit**: systémový budík, ktorý zazvoní aj po reštarte iOS. Overím, či treba o oprávnenie požiadať Apple (formulár).
- [ ] **HealthKit** (neskôr): skutočný čas zaspatia a fázy spánku z Apple Watch.
- [ ] Voliteľne **TestFlight**: inštalácia bez kábla a automatické aktualizácie.

## C. Kým čakáme
- Bezplatná verzia, nainštalovaná 29. 9., vyprší **okolo 6. 10.** Ak účet nebude aktívny, stačí raz pripojiť iPhone a spustiť ▶ Run.
- Appka funguje bežne ďalej. Platený účet mení iba „kto ju podpisuje“ a čo smie.
