# Ako spustiť SleepHole na iPhone (bezplatný Personal Team)

## Prvýkrát (asi 10 minút)
1. **Apple ID v Xcode:** Xcode → *Settings…* (⌘,) → *Apple Accounts* → **+** → prihlás sa svojím Apple ID.
   Vznikne tím „*Tvoje Meno (Personal Team)*“.
2. **Otvor projekt:** v termináli `cd ~/Projects/sleephole && xcodegen generate && open SleepHole.xcodeproj`
   (projekt sa generuje z `project.yml`, preto vždy najprv `xcodegen generate`).
3. **Podpisovanie:** vľavo klikni na projekt *SleepHole* → target *SleepHole* → záložka
   **Signing & Capabilities** → *Team* = tvoj **Personal Team**.
   Ak Xcode hlási, že bundle id je obsadený, zmeň *Bundle Identifier* napr. na `sk.zrebec.sleephole2`
   a tú istú hodnotu daj do `project.yml` (`PRODUCT_BUNDLE_IDENTIFIER`).
4. **Pripoj iPhone** káblom a na telefóne potvrď „Dôverovať tomuto počítaču“.
5. Hore v Xcode vyber ako cieľ **svoj iPhone** (nie simulátor) a stlač **▶ Run** (⌘R).
6. **Developer Mode:** pri prvom spustení iPhone vypýta zapnutie – *Nastavenia → Súkromie a bezpečnosť →
   Režim vývojára* → zapni, telefón sa reštartuje, potvrď.
7. **Dôvera vývojárovi:** ak appka nechce naštartovať („Nedôveryhodný vývojár“):
   *Nastavenia → Všeobecné → Správa VPN a zariadení* → tvoje Apple ID → **Dôverovať**.
8. Spusti znova ▶ Run. Na obrazovke **Dnes** má byť „Načítaných spritov: 174“ a štyri budovy.

## Každých 7 dní
Bezplatný podpis vyprší po 7 dňoch (appka sa prestane otvárať). Pripoj iPhone, otvor projekt a daj
**▶ Run** – dáta v appke ostanú zachované.

## Pre istotu
- Nastav si na iPhone **kód na odomknutie** – appka ho potrebuje na rozlíšenie zamknutia telefónu.
- Voliteľne: `sudo xcode-select -s /Applications/Xcode.app` (aby príkazy `xcodebuild` v termináli
  používali Xcode namiesto Command Line Tools).
