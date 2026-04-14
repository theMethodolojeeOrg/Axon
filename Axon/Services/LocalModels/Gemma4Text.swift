//
//  Gemma4Text.swift
//  Axon
//
//  Gemma 4 text model implementation for MLX Swift.
//  Ported from ml-explore/mlx-lm gemma4_text.py, adapted for the weight
//  structure produced by the GGUF-to-MLX converter.
//

#if canImport(MLX) && canImport(MLXLLM) && canImport(MLXLMCommon)

import Foundation
import MLX
import MLXFast
import MLXNN
import MLXLMCommon
import MLXLLM

// MARK: - Configuration

public struct Gemma4TextConfiguration: Codable, Sendable {
    let modelType: String
    let hiddenSize: Int
    let hiddenLayers: Int
    let intermediateSize: [Int]
    let attentionHeads: Int
    let headDim: Int
    let globalHeadDim: Int
    let rmsNormEps: Float
    let vocabularySize: Int
    let kvHeads: Int
    let maxPositionEmbeddings: Int
    let slidingWindow: Int
    let slidingWindowPattern: Int
    let finalLogitSoftcapping: Float
    let tieWordEmbeddings: Bool
    let layerTypes: [String]
    let ropeParameters: RopeParameters?

    struct RopeParameters: Codable, Sendable {
        let fullAttention: RopeConfig?
        let slidingAttention: RopeConfig?

        enum CodingKeys: String, CodingKey {
            case fullAttention = "full_attention"
            case slidingAttention = "sliding_attention"
        }
    }

    struct RopeConfig: Codable, Sendable {
        let ropeTheta: Float?
        let partialRotaryFactor: Float?
        let ropeType: String?

        enum CodingKeys: String, CodingKey {
            case ropeTheta = "rope_theta"
            case partialRotaryFactor = "partial_rotary_factor"
            case ropeType = "rope_type"
        }
    }

    enum CodingKeys: String, CodingKey {
        case modelType = "model_type"
        case hiddenSize = "hidden_size"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case attentionHeads = "num_attention_heads"
        case headDim = "head_dim"
        case globalHeadDim = "global_head_dim"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case kvHeads = "num_key_value_heads"
        case maxPositionEmbeddings = "max_position_embeddings"
        case slidingWindow = "sliding_window"
        case slidingWindowPattern = "sliding_window_pattern"
        case finalLogitSoftcapping = "final_logit_softcapping"
        case tieWordEmbeddings = "tie_word_embeddings"
        case layerTypes = "layer_types"
        case ropeParameters = "rope_parameters"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        modelType = try container.decode(String.self, forKey: .modelType)
        hiddenSize = try container.decodeIfPresent(Int.self, forKey: .hiddenSize) ?? 1536
        hiddenLayers = try container.decodeIfPresent(Int.self, forKey: .hiddenLayers) ?? 35
        attentionHeads = try container.decodeIfPresent(Int.self, forKey: .attentionHeads) ?? 8
        headDim = try container.decodeIfPresent(Int.self, forKey: .headDim) ?? 256
        globalHeadDim = try container.decodeIfPresent(Int.self, forKey: .globalHeadDim) ?? 512
        rmsNormEps = try container.decodeIfPresent(Float.self, forKey: .rmsNormEps) ?? 1e-6
        vocabularySize = try container.decodeIfPresent(Int.self, forKey: .vocabularySize) ?? 262144
        kvHeads = try container.decodeIfPresent(Int.self, forKey: .kvHeads) ?? 1
        maxPositionEmbeddings = try container.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings) ?? 131072
        slidingWindow = try container.decodeIfPresent(Int.self, forKey: .slidingWindow) ?? 512
        slidingWindowPattern = try container.decodeIfPresent(Int.self, forKey: .slidingWindowPattern) ?? 5
        finalLogitSoftcapping = try container.decodeIfPresent(Float.self, forKey: .finalLogitSoftcapping) ?? 30.0
        tieWordEmbeddings = try container.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) ?? true
        ropeParameters = try container.decodeIfPresent(RopeParameters.self, forKey: .ropeParameters)

        // intermediate_size can be a single int or per-layer array
        if let array = try? container.decode([Int].self, forKey: .intermediateSize) {
            intermediateSize = array
        } else if let single = try? container.decode(Int.self, forKey: .intermediateSize) {
            intermediateSize = Array(repeating: single, count: hiddenLayers)
        } else {
            intermediateSize = Array(repeating: 6144, count: hiddenLayers)
        }

        // layer_types defaults to sliding_window_pattern-based pattern
        if let types = try? container.decode([String].self, forKey: .layerTypes) {
            layerTypes = types
        } else {
            layerTypes = (0..<hiddenLayers).map { i in
                (i + 1) % slidingWindowPattern == 0 ? "full_attention" : "sliding_attention"
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(modelType, forKey: .modelType)
        try container.encode(hiddenSize, forKey: .hiddenSize)
        try container.encode(hiddenLayers, forKey: .hiddenLayers)
        try container.encode(intermediateSize, forKey: .intermediateSize)
        try container.encode(attentionHeads, forKey: .attentionHeads)
        try container.encode(headDim, forKey: .headDim)
        try container.encode(globalHeadDim, forKey: .globalHeadDim)
        try container.encode(rmsNormEps, forKey: .rmsNormEps)
        try container.encode(vocabularySize, forKey: .vocabularySize)
        try container.encode(kvHeads, forKey: .kvHeads)
        try container.encode(maxPositionEmbeddings, forKey: .maxPositionEmbeddings)
        try container.encode(slidingWindow, forKey: .slidingWindow)
        try container.encode(slidingWindowPattern, forKey: .slidingWindowPattern)
        try container.encode(finalLogitSoftcapping, forKey: .finalLogitSoftcapping)
        try container.encode(tieWordEmbeddings, forKey: .tieWordEmbeddings)
        try container.encode(layerTypes, forKey: .layerTypes)
        try container.encodeIfPresent(ropeParameters, forKey: .ropeParameters)
    }

    /// Whether a given layer index uses full (global) attention
    func isFullAttention(layerIdx: Int) -> Bool {
        if layerIdx < layerTypes.count {
            return layerTypes[layerIdx] == "full_attention"
        }
        return (layerIdx + 1) % slidingWindowPattern == 0
    }

    /// Get the effective head dimension for a given layer
    func effectiveHeadDim(layerIdx: Int) -> Int {
        isFullAttention(layerIdx: layerIdx) ? globalHeadDim : headDim
    }

    /// Get the RoPE theta for a given layer type
    func ropeTheta(forFullAttention: Bool) -> Float {
        if forFullAttention {
            return ropeParameters?.fullAttention?.ropeTheta ?? 1_000_000.0
        } else {
            return ropeParameters?.slidingAttention?.ropeTheta ?? 10_000.0
        }
    }

    /// Get the partial rotary factor for full attention layers
    var fullAttentionPartialRotaryFactor: Float {
        ropeParameters?.fullAttention?.partialRotaryFactor ?? 0.25
    }
}

