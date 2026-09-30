import SwiftUI

/// "Poďakovanie" – credits (owner request 2026-09-30).
struct CreditsView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Kenney").font(.headline)
                    Text(L("All buildings, roads, cars, trees and some sounds come from Kenney Game Assets (CC0 licence). Thank you for the wonderful assets and for giving them to the world. 💛"))
                    Link(destination: URL(string: "https://www.kenney.nl")!) { Text(verbatim: "www.kenney.nl") }
                }
            } header: { Text(L("Graphics and sounds")) }

            Section {
                Text(verbatim: "“Rain on Windows, Interior, A” – InspectorJ (www.jshaw.co.uk), Freesound.org")
                Text(L("Licence CC BY 4.0 – modified (trimmed, crossfaded into a loop). Used as “Rain on a window”."))
                    .font(.footnote).foregroundStyle(.secondary)
                Link(destination: URL(string: "https://freesound.org/s/346642/")!) { Text(verbatim: "freesound.org/s/346642") }
                Link(destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!) {
                    Text(verbatim: "creativecommons.org/licenses/by/4.0")
                }
                Text(L("“Rain on a tent” and all noises are synthesised by SleepHole itself."))
                    .font(.footnote).foregroundStyle(.secondary)
                Text(L("The sound stories are made of Kenney's CC0 sounds (Impact Sounds, RPG Audio, Foley Sounds) and CC0 field recordings from Freesound.org – thank you to their authors (the full list is in the project's CREDITS-freesound.txt)."))
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text(L("Sleep sounds")) }

            Section {
                Text(L("“Morning Mood” – Edvard Grieg, Peer Gynt (1875)"))
                Text(L("“Ode to Joy” – Ludwig van Beethoven, Symphony No. 9 (1824)"))
                Text(L("Both pieces are in the public domain, re-synthesised for SleepHole. “Reveille” and “Alarm!” are original."))
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text(L("Alarm music")) }

            Section {
                Text(L("SleepTown by Seekrtech – the game that showed sleep can build a town."))
            } header: { Text(L("Inspiration")) }

            Section {
                Text(L("Made by Zrebec with help from Claude (Anthropic) 🐰🦊"))
            } header: { Text(L("Authors")) }
        }
        .navigationTitle(L("Credits"))
    }
}
