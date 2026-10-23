import SwiftUI

// Keep the legacy view type compatible without reviving general-overview inference.
struct GeneralOverviewView: View {
    @Bindable var model: DashboardModel
    @Bindable var briefings: BriefingService
    var body: some View { TodayBriefView(model:model,briefings:briefings) }
}
