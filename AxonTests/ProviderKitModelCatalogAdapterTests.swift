import XCTest
import AxonProviderKitCore
@testable import Axon

@MainActor
final class ProviderKitModelCatalogAdapterTests: XCTestCase {
    private typealias AxonProvider = Axon.AIProvider

    override func setUp() {
        super.setUp()
        applyTestMLXConfig()
    }

    func testProviderMappingsCoverAxonBuiltIns() {
        for provider in AxonProvider.allCases {
            XCTAssertNotNil(
                ProviderKitModelCatalogAdapter.providerKitProvider(for: provider),
                "Missing ProviderKit mapping for \(provider.rawValue)"
            )
        }

        XCTAssertEqual(
            ProviderKitModelCatalogAdapter.axonProvider(for: .appleIntelligence),
            .appleFoundation
        )
        XCTAssertEqual(
            ProviderKitModelCatalogAdapter.axonProvider(for: .mlx),
            .localMLX
        )
        XCTAssertNil(ProviderKitModelCatalogAdapter.axonProvider(for: .venice))
        XCTAssertNil(ProviderKitModelCatalogAdapter.axonProvider(for: .aiEdge))
    }

    func testEveryAxonBuiltInProviderHasModels() {
        for provider in AxonProvider.allCases {
            XCTAssertFalse(
                ProviderKitModelCatalogAdapter.models(for: provider).isEmpty,
                "Expected ProviderKit models for \(provider.rawValue)"
            )
        }
    }

    func testAppleDefaultCompatibility() {
        let models = ProviderKitModelCatalogAdapter.models(for: .appleFoundation)
        XCTAssertTrue(models.contains { $0.id == ProviderKitModelCatalogAdapter.appleFoundationModelId })
        XCTAssertEqual(
            ProviderKitModelCatalogAdapter.contextWindow(for: ProviderKitModelCatalogAdapter.appleFoundationModelId),
            4096
        )
    }

    func testLocalMLXConfigModelsAreVisible() {
        let modelIds = Set(ProviderKitModelCatalogAdapter.models(for: .localMLX).map(\.id))
        XCTAssertTrue(modelIds.contains("google/gemma-4-E2B-it-MLX"))
        XCTAssertTrue(modelIds.contains("mlx-community/Qwen3-VL-2B-Instruct-4bit"))
        XCTAssertTrue(modelIds.contains("lmstudio-community/gemma-3-270m-it-MLX-8bit"))
    }

    func testPricingKnownFreeAndUnknownStates() {
        XCTAssertNotNil(ProviderKitModelCatalogAdapter.pricing(for: "claude-sonnet-4-6"))
        XCTAssertEqual(
            ProviderKitModelCatalogAdapter.pricing(for: ProviderKitModelCatalogAdapter.appleFoundationModelId)?.inputPerMTokUSD,
            0
        )
        XCTAssertNil(ProviderKitModelCatalogAdapter.pricing(for: "gpt-5.4"))
    }

    func testTierSelectionFiltersToConfiguredAxonProviders() {
        let result = UnifiedModelRegistry.shared.selectModel(for: .fast) { provider in
            provider == .openai
        }

        XCTAssertEqual(result?.provider, .openai)
        XCTAssertNotNil(result?.modelConfig)
    }

    private func applyTestMLXConfig() {
        let config = AxonProviderKitCore.MLXModelConfig(
            version: 1,
            defaultModelId: "google/gemma-4-E2B-it-MLX",
            models: [
                .init(
                    id: "google/gemma-4-E2B-it-MLX",
                    displayName: "Gemma 4 E2B",
                    summary: "Bundled test model",
                    contextWindow: 8192,
                    modalities: ["text"],
                    bundled: true,
                    localPath: "MLXModels/google_gemma-4-E2B-it-MLX"
                ),
                .init(
                    id: "mlx-community/Qwen3-VL-2B-Instruct-4bit",
                    displayName: "Qwen3 VL 2B",
                    summary: "Bundled test vision model",
                    contextWindow: 8192,
                    modalities: ["text", "vision"],
                    bundled: true,
                    localPath: "MLXModels/mlx-community_Qwen3-VL-2B-Instruct-4bit"
                ),
                .init(
                    id: "lmstudio-community/gemma-3-270m-it-MLX-8bit",
                    displayName: "Gemma3 270M",
                    summary: "Bundled test model",
                    contextWindow: 8192,
                    modalities: ["text"],
                    bundled: true,
                    localPath: "MLXModels/lmstudio-community_gemma-3-270m-it-MLX-8bit"
                )
            ],
            excludeDefaults: []
        )

        MLXModelConfigLoader.shared.apply(config)
        MLXModelRegistry.shared.updateModels([])
        ProviderKitModelCatalogAdapter.bootstrapMLXCatalog()
    }
}
