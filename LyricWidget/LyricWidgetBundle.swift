import WidgetKit
import SwiftUI

@main
struct LyricsWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        LyricWidgetLiveActivity()
        // You can add more widgets here if needed
    }
}
