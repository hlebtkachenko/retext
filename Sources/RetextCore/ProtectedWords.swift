extension RetextSettings {
    /// Replaces the protected word `old` with the terms in `text` (split like a pasted list), in its place.
    /// Terms protected elsewhere in the list are dropped, so an edit into a duplicate removes the edited row,
    /// and an edit that leaves no terms removes it too. Unknown `old` or an unchanged word changes nothing.
    public mutating func editProtectedWord(_ old: String, to text: String) {
        guard let index = protectedWords.firstIndex(of: old) else { return }
        let others = Set(protectedWords).subtracting([old])
        let new = Self.terms(in: text).filter { !others.contains($0) }
        guard new != [old] else { return }
        protectedWords.replaceSubrange(index...index, with: new)
    }
}
