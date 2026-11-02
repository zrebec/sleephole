import Foundation
import Testing
@testable import SleepCore

/// Step 11b5a: every postcard has a source on an allowed authority's https page.
@Suite struct PostcardsTests {
    @Test func theTableCoversExactlyTheCatalog() {
        #expect(Set(Postcards.sources.keys) == Set(BoxCatalog.ids(.postcard)))
        #expect(Postcards.sources.count == 30)
        #expect(Postcards.source(for: "postcard-07") != nil)
        #expect(Postcards.source(for: "postcard-31") == nil)
    }

    @Test func everyUrlIsHttpsOnAnAllowedDomain() throws {
        for (id, s) in Postcards.sources {
            #expect(!s.name.trimmingCharacters(in: .whitespaces).isEmpty, "\(id)")
            let url = try #require(URL(string: s.url), "\(id)")
            #expect(url.scheme == "https", "\(id)")
            let host = try #require(url.host, "\(id)")
            #expect(Postcards.allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }, "\(id): \(host)")
            #expect(url.path.count > 1, "\(id) points to a page, not a home page")
        }
    }

    @Test func noTwoPostcardsShareAPageAndAName() {
        // a page may back a few tips, but never more than ten of them (a spread of sources)
        let byUrl = Dictionary(grouping: Postcards.sources.values, by: \.url)
        #expect(byUrl.values.allSatisfy { $0.count <= 10 })
        let byName = Dictionary(grouping: Postcards.sources.values, by: \.name)
        #expect(byName.values.allSatisfy { $0.count <= 11 }, "\(byName.mapValues(\.count))")
    }

    @Test func theStudiesBelongToTheCatalogAndAreWellFormed() throws {
        #expect(Set(Postcards.studies.keys).isSubset(of: Set(BoxCatalog.ids(.postcard))))
        #expect(Postcards.study(for: "postcard-05") != nil && Postcards.study(for: "postcard-17") == nil && Postcards.study(for: "postcard-21") == nil)
        for (id, s) in Postcards.studies {
            #expect(!s.pmid.isEmpty && s.pmid.allSatisfy(\.isASCII) && s.pmid.allSatisfy(\.isNumber), "\(id) pmid")
            let url = try #require(URL(string: s.url), "\(id)")
            #expect(url.scheme == "https", "\(id)")
            let host = try #require(url.host, "\(id)")
            #expect(Postcards.allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) }, "\(id): \(host)")
            #expect((1950...2026).contains(s.year), "\(id) year")
            #expect(!s.firstAuthor.isEmpty && !s.journal.isEmpty, "\(id)")
        }
    }

    @Test func noTwoPostcardsShareAStudy() {
        let pmids = Postcards.studies.values.map(\.pmid)
        #expect(Set(pmids).count == pmids.count)
    }
}
