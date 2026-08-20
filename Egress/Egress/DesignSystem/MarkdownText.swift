import SwiftUI

// MARK: - Inline markdown for runtime strings

extension AttributedString {
    /// Parse **inline** markdown (`**bold**`, `*italic*`, `` `code` ``) from a *runtime* string.
    ///
    /// `Text(someString)` renders a runtime `String` verbatim — so RALLY's coaching prose, which can
    /// carry `**bold**` emphasis, would otherwise show the literal asterisks. Running it through this
    /// turns the emphasis into real styling while preserving whitespace, and falls back to the plain
    /// string if parsing ever fails, so copy is never lost.
    static func coachMarkdown(_ string: String) -> AttributedString {
        (try? AttributedString(
            markdown: string,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(string)
    }
}

extension Text {
    /// A `Text` that renders inline markdown from a runtime string (see `AttributedString.coachMarkdown`).
    init(coach string: String) {
        self.init(AttributedString.coachMarkdown(string))
    }
}
