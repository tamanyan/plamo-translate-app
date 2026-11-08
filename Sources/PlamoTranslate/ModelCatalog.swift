import Foundation

struct ModelEntry: Codable, Identifiable, Hashable, Sendable {
    let size: String
    let quant: String
    let revision: String
    let bytes: Int64
    let sha256: String
    var id: String { "plamo-3-translate-\(size)-\(quant)" }
    var fileName: String { id + ".gguf" }
    var repo: String { "pfnet/plamo-3-translate-\(size)-GGUF" }
    var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(fileName)")! }
    var label: String { size.uppercased() + " · " + quant }
    var formattedSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var partialName: String { fileName + "." + sha256.prefix(12) + ".part" }
    var memoryRecommendation: String {
        switch size { case "0.8b": return "4 GB+"; case "2b": return "8 GB+"; case "8b": return "16 GB+"; default: return "32 GB+" }
    }
    // Pinned revisions and SHA-256 values from tanakh/plamo-translate-desktop,
    // crates/engine/src/models.rs (2026-11-06 catalog). See THIRD-PARTY-NOTICES.md.
    static let builtIn: [ModelEntry] = [
        .init(size: "0.8b", quant: "Q4_K_M", revision: "dbeb0856cb0b004b484f190bb71dd65876297013", bytes: 573123200, sha256: "923b2f28a9856de1b8b3b610a7e59ded0b14d007466fd5dd526e6a9ecaadafdd"),
        .init(size: "0.8b", quant: "Q4_0", revision: "dbeb0856cb0b004b484f190bb71dd65876297013", bytes: 547539584, sha256: "39300577d714b108a509ca9d582ea7335ae2fa4504ee73d3358c00b4980fb32a"),
        .init(size: "0.8b", quant: "Q3_K_M", revision: "dbeb0856cb0b004b484f190bb71dd65876297013", bytes: 486382208, sha256: "712dbe94cdb6dffa08082472e74ee8c65e12e688ad9e76cb944a1b3699be208f"),
        .init(size: "0.8b", quant: "Q2_K", revision: "dbeb0856cb0b004b484f190bb71dd65876297013", bytes: 410135168, sha256: "8f84478629c5d36ffe6a28f4de1bbe7f49da0faf53644614453d00ad63330bea"),
        .init(size: "2b", quant: "Q4_K_M", revision: "232fbd7916519edecddfdae0beae7e76fe70453f", bytes: 1807199392, sha256: "f36d0813dd95573a852ab5d76e374c543632d9e292929e922bcdbf7e53b494e0"),
        .init(size: "2b", quant: "Q4_0", revision: "232fbd7916519edecddfdae0beae7e76fe70453f", bytes: 1698573472, sha256: "9b976e7857b65012cb98da4f4176203fb42fadf542057980d5329a93d3e4f8f8"),
        .init(size: "2b", quant: "Q3_K_M", revision: "232fbd7916519edecddfdae0beae7e76fe70453f", bytes: 1495882912, sha256: "24ef0a97f1527d2aa49fc12ddcd9eb6de74d6b883ffcd84c72cac299fafb3006"),
        .init(size: "2b", quant: "Q2_K", revision: "232fbd7916519edecddfdae0beae7e76fe70453f", bytes: 1225608352, sha256: "01517813751c20412568f93845858f6902eefc3794f247dfbb50bad466b108e7"),
        .init(size: "8b", quant: "Q4_K_M", revision: "2234f168757f570714b333049c9d018161ec5277", bytes: 5280442080, sha256: "47a04e86a67bcc352fa186f01159060aae594b73993e1d49dbfc0ef0081d01ad"),
        .init(size: "8b", quant: "Q3_K_M", revision: "2234f168757f570714b333049c9d018161ec5277", bytes: 4310214368, sha256: "b52b510f7bf1d49bff10cc9024518bfd88b78f0bb38d63956f5e7784f573d97b"),
        .init(size: "8b", quant: "Q2_K", revision: "2234f168757f570714b333049c9d018161ec5277", bytes: 3450742496, sha256: "917b86aedab74a3d2172bbed89830a9593bc610b370886a2b5f5acd3e1f58589"),
        .init(size: "31b", quant: "Q4_K_M", revision: "7970aee3005211df5d90740a3e009a9b26be4df9", bytes: 19526590304, sha256: "ae935e91092f67df6254388c510cb89870353055912e452bb9e4923fd4f41071"),
        .init(size: "31b", quant: "Q3_K_M", revision: "7970aee3005211df5d90740a3e009a9b26be4df9", bytes: 15863127904, sha256: "52918573c603e656f29d221f11ced1709a94df134d58dffa603806f77f947942"),
        .init(size: "31b", quant: "Q2_K", revision: "7970aee3005211df5d90740a3e009a9b26be4df9", bytes: 12609920864, sha256: "37d16404bc852dc8bf8ca95d6411e90b3bc0ff754b3c68474736ea59be3959ab")
    ]
}
