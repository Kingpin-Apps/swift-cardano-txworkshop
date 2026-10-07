import SwiftUI
import TxWorkshopCore

/// A field with its label small above the value, inside the row.
///
/// In a form, a field's label otherwise sits beside it, or stands in for it
/// while empty: a long label then squeezes or hides what is typed, and is gone
/// once the field is filled. Here the label stays, above, and the value has
/// the row's full width. The field keeps the label for VoiceOver.
struct TWLabeledField<Field: View>: View {
    let label: Text
    let field: Field

    init(_ label: Text, @ViewBuilder field: () -> Field) {
        self.label = label
        self.field = field()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TWSpacing.xxs) {
            label
                .font(.caption)
                .foregroundStyle(TWColor.secondaryText)
                .accessibilityHidden(true)
            field
                .labelsHidden()
        }
    }
}

extension TWLabeledField where Field == TextField<Text> {
    /// A text field, with `prompt` in it while it is empty.
    init(_ label: Text, text: Binding<String>, prompt: Text? = nil, axis: Axis = .horizontal) {
        self.init(label) { TextField(text: text, prompt: prompt, axis: axis) { label } }
    }

    /// A field for an optional value, such as a number left empty.
    init<F: ParseableFormatStyle>(_ label: Text, value: Binding<F.FormatInput?>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String {
        self.init(label) { TextField(value: value, format: format, prompt: prompt) { label } }
    }

    /// A field for a value that is always there.
    init<F: ParseableFormatStyle>(_ label: Text, value: Binding<F.FormatInput>, format: F, prompt: Text? = nil)
    where F.FormatOutput == String {
        self.init(label) { TextField(value: value, format: format, prompt: prompt) { label } }
    }
}

extension TWLabeledField where Field == SecureField<Text> {
    /// A field for a secret, such as an API key or a passphrase.
    init(_ label: Text, secret: Binding<String>) {
        self.init(label) { SecureField(text: secret) { label } }
    }
}
