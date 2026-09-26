import SwiftUI
import TxWorkshopCore

/// Change, coin selection, validity, message, signers and fee buffer.
struct BuildOptionsSection: View {
    @Binding var recipe: BuildRecipe
    @State private var signers = ""
    @State private var collateral = ""

    var body: some View {
        Section {
            TextField(text: $recipe.changeAddress) {
                Text("Change address (first source address if empty)", bundle: #bundle)
            }
            .font(TWFont.bytesSmall)
            .autocorrectionDisabled()
            Picker(selection: $recipe.coinSelection) {
                Text("Random-improve", bundle: #bundle).tag(BuildRecipe.CoinSelection.randomImprove)
                Text("Largest first", bundle: #bundle).tag(BuildRecipe.CoinSelection.largestFirst)
            } label: {
                Text("Coin selection", bundle: #bundle)
            }
            TextField(value: $recipe.validFrom, format: .number) {
                Text("Valid from slot", bundle: #bundle)
            }
            .font(TWFont.figure)
            TextField(value: $recipe.validUntil, format: .number) {
                Text("Valid until slot", bundle: #bundle)
            }
            .font(TWFont.figure)
            TextField(value: $recipe.feeBuffer, format: .number) {
                Text("Extra fee (lovelace)", bundle: #bundle)
            }
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
            TextEditor(text: $signers)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 100)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Required signers, one key hash per line", bundle: #bundle))
        } header: {
            Text("Required signers", bundle: #bundle)
        } footer: {
            Text("Key hashes in hex, one per line.", bundle: #bundle)
        }
        Section {
            TextEditor(text: $collateral)
                .font(TWFont.bytesSmall)
                .frame(minHeight: 44, maxHeight: 100)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("Collateral inputs, one per line", bundle: #bundle))
        } header: {
            Text("Collateral", bundle: #bundle)
        } footer: {
            Text("Inputs (transaction id#index), one per line. Left empty, the builder picks collateral from the source addresses when scripts run.", bundle: #bundle)
        }
        .onAppear {
            signers = recipe.requiredSigners.joined(separator: "\n")
            collateral = recipe.collateral.joined(separator: "\n")
        }
        .onChange(of: signers) { _, text in recipe.requiredSigners = SourcesSection.lines(text) }
        .onChange(of: collateral) { _, text in recipe.collateral = SourcesSection.lines(text) }
    }
}