// MARK: - Attention

private class Gemma4Attention: Module {
    let nHeads: Int
    let nKVHeads: Int
    let layerHeadDim: Int
    let scale: Float
    let isFullAttention: Bool
    let slidingWindow: Int
    let partialRotaryDims: Int

    @ModuleInfo(key: "q_proj") var queryProj: Linear
    @ModuleInfo(key: "k_proj") var keyProj: Linear
    @ModuleInfo(key: "v_proj") var valueProj: Linear
    @ModuleInfo(key: "o_proj") var outputProj: Linear

    @ModuleInfo(key: "q_norm") var queryNorm: Gemma.RMSNorm
    @ModuleInfo(key: "k_norm") var keyNorm: Gemma.RMSNorm

    let rope: RoPE

    init(_ config: Gemma4TextConfiguration, layerIdx: Int) {
        let dim = config.hiddenSize
        self.nHeads = config.attentionHeads
        self.nKVHeads = config.kvHeads
        self.isFullAttention = config.isFullAttention(layerIdx: layerIdx)
        self.layerHeadDim = config.effectiveHeadDim(layerIdx: layerIdx)
        self.slidingWindow = config.slidingWindow

        // Scale uses head_dim (not global_head_dim) per the Python implementation
        self.scale = pow(Float(config.headDim), -0.5)

        self._queryProj.wrappedValue = Linear(dim, nHeads * layerHeadDim, bias: false)
        self._keyProj.wrappedValue = Linear(dim, nKVHeads * layerHeadDim, bias: false)
        self._valueProj.wrappedValue = Linear(dim, nKVHeads * layerHeadDim, bias: false)
        self._outputProj.wrappedValue = Linear(nHeads * layerHeadDim, dim, bias: false)

        self._queryNorm.wrappedValue = Gemma.RMSNorm(
            dimensions: layerHeadDim, eps: config.rmsNormEps)
        self._keyNorm.wrappedValue = Gemma.RMSNorm(
            dimensions: layerHeadDim, eps: config.rmsNormEps)

        // RoPE configuration differs between full and sliding attention
        let ropeTheta = config.ropeTheta(forFullAttention: isFullAttention)

        if isFullAttention {
            // Full attention uses partial rotary embedding
            self.partialRotaryDims = Int(Float(layerHeadDim) * config.fullAttentionPartialRotaryFactor)
            self.rope = RoPE(dimensions: partialRotaryDims, traditional: false, base: ropeTheta)
        } else {
            // Sliding attention uses full rotary embedding
            self.partialRotaryDims = layerHeadDim
            self.rope = RoPE(dimensions: layerHeadDim, traditional: false, base: ropeTheta)
        }

        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache? = nil
    ) -> MLXArray {
        let (B, L, _) = (x.dim(0), x.dim(1), x.dim(2))

        var queries = queryProj(x)
        var keys = keyProj(x)
        var values = valueProj(x)

        queries = queries.reshaped(B, L, nHeads, -1).transposed(0, 2, 1, 3)
        keys = keys.reshaped(B, L, nKVHeads, -1).transposed(0, 2, 1, 3)
        values = values.reshaped(B, L, nKVHeads, -1).transposed(0, 2, 1, 3)

        // Apply QK normalization
        queries = queryNorm(queries)
        keys = keyNorm(keys)

        // Apply RoPE
        if let cache {
            queries = rope(queries, offset: cache.offset)
            keys = rope(keys, offset: cache.offset)
        } else {
            queries = rope(queries)
            keys = rope(keys)
        }

        let output = attentionWithCacheUpdate(
            queries: queries,
            keys: keys,
            values: values,
            cache: cache,
            scale: scale,
            mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)

        return outputProj(output)
    }
}

