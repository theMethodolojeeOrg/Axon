//
//  AxonLiveActivityBundle.swift
//  AxonLiveActivity
//
//  Created by Tom on 12/18/25.
//

import WidgetKit
import SwiftUI

@main
struct AxonLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        // Live Activities
        HeartbeatLiveActivity()
        SubAgentLiveActivity()
        VideoGenerationLiveActivity()

        // Home Screen Widgets
        ConversationWidget()
    }
}
