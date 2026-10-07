import SwiftUI
import TxWorkshopCore

/// Change, coin selection, validity, message, signers and fee buffer.
struct BuildOptionsSection: View {
    @Binding var recipe: BuildRecipe

    var body: some View {
        Section {
            ValueField(kind: .address, text: $recipe.changeAddress, prompt: Text("Change address (first source address if empty)", bundle: #bundle))
            Picker(selection: $recipe.coinSelection) {
                Text("Random-improve", bundle: #bundle).tag(BuildRecipe.CoinSelection.randomImprove)
                Text("Largest first", bundle: #bundle).tag(BuildRecipe.CoinSelection.largestFirst)
            } label: {
                Text("Coin selection", bundle: #bundle)
            }
            TWLabeledField(Text("Valid from slot", bundle: #bundle), value: $recipe.validFrom, format: .number)
            .font(TWFont.figure)
            TWLabeledField(Text("Valid until slot", bundle: #bundle), value: $recipe.validUntil, format: .number)
            .font(TWFont.figure)
            TWLabeledField(Text("Extra fee (lovelace)", bundle: #bundle), value: $recipe.feeBuffer, format: .number)
            .font(TWFont.figure)
        } header: {
            Text("Options", bundle: #bundle)
        }
        Section {
            TextEditor(text: $recipe.message)
                .frame(minHeight: 44, maxHeight: 100)
                .accessibilityLabel(Text("Message", bundle: #bundle))
        } header: {
            Text("Message (CIP-20)", bundle: #bundle)
        }
        Section {
            ValueLinesEditor(kind: .keyHash, lines: $recipe.requiredSigners, label: Text("Required signers, one per line", bundle: #bundle))
        } header: {
            Text("Required signers", bundle: #bundle)
        } footer: {
            Text("One per line: a key hash, an address, or read from a key file.", bundle: #bundle)
        }
        Section {
            ValueLinesEditor(kind: .transactionInput, lines: $recipe.collateral, label: Text("Collateral inputs, one per line", bundle: #bundle))
        } header: {
            Text("Collateral", bundle: #bundle)
        } footer: {
            Text("Inputs (transaction id#index), one per line. Left empty, the builder picks collateral from the source addresses when scripts run.", bundle: #bundle)
        }
    }
}
