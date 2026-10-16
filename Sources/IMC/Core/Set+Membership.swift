extension Set {
    /// Appartenenza scrivibile: `$selection[contains: id]` produce un
    /// `Binding<Bool>` per un `Toggle` senza un binding costruito a mano.
    subscript(contains element: Element) -> Bool {
        get { contains(element) }
        set {
            if newValue {
                insert(element)
            } else {
                remove(element)
            }
        }
    }
}
