import Foundation

struct NotebookMeta: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var coverAsset: String? // template or custom image name
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var pageCount: Int
}

struct FolderMeta: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var parentID: UUID?
    var colorHex: String?
}

struct PageMeta: Codable, Equatable, Identifiable {
    var id: UUID
    var notebookID: UUID
    var index: Int // 0-based order
    var size: PageSize
    var template: TemplateSpec
    var thumbnailName: String? // generated on save
}
