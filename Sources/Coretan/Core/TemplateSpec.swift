import Foundation

enum TemplateKind: String, Codable, CaseIterable {
    case blank, ruled, wideRuled, narrowRuled, grid, dotGrid, graph
    case cornell, music, plannerDaily, plannerWeekly, plannerMonthly
    case habitTracker, todoList, meetingNotes, studyNotes
    case math, calculus, statistics, table, diagram, custom
}

struct TemplateSpec: Codable, Equatable {
    var kind: TemplateKind
    var paperColorHex: String // e.g. "#FFFBF0"
    var lineSpacing: Float?   // points
    var gridSize: Float?      // points
    var orientationLocked: Bool

    static let blankA4 = TemplateSpec(kind: .blank, paperColorHex: "#FFFFFF", lineSpacing: nil, gridSize: nil, orientationLocked: false)
    static let ruled = TemplateSpec(kind: .ruled, paperColorHex: "#FFFEF7", lineSpacing: 24, gridSize: nil, orientationLocked: false)
    static let dotGrid = TemplateSpec(kind: .dotGrid, paperColorHex: "#FFFFFF", lineSpacing: nil, gridSize: 20, orientationLocked: false)
}
