import Foundation

struct Subject: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: String = "indigo"
    var symbol: String = "book.closed"
}

struct MaterialPage: Identifiable, Codable, Equatable {
    var id = UUID()
    var number: Int
    var text: String
    var usedOCR: Bool = false
    var warning: String? = nil
}

struct Material: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID
    var name: String
    var storedFilename: String
    var pages: [MaterialPage]
    var importedAt = Date()
    var kind: String
    var warning: String? = nil
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID
    var title: String = "Untitled note"
    var text: String = ""
    var updatedAt = Date()
}

struct Assignment: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID
    var title: String
    var instructions: String = ""
    var dueDate: LocalDay = .today
    var isComplete: Bool = false
    var materialIDs: [UUID] = []
    var updatedAt = Date()
}

/// Gregorian date components, never a UTC midnight. Comparisons are calendar days.
struct LocalDay: Codable, Equatable, Comparable, Hashable {
    var year: Int
    var month: Int
    var day: Int
    static var today: LocalDay { LocalDay(Date()) }
    init(year: Int, month: Int, day: Int) { self.year = year; self.month = month; self.day = day }
    init(_ date: Date, calendar: Calendar = .current) {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = calendar.timeZone
        let parts = cal.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }
    func date(calendar: Calendar = .current) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = calendar.timeZone
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
    func adding(days: Int, calendar: Calendar = .current) -> LocalDay {
        LocalDay(calendar.date(byAdding: .day, value: days, to: date(calendar: calendar))!, calendar: calendar)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day) }
    var formatted: String { date().formatted(date: .abbreviated, time: .omitted) }
}

struct SourceReference: Identifiable, Codable, Equatable {
    /// Token provided to the model, e.g. S1. Valid only within a request.
    var id: String
    var materialID: UUID? = nil
    var noteID: UUID? = nil
    var assignmentID: UUID? = nil
    var title: String
    var page: Int? = nil
    var excerpt: String
    var passageID: String? = nil
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: String
    var text: String
    var sources: [SourceReference] = []
    var createdAt = Date()
    var status: String = "complete"
}

struct Conversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID? = nil
    var title: String = "New conversation"
    var messages: [ChatMessage] = []
    var updatedAt = Date()
}

enum StudyKind: String, Codable, CaseIterable, Identifiable {
    case flashcards, quiz
    var id: String { rawValue }
    var title: String { self == .flashcards ? "Flashcards" : "Practice quiz" }
}
struct Flashcard: Identifiable, Codable, Equatable {
    var id = UUID()
    var front: String
    var back: String
    var dueDate: LocalDay = .today
    var intervalDays: Int = 0
    var reviewCount: Int = 0
}
struct QuizQuestion: Identifiable, Codable, Equatable {
    var id = UUID()
    var prompt: String
    var options: [String] = []
    var answer: String
    var explanation: String
}
struct ReviewEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var cardID: UUID
    var rating: String
    var reviewedAt = Date()
}
struct QuizAttempt: Identifiable, Codable, Equatable {
    var id = UUID()
    var questionID: UUID
    var response: String
    var isCorrect: Bool
    var reviewedAt = Date()
}
struct StudySet: Identifiable, Codable, Equatable {
    var id = UUID()
    var subjectID: UUID? = nil
    var title: String
    var kind: StudyKind
    var cards: [Flashcard] = []
    var questions: [QuizQuestion] = []
    var reviews: [ReviewEvent] = []
    var attempts: [QuizAttempt] = []
    var createdAt = Date()
}

struct Library: Codable, Equatable {
    var schemaVersion: Int = 1
    var subjects: [Subject] = []
    var materials: [Material] = []
    var notes: [Note] = []
    var assignments: [Assignment] = []
    var conversations: [Conversation] = []
    var studySets: [StudySet] = []
}

struct AISettings: Codable, Equatable {
    var provider: ProviderKind = .ollama
    var model: String = ""
    var cloudConsent: Bool = false
}

enum ProviderKind: String, Codable, CaseIterable, Identifiable {
    case ollama, openRouter
    var id: String { rawValue }
    var title: String { self == .ollama ? "Ollama (local)" : "OpenRouter (cloud)" }
}
