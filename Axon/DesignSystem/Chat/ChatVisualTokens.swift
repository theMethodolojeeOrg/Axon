//
//  ChatVisualTokens.swift
//  Axon
//
//  Chat-specific visual tokens for spacing, sizing, and layout rhythm.
//

import SwiftUI

enum ChatVisualTokens {
    // MARK: - Message Layout

    #if os(macOS)
    static let chatRailMaxWidth: CGFloat = 940
    static let chatRailHorizontalPadding: CGFloat = 24
    static let messageMaxReadableWidth: CGFloat = 940
    #else
    static let chatRailMaxWidth: CGFloat = .infinity
    static let chatRailHorizontalPadding: CGFloat = 0
    static let messageMaxReadableWidth: CGFloat = 520
    #endif
    static let messageOuterHorizontalPadding: CGFloat = 12
    static let messageBubbleHorizontalPadding: CGFloat = 14
    static let messageBubbleVerticalPadding: CGFloat = 10
    static let messageAvatarSize: CGFloat = 28

    // MARK: - Turn Rhythm

    static let intraClusterSpacing: CGFloat = 4
    static let interTurnSpacing: CGFloat = 14
    static let messageSectionVerticalPadding: CGFloat = 10

    // MARK: - Composer

    static let minTouchTarget: CGFloat = 44
    #if os(macOS)
    static let composerCornerRadius: CGFloat = 16
    static let composerInnerCornerRadius: CGFloat = 11
    static let composerControlSize: CGFloat = 32
    static let composerControlGlyphSize: CGFloat = 15
    static let composerControlChevronSize: CGFloat = 8
    static let composerOuterVerticalPadding: CGFloat = 5
    static let composerInputMaxHeight: CGFloat = 96
    static let composerAttachmentTileSize: CGFloat = 48
    #else
    static let composerCornerRadius: CGFloat = 28
    static let composerInnerCornerRadius: CGFloat = 18
    static let composerControlSize: CGFloat = 44
    static let composerControlGlyphSize: CGFloat = 18
    static let composerControlChevronSize: CGFloat = 10
    static let composerOuterVerticalPadding: CGFloat = 7
    static let composerInputMaxHeight: CGFloat = 120
    static let composerAttachmentTileSize: CGFloat = 56
    #endif
    static let composerHorizontalPadding: CGFloat = 12
    static let composerBottomPadding: CGFloat = 6
    static let composerAttachmentPreviewHeight: CGFloat = composerAttachmentTileSize + 16
    static let composerSendGlyphSize: CGFloat = 15
    #if os(macOS)
    static let composerSendIconFrame: CGFloat = 28
    #else
    static let composerSendIconFrame: CGFloat = 34
    #endif
    static let composerSlashMenuBottomOffset: CGFloat = composerControlSize + (composerOuterVerticalPadding * 2) + composerBottomPadding + 32

    // MARK: - iOS Chrome

    static let toolbarButtonSize: CGFloat = 44
    static let sidebarScrimOpacity: CGFloat = 0.22

    // MARK: - Menus

    static let slashMenuMaxHeightRatio: CGFloat = 0.45
    static let slashMenuAbsoluteMaxHeight: CGFloat = 420

    // MARK: - Welcome

    static let welcomeHeroTopSpacing: CGFloat = 24
    static let welcomeHeroLogoSize: CGFloat = 112
    static let welcomePromptCardSpacing: CGFloat = 10
}