// MARK: - MLP

private class Gemma4MLP: Module {
    @ModuleInfo(key: "gate_proj") var gateProj: Linear
    @ModuleInfo(key: "down_proj") var downProj: Linear
    @ModuleInfo(key: "up_proj") var upProj: Linear

    init(dimensions: Int, hiddenDimensions: Int) {
        self._gateProj.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
        self._downProj.wrappedValue = Linear(hiddenDimensions, dimensions, bias: false)
        self._upProj.wrappedValue = Linear(dimensions, hiddenDimensions, bias: false)
        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        downProj(geluApproximate(gateProj(x)) * upProj(x))
    }
}

// MARK: - Transformer Block

private class Gemma4TransformerBlock: Module {
    @ModuleInfo(key: "self_attn") var selfAttention: Gemma4Attention
    @ModuleInfo var mlp: Gemma4MLP
    @ModuleInfo(key: "input_layernorm") var inputLayerNorm: Gemma.RMSNorm
    @ModuleInfo(key: "post_attention_layernorm") var postAttentionLayerNorm: Gemma.RMSNorm

    init(_ config: Gemma4TextConfiguration, layerIdx: Int) {
        self._selfAttention.wrappedValue = Gemma4Attention(config, layerIdx: layerIdx)
        self.mlp = Gemma4MLP(
            dimensions: config.hiddenSize,
            hiddenDimensions: config.intermediateSize[layerIdx]
        )
        self._inputLayerNorm.wrappedValue = Gemma.RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = Gemma.RMSNorm(
            dimensions: config.hiddenSize, eps: config.rmsNormEps)
        super.init()
    }

    func callAsFunction(
        _ x: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode,
        cache: KVCache? = nil
    ) -> MLXArray {
        // Attention with residual
        let r = selfAttention(inputLayerNorm(x), mask: mask, cache: cache)
        let h = Gemma.clipResidual(x, r)
        // MLP with residual
        let r2 = mlp(postAttentionLayerNorm(h))
        return Gemma.clipResidual(h, r2)
    }
}

// MARK: - Model

private class Gemma4Model: Module {
    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding
    @ModuleInfo var layers: [Gemma4TransformerBlock]
    @ModuleInfo var norm: Gemma.RMSNorm

    let config: Gemma4TextConfiguration

    init(_ config: Gemma4TextConfiguration) {
        self.config = config

        self._embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabularySize,
            dimensions: config.hiddenSize
        )

        self._layers.wrappedValue = (0..<config.hiddenLayers).map { layerIdx in
            Gemma4TransformerBlock(config, layerIdx: layerIdx)
        }

