import AppIntents
import WidgetKit

struct DismissJobIntent: AppIntent {
    static var title: LocalizedStringResource = "Dismiss Job"
    static var description = IntentDescription("Hides a job from the Job Hunt widget and app.")

    @Parameter(title: "Job ID")
    var jobID: String

    init() {
        jobID = ""
    }

    init(jobID: String) {
        self.jobID = jobID
    }

    func perform() async throws -> some IntentResult {
        DismissedStore.dismiss(jobID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
