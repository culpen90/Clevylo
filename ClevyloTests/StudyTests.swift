import XCTest
@testable import Clevylo

final class StudyTests: XCTestCase {
    private var utc: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testInitialReviewIntervalsAndReviewCount() {
        let day = LocalDay(year: 2026, month: 9, day: 23)
        let card = Flashcard(front: "What is a cell?", back: "A basic unit of life.")
        for (rating, days) in [(ReviewRating.again, 0), (.hard, 1), (.good, 1), (.easy, 3)] {
            let reviewed = StudyEngine.reviewed(card, rating: rating, on: day, calendar: utc)
            XCTAssertEqual(reviewed.intervalDays, days)
            XCTAssertEqual(reviewed.dueDate, day.adding(days: days, calendar: utc))
            XCTAssertEqual(reviewed.reviewCount, 1)
            XCTAssertEqual(reviewed.id, card.id)
            XCTAssertEqual(reviewed.front, card.front)
        }
        XCTAssertEqual(card.reviewCount, 0, "Scheduling must not mutate the input value.")
    }

    func testEstablishedIntervalsAndCap() {
        var card = Flashcard(front: "Front", back: "Back", intervalDays: 10, reviewCount: 5)
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .again).intervalDays, 0)
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .hard).intervalDays, 12)
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .good).intervalDays, 20)
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .easy).intervalDays, 30)
        card.intervalDays = Int.max
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .easy).intervalDays, 365)
        card.intervalDays = -10
        XCTAssertEqual(StudyEngine.reviewed(card, rating: .hard).intervalDays, 1)
    }

    func testSchedulingUsesCalendarDaysAcrossDaylightSaving() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let card = Flashcard(front: "Question", back: "Answer", intervalDays: 1)
        let result = StudyEngine.reviewed(card, rating: .good, on: LocalDay(year: 2026, month: 3, day: 7), calendar: eastern)
        XCTAssertEqual(result.dueDate, LocalDay(year: 2026, month: 3, day: 9))
        let yearEnd = StudyEngine.reviewed(card, rating: .good, on: LocalDay(year: 2026, month: 12, day: 31), calendar: eastern)
        XCTAssertEqual(yearEnd.dueDate, LocalDay(year: 2027, month: 1, day: 2))
    }

    func testDecodeValidFlashcardCreatesAppOwnedIDsAndSchedule() throws {
        let json = #"{"title":"Cells","cards":[{"front":"What is a cell?","back":"The basic unit of life."}],"questions":[]}"#
        let subjectID = UUID()
        let result = try StudyEngine.parseGenerated(json, kind: .flashcards, subjectID: subjectID, expectedCount: 1)
        XCTAssertEqual(result.title, "Cells")
        XCTAssertEqual(result.subjectID, subjectID)
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards[0].dueDate, .today)
        XCTAssertEqual(result.cards[0].reviewCount, 0)
        XCTAssertTrue(result.reviews.isEmpty)
    }

    func testDecodeMixedQuizQuestionTypes() throws {
        let json = #"{"title":"Biology","cards":[],"questions":[{"prompt":"Which stores DNA?","options":["Nucleus","Ribosome"],"answer":"Nucleus","explanation":"The nucleus holds most of a eukaryotic cell's DNA."},{"prompt":"Explain diffusion.","options":[],"answer":"Movement down a concentration gradient.","explanation":"Random motion produces a net movement from high to low concentration."}]}"#
        let result = try StudyEngine.parseGenerated(json, kind: .quiz, subjectID: nil, expectedCount: 2)
        XCTAssertEqual(result.questions.count, 2)
        XCTAssertTrue(result.questions[1].options.isEmpty)
        XCTAssertTrue(result.attempts.isEmpty)
    }

    func testMalformedOutputFailsBeforeAnyStudySetIsSaved() {
        let original = StudySet(title: "Keep me", kind: .flashcards, cards: [Flashcard(front: "Q", back: "A")])
        var library = Library(studySets: [original])
        let invalid = [
            "not JSON",
            #"{"title":"Empty","cards":[],"questions":[]}"#,
            #"{"title":"Bad card","cards":[{"front":"Q","back":" "}],"questions":[]}"#,
            #"{"title":"Missing field","cards":[{"front":"Q"}],"questions":[]}"#,
            #"{"title":"Wrong type","cards":null,"questions":[]}"#,
            #"{"title":"Mixed kind","cards":[{"front":"Q","back":"A"}],"questions":[{"prompt":"Q","options":[],"answer":"A","explanation":"E"}]}"#
        ]
        for response in invalid {
            do {
                let parsed = try StudyEngine.parseGenerated(response, kind: .flashcards, subjectID: nil, expectedCount: 1)
                library.studySets.append(parsed)
                XCTFail("Invalid data was accepted")
            } catch { }
            XCTAssertEqual(library.studySets, [original])
        }
    }

    func testWrongCountRejected() {
        let json = #"{"title":"Cells","cards":[{"front":"Q","back":"A"}],"questions":[]}"#
        XCTAssertThrowsError(try StudyEngine.parseGenerated(json, kind: .flashcards, subjectID: nil, expectedCount: 10))
    }

    func testInvalidMultipleChoiceAnswerAndDuplicateOptionsRejected() {
        var set = StudySet(title: "Quiz", kind: .quiz, questions: [QuizQuestion(prompt: "Q", options: ["A", "B"], answer: "C", explanation: "Why")])
        XCTAssertThrowsError(try StudyEngine.validate(set))
        set.questions[0].answer = "A"
        set.questions[0].options = ["A", " A "]
        XCTAssertThrowsError(try StudyEngine.validate(set))
        set.questions[0].options = ["A", "B"]
        XCTAssertNoThrow(try StudyEngine.validate(set))
    }

    func testActualReviewAndQuizHistoryRoundTrips() throws {
        let card = Flashcard(front: "Q", back: "A")
        let question = QuizQuestion(prompt: "Q", answer: "A", explanation: "Why")
        let deck = StudySet(title: "Deck", kind: .flashcards, cards: [StudyEngine.reviewed(card, rating: .good)],
                            reviews: [ReviewEvent(cardID: card.id, rating: "good")])
        let quiz = StudySet(title: "Quiz", kind: .quiz, questions: [question],
                            attempts: [QuizAttempt(questionID: question.id, response: "My attempt", isCorrect: false)])
        let library = Library(studySets: [deck, quiz])
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
        XCTAssertEqual(decoded.studySets[0].cards[0].reviewCount, 1)
        XCTAssertEqual(decoded.studySets[1].attempts[0].response, "My attempt")
        XCTAssertFalse(decoded.studySets[1].attempts[0].isCorrect)
    }

    func testGenerationRequestIncludesOnlyPassedSourcesAndSchema() {
        let source = SourceReference(id: "S1", title: "Selected note", excerpt: "Cell membranes are selectively permeable.")
        let request = StudyEngine.generationRequest(kind: .quiz, topic: "Cells", count: 5, difficulty: .standard, sources: [source])
        XCTAssertEqual(request.sources, [source])
        XCTAssertTrue(request.messages[0].text.contains("exactly 5"))
        XCTAssertEqual(request.structuredSchema?.name, "study_set")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(request.structuredSchema!.schema))
    }
}
