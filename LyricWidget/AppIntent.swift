//
//  AppIntent.swift
//  LyricWidget
//
//  Created by Aiden Liu on 11/13/25.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Lyrics Widget" }
    static var description: IntentDescription { "Displays lyrics for the currently playing Spotify track." }
}
