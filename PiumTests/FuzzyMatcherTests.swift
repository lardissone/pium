import Testing
@testable import Pium

@Suite("Fuzzy matching")
struct FuzzyMatcherTests {
    private func score(_ query: String, _ candidate: String) -> Double {
        FuzzyMatcher.score(
            TextNormalizer.query(query),
            against: TextNormalizer.candidate(candidate)
        )
    }

    /// The PRD fixes this priority order: exact, prefix, whole word, acronym,
    /// then looser fuzzy. The test asserts the ordering, not the values, so
    /// weights stay tunable.
    @Test func scoresFollowThePrescribedPriorityOrder() {
        let exact = score("safari", "Safari")
        let prefix = score("saf", "Safari")
        let wholeWord = score("code", "Visual Studio Code")
        let acronym = score("vsc", "Visual Studio Code")
        let loose = score("vscd", "Visual Studio Code")

        #expect(exact > prefix)
        #expect(prefix > wholeWord)
        #expect(wholeWord > acronym)
        #expect(acronym > loose)
        #expect(loose > FuzzyMatcher.rejectionThreshold)
    }

    /// PIUM-111, a real search that found nothing: `yo n` did not reach
    /// `yo_nueva.jpg`. A query with a space in it was compared as one literal
    /// string, spaces and all, while candidates were split into words — so the
    /// space could only match a space, and a file named with an underscore had
    /// none to offer.
    @Test func aQueryOfSeveralWordsMatchesWordsSeparatedAnyWay() {
        #expect(score("yo n", "yo_nueva.jpg") > FuzzyMatcher.rejectionThreshold)
        #expect(score("yo nue", "yo_nueva.jpg") > FuzzyMatcher.rejectionThreshold)
        #expect(score("visual code", "Visual Studio Code") > FuzzyMatcher.rejectionThreshold)
        #expect(score("act mon", "Activity Monitor.app") > FuzzyMatcher.rejectionThreshold)
    }

    /// Every word has to land somewhere. Otherwise a second word would be free
    /// to be nonsense, and typing more would stop narrowing anything.
    @Test func everyWordOfAQueryHasToMatchSomething() {
        #expect(score("yo zzz", "yo_nueva.jpg") == 0)
        #expect(score("visual zzz", "Visual Studio Code") == 0)
    }

    @Test func anExactMatchScoresTheMaximum() {
        #expect(score("safari", "Safari") == 1.0)
    }

    /// Accents and case must not prevent a match.
    @Test func matchingIgnoresCaseAndAccents() {
        #expect(score("CODIGO", "Código") == 1.0)
        #expect(score("codigo", "Código") == 1.0)
    }

    /// Unrelated text must fall below the gate, or frecency in Phase 3 could
    /// float irrelevant results into view.
    @Test(arguments: ["xyz", "qqq", "zzzzzz"])
    func unrelatedQueriesAreRejected(query: String) {
        #expect(score(query, "Safari") <= FuzzyMatcher.rejectionThreshold)
    }

    /// An empty query matches nothing: the launcher shows no results until the
    /// user types.
    @Test func anEmptyQueryScoresZero() {
        #expect(score("", "Safari") == 0)
    }

    /// Characters must appear in order for a fuzzy match.
    @Test func outOfOrderCharactersDoNotMatch() {
        #expect(score("irafas", "Safari") <= FuzzyMatcher.rejectionThreshold)
    }

    /// A shorter candidate is the better match for the same query, so "Mail"
    /// beats "MailMate" for "mail".
    @Test func shorterCandidatesWinTies() {
        #expect(score("mail", "Mail") > score("mail", "MailMate"))
    }

    /// Alias and keyword lists are scored by taking the best of them.
    @Test func bestScoreTakesTheStrongestTerm() {
        let terms = ["Visual Studio Code", "vscode"].map(TextNormalizer.candidate)
        let best = FuzzyMatcher.bestScore(TextNormalizer.query("vscode"), againstAnyOf: terms)
        #expect(best == 1.0)
    }
}
