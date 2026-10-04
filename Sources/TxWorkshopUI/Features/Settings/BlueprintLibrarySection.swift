import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// The CIP-57 blueprints kept in the app, which any document's forms can use.
struct BlueprintLibrarySection: View {
    @Environment(BlueprintLibrary.self) private var library
    @State private var isImporting = false
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(library.blueprints) { stored in
                BlueprintLibraryRow(stored: stored) { library.remove(stored.id) }
            }
            if library.blueprints.isEmpty {
                Text("No blueprints yet.", bundle: #bundle)
                    .foregroundStyle(TWColor.secondaryText)
            }
            Button {
                isImporting = true
            } label: {
                Label {
                    Text("Import plutus.json…", bundle: #bundle)
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { importBlueprints(urls) }
            }
            if let problem { TWErrorText(problem) }
            if let error = library.lastError { TWErrorText(error) }
        } header: {
            Text("Blueprints", bundle: #bundle)
        } footer: {
            Text("A blueprint (plutus.json, from Aiken and other compilers) gives datums and redeemers typed forms. Kept here, it is offered in every document; a document keeps a copy of each one it uses.", bundle: #bundle)
        }
    }

    private func importBlueprints(_ urls: [URL]) {
        var failures: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                library.add(try BlueprintImport.read(url))
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }
        problem = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }
}

/// One kept blueprint: its title, version, compiler and validators.
private struct BlueprintLibraryRow: View {
    let stored: StoredBlueprint
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let blueprint = try? BlueprintCatalog.blueprint(stored) {
                VStack(alignment: .leading, spacing: TWSpacing.xs) {
                    Text(verbatim: [blueprint.preamble.title, blueprint.preamble.version].compactMap { $0 }.joined(separator: " "))
                    Text(verbatim: [blueprint.preamble.compiler, blueprint.preamble.plutusVersion.map { "Plutus V\($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                    Text(String(localized: "\(Set(blueprint.validators.compactMap(\.hash)).count) validators", bundle: #bundle))
                        .font(.caption)
                        .foregroundStyle(TWColor.secondaryText)
                }
            } else {
                Text("A blueprint that no longer reads", bundle: #bundle)
                    .foregroundStyle(TWColor.secondaryText)
            }
            Spacer()
            Button(role: .destructive, action: onRemove) {
                Label {
                    Text("Remove", bundle: #bundle)
                } icon: {
                    Image(systemName: "trash")
                }
                .labelStyle(.iconOnly)
                .twHitTarget()
            }
            .buttonStyle(.borderless)
        }
    }
}
