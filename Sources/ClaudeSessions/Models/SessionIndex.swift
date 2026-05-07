import Foundation

struct SessionsIndex: Codable {
    let version: Int
    let originalPath: String?
    let entries: [SessionsIndexEntry]
}

struct SessionsIndexEntry: Codable {
    let sessionId: String
    let fullPath: String?
    let fileMtime: Int64?
    let firstPrompt: String?
    let summary: String?
    let messageCount: Int?
    let created: String?
    let modified: String?
    let gitBranch: String?
    let projectPath: String?
    let isSidechain: Bool?
}
