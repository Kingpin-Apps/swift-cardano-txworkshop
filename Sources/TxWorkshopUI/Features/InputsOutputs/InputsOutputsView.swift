import SwiftUI
import TxWorkshopCore
import TxWorkshopEngine

/// What the transaction spends, references and creates.
struct InputsOutputsView: View {
    let document: TxWorkshopDocument
    let inspection: LoadState<TransactionInspection>

    var body: some View {
        InspectionContainer(inspection: inspection, title: LocalizedStringResource("Inputs & Outputs", bundle: #bundle)) { inspection in
            Form {
                ChainLookupSection(document: document, inspection: inspection)
                InputSection(title: LocalizedStringResource("Inputs", bundle: #bundle), inputs: inspection.inputs)
                if !inspection.referenceInputs.isEmpty {
                    InputSection(title: LocalizedStringResource("Reference Inputs", bundle: #bundle), inputs: inspection.referenceInputs)
                }
                if !inspection.collateralInputs.isEmpty {
                    InputSection(title: LocalizedStringResource("Collateral", bundle: #bundle), inputs: inspection.collateralInputs)
                }
                ForEach(inspection.outputs) { output in
                    OutputSection(output: output, title: LocalizedStringResource("Output \(output.index)", bundle: #bundle))
                }
                if let collateralReturn = inspection.collateralReturn {
                    OutputSection(output: collateralReturn, title: LocalizedStringResource("Collateral Return", bundle: #bundle))
                }
                if !inspection.mint.isEmpty {
                    Section {
                        ForEach(inspection.mint) { asset in
                            AssetRow(asset: asset)
                        }
                    } header: {
                        Text("Minted & Burned", bundle: #bundle)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct InputSection: View {
    let title: LocalizedStringResource
    let inputs: [InputDetail]

    var body: some View {
        Section {
            ForEach(inputs) { input in
                InputRow(input: input)
            }
        } header: {
            Text("\(Text(title)) · \(inputs.count)", bundle: #bundle)
        }
    }
}
