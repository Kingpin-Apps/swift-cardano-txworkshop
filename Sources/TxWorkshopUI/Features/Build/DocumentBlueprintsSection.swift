import SwiftUI
import TxWorkshopCore

/// The blueprints this document keeps a copy of, removable once no form or
/// script uses them. The app's own library is in Settings.
struct DocumentBlueprintsSection: View {
    @Binding var recipe: BuildRecipe

    var body: some View {
        if !recipe.blueprints.isEmpty {
            Section {
                ForEach(recipe.blueprints) { stored in
                    BlueprintLibraryRow(
                        stored: stored,
                        inUse: recipe.uses(blueprint: stored.id)
                            ? LocalizedStringResource("In use: clear the forms that use it first.", bundle: #bundle) : nil
                    ) {
                        recipe.blueprints.removeAll { $0.id == stored.id }
                    }
                }
            } header: {
                Text("Blueprints in this document", bundle: #bundle)
            } footer: {
                Text("Copies kept with the document, so its forms open the same anywhere. Settings keeps the app's own.", bundle: #bundle)
            }
        }
    }
}
