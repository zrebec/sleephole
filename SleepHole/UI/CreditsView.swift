import SwiftUI

/// "Poďakovanie" – credits (owner request 2026-09-30).
struct CreditsView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kenney").font(.headline)
                    Text("Všetky budovy, cesty, autá, stromy a časť zvukov pochádzajú z Kenney Game Assets (licencia CC0). Ďakujeme za nádherné assety a za to, že ich Kenney dáva svetu. 💛")
                    Link("www.kenney.nl", destination: URL(string: "https://www.kenney.nl")!)
                }
            } header: { Text("Grafika a zvuky") }

            Section {
                Text("„Rain on Windows, Interior, A“ – InspectorJ (www.jshaw.co.uk), Freesound.org")
                Text("Licencia CC BY 4.0 – upravené (orezané, zmiešané do slučky). Použité ako „Dážď na okno“.")
                    .font(.footnote).foregroundStyle(.secondary)
                Link("freesound.org/s/346642", destination: URL(string: "https://freesound.org/s/346642/")!)
                Link("creativecommons.org/licenses/by/4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                Text("„Dážď na stan“ a všetky šumy sú syntetizované priamo v SleepHole.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Zvuky na zaspávanie") }

            Section {
                Text("„Ranná nálada“ – Edvard Grieg, Peer Gynt (1875)")
                Text("„Óda na radosť“ – Ludwig van Beethoven, 9. symfónia (1824)")
                Text("Obe skladby sú voľné dielo, v SleepHole nanovo syntetizované. „Budíček“ a „Poplach“ sú vlastné skladby.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Hudba budíkov") }

            Section {
                Text("SleepTown od Seekrtech – hra, ktorá ukázala, že spánok môže byť stavba mesta.")
            } header: { Text("Inšpirácia") }

            Section {
                Text("Vytvoril Zrebec s pomocou Clauda (Anthropic) 🐰🦊")
            } header: { Text("Autori") }
        }
        .navigationTitle("Poďakovanie")
    }
}
