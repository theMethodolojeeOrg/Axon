//
//  PaperPacket.swift
//  Axon
//
//  Phase 9 artifact: Standardized manuscript unit packaging collapse results.
//

import Foundation

// MARK: - Paper Section

/// A section in a paper packet
struct PaperSection: Codable, Equatable, Hashable {
    /// Title of the section
    let title: String

    /// Content of the section
    let content: String

    /// Type of section
    let sectionType: PaperSectionType

    /// Order in the document
    let order: Int

    init(
        title: String,
        content: String,
        sectionType: PaperSectionType,
        order: Int? = nil
    ) {
        self.title = title
        self.content = content
        self.sectionType = sectionType
        self.order = order ?? sectionType.order
    }
}

// MARK: - Paper Reference

/// A reference/citation in a paper packet
struct PaperReference: Codable, Equatable, Hashable {
    /// Unique identifier
    let id: String

    /// Citation text
    let citation: String

    /// URL if available
    let url: String?

    /// Notes about the reference
    let notes: String?

    init(
        id: String = UUID().uuidString,
        citation: String,
        url: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.citation = citation
        self.url = url
        self.notes = notes
    }
}

// MARK: - Paper Appendix

/// An appendix in a paper packet
struct PaperAppendix: Codable, Equatable, Hashable {
    /// Title of the appendix
    let title: String

    /// Content of the appendix
    let content: String

    /// Order in the appendices
    let order: Int

    init(
        title: String,
        content: String,
        order: Int = 0
    ) {
        self.title = title
        self.content = content
        self.order = order
    }
}

// MARK: - Paper Packet

/// A standardized manuscript unit packaging collapse results.
///
/// From the protocol, a packet must include:
/// 1. Scope
/// 2. Constraint identity evidence
/// 3. Derivation status
/// 4. Gauge choice + what it quotients
/// 5. Predictions/tests
/// 6. Failure modes
/// 7. Gauge Relativity note (permission to re-gauge)
///
/// Formally: Π = (A, B, C, S, g, D, T, F, R)
/// where T are tests, F are failure modes, and R is gauge-relativity metadata.
struct PaperPacket: Codable, Identifiable, Equatable {
    /// Unique identifier
    let id: String

    /// Session this belongs to
    let sessionId: CollapseSessionId

    /// Title of the paper
    let title: String

    /// Abstract summarizing the collapse
    let abstract: String

    /// Sections of the paper
    let sections: [PaperSection]

    /// References/citations
    let references: [PaperReference]?

    /// Appendices
    let appendices: [PaperAppendix]?

    /// Predictions that can be tested
    let predictions: [String]

    /// Known failure modes
    let failureModes: [String]

    /// Version of this packet
    let version: String

    /// Status of the paper
    let status: PaperStatus

    /// When this packet was created
    let createdAt: Date

    /// When this packet was last updated
    let updatedAt: Date

    /// Metadata
    let metadata: [String: String]?

    init(
        id: String = UUID().uuidString,
        sessionId: CollapseSessionId,
        title: String,
        abstract: String,
        sections: [PaperSection],
        references: [PaperReference]? = nil,
        appendices: [PaperAppendix]? = nil,
        predictions: [String] = [],
        failureModes: [String] = [],
        version: String = "1.0.0",
        status: PaperStatus = .draft,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.abstract = abstract
        self.sections = sections.sorted { $0.order < $1.order }
        self.references = references
        self.appendices = appendices?.sorted { $0.order < $1.order }
        self.predictions = predictions
        self.failureModes = failureModes
        self.version = version
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    /// Sections sorted by order
    var sortedSections: [PaperSection] {
        sections.sorted { $0.order < $1.order }
    }

    /// Generate markdown export
    func toMarkdown() -> String {
        var md = "# \(title)\n\n"
        md += "## Abstract\n\n\(abstract)\n\n"

        for section in sortedSections {
            md += "## \(section.title)\n\n\(section.content)\n\n"
        }

        if !predictions.isEmpty {
            md += "## Predictions\n\n"
            for (i, prediction) in predictions.enumerated() {
                md += "\(i + 1). \(prediction)\n"
            }
            md += "\n"
        }

        if !failureModes.isEmpty {
            md += "## Failure Modes\n\n"
            for (i, mode) in failureModes.enumerated() {
                md += "\(i + 1). \(mode)\n"
            }
            md += "\n"
        }

        if let refs = references, !refs.isEmpty {
            md += "## References\n\n"
            for ref in refs {
                md += "- \(ref.citation)"
                if let url = ref.url {
                    md += " [\(url)]"
                }
                md += "\n"
            }
            md += "\n"
        }

        if let apps = appendices, !apps.isEmpty {
            for appendix in apps.sorted(by: { $0.order < $1.order }) {
                md += "## Appendix: \(appendix.title)\n\n\(appendix.content)\n\n"
            }
        }

        md += "---\n"
        md += "*Generated by Collapse Engine v\(version)*\n"
        md += "*Status: \(status.displayName)*\n"

        return md
    }

    /// Generate a summary for memory storage
    var summary: String {
        """
        Paper Packet: \(title)
        Status: \(status.displayName)
        Sections: \(sections.count)
        Predictions: \(predictions.count)
        Failure Modes: \(failureModes.count)
        Version: \(version)
        """
    }
}
