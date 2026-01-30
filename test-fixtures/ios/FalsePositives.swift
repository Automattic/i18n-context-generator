import Foundation

/// Examples of patterns that should NOT be matched by the searcher.
/// These are false positives that look like localization but aren't.
class FalsePositives {

    // MARK: - String Comparisons (should NOT match)

    func stringComparisons() {
        let key = "common.save"

        // Equality comparisons - NOT localization usage
        if key == "common.save" {
            print("matched")
        }

        if "common.cancel" == key {
            print("matched")
        }

        // Inequality comparisons
        if key != "common.delete" {
            print("different")
        }

        if "common.loading" != key {
            print("different")
        }

        // Switch statement comparisons
        switch key {
        case "settings.title":
            break
        case "settings.logout":
            break
        default:
            break
        }
    }

    // MARK: - Dictionary/Collection Access (should NOT match)

    func dictionaryAccess() {
        let translations: [String: String] = [:]

        // Dictionary key access - NOT localization
        let value1 = translations["post.create"]
        let value2 = translations["post.delete.confirm"]

        // Dictionary assignment
        var dict: [String: Any] = [:]
        dict["profile.edit"] = "value"

        print(value1 ?? "", value2 ?? "")
    }

    // MARK: - Method Calls That Look Like Localization (should NOT match)

    func methodCallFalsePositives() {
        // .equals() style comparisons (Java-like, but possible in some Swift code)
        // This pattern exists in the FALSE_POSITIVE_PATTERNS
        let str = "test"
        _ = str.elementsEqual("error.network")

        // Contains checks
        let keys = ["a", "b", "c"]
        _ = keys.contains("error.unauthorized")

        // hasPrefix/hasSuffix
        _ = str.hasPrefix("error.")
        _ = str.hasSuffix(".confirm")
    }

    // MARK: - String Literals in Other Contexts (should NOT match)

    func otherContexts() {
        // Regex patterns
        let pattern = "post\\.comments"
        _ = try? NSRegularExpression(pattern: pattern)

        // URL components
        let urlString = "https://api.example.com/common/save"
        _ = URL(string: urlString)

        // JSON keys (when parsing, not localizing)
        let json = """
        {"key": "quickstart.title", "value": "test"}
        """
        print(json)

        // Logging/debugging
        print("Debug: key = common.done")
        debugPrint("settings.privacy")

        // Analytics event names (string literals, not localization)
        trackEvent("profile.photo.change")
    }

    // MARK: - Comments and Documentation (should NOT match)

    /// This documents the "common.save" key
    /// See also: "common.cancel" and "common.delete"
    func documentedFunction() {
        // The key "settings.title" is used for...
        /* Multi-line comment mentioning "profile.edit" */
    }

    // MARK: - Test Assertions (should NOT match)

    func testAssertions() {
        // XCTest assertions
        // XCTAssertEqual(key, "post.like")
        // XCTAssertNotEqual(result, "post.share")

        // String in test expectation
        let expected = "post.comments"
        assert(expected == "post.comments")
    }

    private func trackEvent(_ name: String) {}
}

// MARK: - Enum Raw Values (edge case - might be legitimate)

enum LocalizationKeys: String {
    case save = "common.save"
    case cancel = "common.cancel"
    case delete = "common.delete"
}
