import WidgetKit
import SwiftUI

@main
struct LyricsWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        LyricWidget()
        LyricWidgetLiveActivity()
    }
}
