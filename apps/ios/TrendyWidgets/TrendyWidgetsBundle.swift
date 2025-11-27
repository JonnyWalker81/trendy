//
//  TrendyWidgetsBundle.swift
//  TrendyWidgets
//
//  Widget extension bundle containing all Trendy widgets.
//

import WidgetKit
import SwiftUI

@main
struct TrendyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Home Screen Widgets
        SmallQuickLogWidget()
        MediumQuickLogWidget()
        LargeDashboardWidget()

        // Lock Screen Widgets
        CircularQuickLogWidget()
        RectangularStreakWidget()
        InlineStatWidget()
    }
}
