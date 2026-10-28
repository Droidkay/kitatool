import SwiftUI

final class LocalBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// Drop-in replacement for @State that doesn't rely on the SwiftUI macro plugin,
/// so the app builds with just the Command Line Tools.
@propertyWrapper
struct Local<Value>: DynamicProperty {
    @StateObject private var box: LocalBox<Value>

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: LocalBox(wrappedValue))
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}