        self.norm = Gemma.RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)

        super.init()
    }

    func callAsFunction(
        _ inputs: MLXArray,
        mask: MLXFast.ScaledDotProductAttentionMaskMode? = nil,
        cache: [KVCache?]? = nil
    ) -> MLXArray {
        var h = embedTokens(inputs)

        // Scale embeddings by sqrt(hidden_size) — Gemma convention
        let scale = MLXArray(sqrt(Float(config.hiddenSize)), dtype: .bfloat16)
        h = h * scale.asType(h.dtype)

        var layerCache = cache ?? Array(repeating: nil as KVCache?, count: layers.count)

        // Create attention masks for full vs sliding layers
        var fullMask: MLXFast.ScaledDotProductAttentionMaskMode = .none
        var slidingWindowMask: MLXFast.ScaledDotProductAttentionMaskMode = .none

        if mask == nil {
            // Find a global layer's cache for the full attention mask
            let globalLayerIdx = (0..<config.hiddenLayers).first { config.isFullAttention(layerIdx: $0) }
            if let idx = globalLayerIdx, let globalCache = layerCache[idx] {
                fullMask = createAttentionMask(h: h, cache: [globalCache])
            } else {
                fullMask = createAttentionMask(h: h, cache: nil)
            }

            // For sliding window, use the first sliding layer's cache
            let slidingLayerIdx = (0..<config.hiddenLayers).first { !config.isFullAttention(layerIdx: $0) }
            if let idx = slidingLayerIdx, let slidingCache = layerCache[idx] {
                slidingWindowMask = createAttentionMask(h: h, cache: [slidingCache])
            } else {
                slidingWindowMask = createAttentionMask(h: h, cache: nil)
            }
        }

        for (i, layer) in layers.enumerated() {
            let localMask: MLXFast.ScaledDotProductAttentionMaskMode
            if let mask {
                localMask = mask
            } else if config.isFullAttention(layerIdx: i) {
                localMask = fullMask
            } else {
                localMask = slidingWindowMask
            }
            h = layer(h, mask: localMask, cache: layerCache[i])
        }

        return norm(h)
    }
}

// MARK: - Top-Level Model

public class Gemma4TextModel: Module, LLMModel {

    @ModuleInfo var model: Gemma4Model
    @ModuleInfo(key: "lm_head") var lmHead: Linear

    public let config: Gemma4TextConfiguration
    public var vocabularySize: Int { config.vocabularySize }

    public init(_ config: Gemma4TextConfiguration) {
        self.config = config
        self.model = Gemma4Model(config)
        self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabularySize, bias: false)
        super.init()
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var out = model(inputs, mask: nil, cache: cache)
        out = lmHead(out)

        // Apply final logit softcapping: tanh(logits / cap) * cap
        if config.finalLogitSoftcapping > 0 {
            out = tanh(out / config.finalLogitSoftcapping) * config.finalLogitSoftcapping
        }

        return out
    }

    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        var processedWeights = weights

        // Handle VLM-style weights with language_model prefix
        let unflattened = ModuleParameters.unflattened(weights)
        if let lm = unflattened["language_model"] {
            processedWeights = Dictionary(uniqueKeysWithValues: lm.flattened())
        }

        // Truncate embedding/lm_head if vocab size is larger than expected
        let expectedVocab = config.vocabularySize
        let keysToCheck = [
            "model.embed_tokens.weight", "model.embed_tokens.scales", "model.embed_tokens.biases",
            "lm_head.weight", "lm_head.scales", "lm_head.biases",
        ]

        for key in keysToCheck {
            if let tensor = processedWeights[key], tensor.dim(0) > expectedVocab {
                processedWeights[key] = tensor[0..<expectedVocab]
            }
        }

        // Tie embeddings: copy embed_tokens to lm_head if missing
        if config.tieWordEmbeddings && processedWeights["lm_head.weight"] == nil {
            ["weight", "scales", "biases"].forEach { key in
                if let embedWeight = processedWeights["model.embed_tokens.\(key)"] {
                    processedWeights["lm_head.\(key)"] = embedWeight
                }
            }
        }

        return processedWeights
    }

    public func newCache(parameters: GenerateParameters? = nil) -> [KVCache] {
        var caches = [KVCache]()

        for i in 0..<config.hiddenLayers {
            if config.isFullAttention(layerIdx: i) {
                // Full attention layers use standard cache
                let cache = KVCacheSimple()
                cache.step = 1024
                caches.append(cache)
            } else {
                // Sliding attention layers use rotating cache
                caches.append(
                    RotatingKVCache(maxSize: config.slidingWindow, keep: 0)
                )
            }
        }

        return caches
    }

    public func prepare(
        _ input: LMInput, cache: [KVCache], windowSize: Int? = nil
    ) throws -> PrepareResult {
        let promptTokens = input.text.tokens
        guard promptTokens.size > 0 else {
            let emptyToken = MLXArray(Int32(0))[0..<0]
            return .tokens(.init(tokens: emptyToken))
        }
        return .tokens(input.text)
    }
}

// MARK: - LoRA

extension Gemma4TextModel: LoRAModel {
    public func loraLinearLayers() -> LoRALinearLayers {
        model.layers.map { ($0.selfAttention, ["q_proj", "v_proj"]) }
    }
}

#endif
