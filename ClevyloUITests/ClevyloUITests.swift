import XCTest

/// Uses only synthetic data in a unique workspace directory. No provider requests,
/// credentials, existing libraries, or global appearance preferences are changed.
final class ClevyloUITests: XCTestCase {
    private var app: XCUIApplication!
    private var dataDirectory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let workspace = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        dataDirectory = workspace.appendingPathComponent("build/UI-smoke/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["--data-dir", dataDirectory.path]
        app.launch()
        XCTAssertTrue(app.buttons["addSubject"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        if app != nil { app.terminate() }
    }

    func testLocalStudyWorkflowSurvivesRestartAndKeepsSubjectsSeparate() throws {
        createSubject("Biology Smoke")
        createNote(subject: "Biology Smoke", title: "Cell notes", body: "Membranes are selectively permeable. Biology-only material.")
        createAssignment(subject: "Biology Smoke", title: "Cell worksheet")

        createSubject("Algebra Smoke")
        createNote(subject: "Algebra Smoke", title: "Equation notes", body: "Do the same operation on both sides. Algebra-only material.")
        createAssignment(subject: "Algebra Smoke", title: "Equation worksheet")

        selectSubject("Biology Smoke")
        selectSection("Notes")
        XCTAssertTrue(app.staticTexts["Cell notes"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Equation notes"].exists)
        app.staticTexts["Cell notes"].firstMatch.click()
        XCTAssertTrue(editable("noteBody").waitForExistence(timeout: 5))
        XCTAssertTrue((editable("noteBody").value as? String ?? "").contains("Biology-only"))
        selectSection("Assignments")
        XCTAssertTrue(app.buttons["Complete Cell worksheet"].waitForExistence(timeout: 5))
        app.buttons["Complete Cell worksheet"].click()
        XCTAssertTrue(app.buttons["Mark Cell worksheet incomplete"].waitForExistence(timeout: 5))

        selectSubject("Algebra Smoke")
        selectSection("Assignments")
        XCTAssertTrue(app.buttons["Complete Equation worksheet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Cell worksheet"].exists)

        app.typeKey("3", modifierFlags: .command)
        let createDeck = app.buttons["Create flashcards"]
        XCTAssertTrue(createDeck.waitForExistence(timeout: 5))
        createDeck.click()
        XCTAssertTrue(app.staticTexts["Edit flashcards"].waitForExistence(timeout: 5))
        replaceText(in: editable("studySetTitle"), with: "Cell recall")
        replaceText(in: editable("flashcardFront"), with: "What does selectively permeable mean?")
        replaceText(in: editable("flashcardBack"), with: "Some substances cross a membrane more easily than others.")
        app.buttons["Save"].firstMatch.click()
        XCTAssertTrue(app.buttons["Review due cards"].waitForExistence(timeout: 5))
        app.buttons["Review due cards"].click()
        // Exercise the documented native shortcuts. On some macOS/XCTest versions,
        // reading a sheet descendant's label can stall the accessibility snapshot.
        // Verify the real persisted review before dismissing, rather than relying on
        // a visual completion label or modifying the store directly from the test.
        app.typeKey(.return, modifierFlags: [])
        app.typeKey("3", modifierFlags: [])
        waitForRecordedReview()
        app.typeKey(.escape, modifierFlags: [])
        waitForSave()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["addSubject"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Biology Smoke"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Algebra Smoke"].firstMatch.exists)
        selectSubject("Biology Smoke")
        selectSection("Notes")
        XCTAssertTrue(app.staticTexts["Cell notes"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Equation notes"].exists)
        app.staticTexts["Cell notes"].firstMatch.click()
        XCTAssertTrue((editable("noteBody").value as? String ?? "").contains("Biology-only"))
        selectSection("Assignments")
        XCTAssertTrue(app.buttons["Mark Cell worksheet incomplete"].waitForExistence(timeout: 5))

        selectSubject("Algebra Smoke")
        selectSection("Notes")
        XCTAssertTrue(app.staticTexts["Equation notes"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Cell notes"].exists)
        selectSection("Assignments")
        XCTAssertTrue(app.buttons["Complete Equation worksheet"].waitForExistence(timeout: 5))
        app.typeKey("3", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Cell recall"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Cell recall"].firstMatch.click()
        let reviewCount = app.descendants(matching: .any)["studyReviewCount"].firstMatch
        XCTAssertTrue(reviewCount.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["studyDueCount"].firstMatch.waitForExistence(timeout: 5))

        // Check actual persisted relationships and history, not only rendered labels.
        let bytes = try Data(contentsOf: dataDirectory.appendingPathComponent("library.json"))
        let library = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let subjects = try XCTUnwrap(library["subjects"] as? [[String: Any]])
        XCTAssertEqual(subjects.count, 2)
        let biologyID = try XCTUnwrap(subjects.first { $0["name"] as? String == "Biology Smoke" }?["id"] as? String)
        let algebraID = try XCTUnwrap(subjects.first { $0["name"] as? String == "Algebra Smoke" }?["id"] as? String)
        let notes = try XCTUnwrap(library["notes"] as? [[String: Any]])
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first { $0["title"] as? String == "Cell notes" }?["subjectID"] as? String, biologyID)
        XCTAssertEqual(notes.first { $0["title"] as? String == "Equation notes" }?["subjectID"] as? String, algebraID)
        let assignments = try XCTUnwrap(library["assignments"] as? [[String: Any]])
        XCTAssertEqual(assignments.count, 2)
        XCTAssertEqual(assignments.first { $0["title"] as? String == "Cell worksheet" }?["isComplete"] as? Bool, true)
        XCTAssertEqual(assignments.first { $0["title"] as? String == "Equation worksheet" }?["isComplete"] as? Bool, false)
        let decks = try XCTUnwrap(library["studySets"] as? [[String: Any]])
        let deck = try XCTUnwrap(decks.first { $0["title"] as? String == "Cell recall" })
        let reviews = try XCTUnwrap(deck["reviews"] as? [[String: Any]])
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?["rating"] as? String, "good")
        let card = try XCTUnwrap((deck["cards"] as? [[String: Any]])?.first)
        XCTAssertEqual(card["reviewCount"] as? Int, 1)
        XCTAssertEqual(card["intervalDays"] as? Int, 1)
        let dueDate = try XCTUnwrap(card["dueDate"] as? [String: Int])
        let reviewedAt = try XCTUnwrap(reviews.first?["reviewedAt"] as? Double)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let followingDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1,
                                                      to: Date(timeIntervalSinceReferenceDate: reviewedAt)))
        let expectedDay = calendar.dateComponents([.year, .month, .day], from: followingDay)
        XCTAssertEqual(dueDate["year"], expectedDay.year)
        XCTAssertEqual(dueDate["month"], expectedDay.month)
        XCTAssertEqual(dueDate["day"], expectedDay.day, "A first Good review must be due on the next local calendar day.")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Persisted study review"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func createSubject(_ name: String) {
        app.buttons["addSubject"].click()
        let field = app.textFields["subjectName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: name)
        app.buttons["saveSubject"].click()
        XCTAssertTrue(app.staticTexts[name].firstMatch.waitForExistence(timeout: 5))
    }

    private func selectSubject(_ name: String) {
        let item = app.staticTexts[name].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        XCTAssertTrue(app.descendants(matching: .any)["subjectSection"].firstMatch.waitForExistence(timeout: 5))
    }

    private func selectSection(_ name: String) {
        let section = app.descendants(matching: .any)["subjectSection"].firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        let match = section.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        if match.exists { match.click() }
        else if app.radioButtons[name].exists { app.radioButtons[name].click() }
        else { app.buttons[name].firstMatch.click() }
    }

    private func createNote(subject: String, title: String, body: String) {
        selectSubject(subject)
        app.typeKey("n", modifierFlags: .command)
        let titleField = app.textFields["noteTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        replaceText(in: titleField, with: title)
        replaceText(in: editable("noteBody"), with: body)
        waitForSave()
    }

    private func createAssignment(subject: String, title: String) {
        selectSubject(subject)
        selectSection("Assignments")
        let add = app.buttons["Add Assignment"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.click()
        let field = app.textFields["assignmentTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(in: field, with: title)
        app.buttons["saveAssignment"].click()
        XCTAssertTrue(app.buttons["Complete \(title)"].waitForExistence(timeout: 5))
        waitForSave()
    }

    private func editable(_ name: String) -> XCUIElement {
        let field = app.textFields[name].firstMatch
        if field.exists { return field }
        return app.textViews[name].firstMatch
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func waitForSave() {
        let status = app.descendants(matching: .any)["saveStatus"].firstMatch
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Saved locally"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 5), .completed)
    }

    private func waitForRecordedReview() {
        let url = dataDirectory.appendingPathComponent("library.json")
        let recorded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let bytes = try? Data(contentsOf: url),
                  let library = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
                  let sets = library["studySets"] as? [[String: Any]],
                  let deck = sets.first(where: { $0["title"] as? String == "Cell recall" }),
                  let reviews = deck["reviews"] as? [[String: Any]],
                  let cards = deck["cards"] as? [[String: Any]] else { return false }
            return reviews.count == 1 && reviews.first?["rating"] as? String == "good"
                && cards.first?["reviewCount"] as? Int == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recorded], timeout: 10), .completed,
                       "The keyboard review must persist an actual Good rating and updated card.")
    }
}
