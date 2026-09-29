import Testing
@testable import TexturCore

@Suite("MaterialCatalog")
struct MaterialCatalogTests {
    @Test func offersSixDistinctMaterials() {
        let materials = MaterialCatalog.all
        #expect(materials.count == 6)
        #expect(Set(materials.map(\.id)).count == 6)
        #expect(Set(materials.map(\.name)).count == 6)
        #expect(materials.map(\.id) == MaterialID.allCases)
    }

    @Test(arguments: MaterialID.allCases)
    func everyMaterialIsPlayable(id: MaterialID) {
        let material = MaterialCatalog.material(for: id)
        #expect(material.id == id)
        #expect(material.spacing >= 0.3)
        #expect((0...1).contains(material.jitter))
        #expect((0..<1).contains(material.skipChance))
        #expect(!material.grain.isEmpty)
        #expect(material.axisWeights.x >= 0 && material.axisWeights.y >= 0)
        #expect(material.axisWeights.x + material.axisWeights.y > 0)
        #expect(!material.summary.isEmpty)
    }

    @Test(arguments: MaterialID.allCases)
    func previewIsAShortOrderedPhrase(id: MaterialID) {
        let preview = MaterialCatalog.material(for: id).preview(strength: .medium)
        #expect(preview.count >= 4)
        #expect(zip(preview, preview.dropFirst()).allSatisfy { $0.delay <= $1.delay })
        #expect((preview.last?.delay ?? 0) < 1.0)
    }

    @Test(arguments: MaterialID.allCases)
    func previewGrainsMakeUpThePreview(id: MaterialID) {
        let material = MaterialCatalog.material(for: id)
        let grains = material.previewGrains(strength: .strong)
        #expect(grains.count == 8)
        #expect(grains.allSatisfy { !$0.isEmpty })
        #expect(grains.flatMap { $0 } == material.preview(strength: .strong))
    }

    @Test func tapGrainIsNeverEmptyAndFollowsStrength() {
        let wood = MaterialCatalog.material(for: .wood)
        let subtle = wood.tapGrain(strength: .subtle)
        let strong = wood.tapGrain(strength: .strong)
        #expect(!subtle.isEmpty)
        #expect(subtle[0].strength < strong[0].strength)
    }

    @Test func unknownIdentifierFallsBackToTheDefault() {
        #expect(MaterialID(storedValue: "velvet") == .linen)
        #expect(MaterialID(storedValue: "sand") == .sand)
    }
}
