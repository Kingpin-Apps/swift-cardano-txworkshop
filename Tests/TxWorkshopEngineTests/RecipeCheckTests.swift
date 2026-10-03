import Foundation
import Testing
import TxWorkshopCore
@testable import TxWorkshopEngine

@Suite("Checking a recipe before building")
struct RecipeCheckTests {
    let address = "addr_test1vrm9x2zsux7va6w892g38tvchnzahvcd9tykqf3ygnmwtaqyfg52x"

    @Test("Empty certificates, a blank policy script and a blank output are each named where they are")
    func namesEachMistake() {
        let recipe = BuildRecipe(
            outputs: [OutputDraft(address: "")],
            changeAddress: address,
            mints: [MintDraft(script: .native(json: ""), assets: [AssetDraft(assetNameHex: "00")])],
            certificates: [
                CertificateItem(certificate: .registerStake(stakeAddress: "")),
                CertificateItem(certificate: .delegateStake(stakeAddress: "", pool: "")),
            ]
        )
        let problems = RecipeCheck.problems(recipe, network: .preprod).map(\.description)
        #expect(problems.contains("Output 1, Address: Empty."))
        #expect(problems.contains("Mint or burn 1, Policy script: Empty: give the native script's JSON, or choose its file."))
        #expect(problems.contains("Certificate 1 (Register stake address), Stake address: Empty."))
        #expect(problems.contains("Certificate 2 (Delegate stake to a pool), Stake address: Empty."))
        #expect(problems.contains("Certificate 2 (Delegate stake to a pool), Pool: Empty."))
    }

    @Test("A complete recipe has no problems")
    func completeRecipe() {
        let recipe = BuildRecipe(outputs: [OutputDraft(address: address, lovelace: 2_000_000)], changeAddress: address)
        #expect(RecipeCheck.problems(recipe, network: .preprod).isEmpty)
    }

    @Test("A wrong value says why, not just that it is wrong")
    func wrongValue() throws {
        let recipe = BuildRecipe(
            outputs: [OutputDraft(address: address)], changeAddress: address,
            withdrawals: [WithdrawalDraft(stakeAddress: "stake_test1nope")]
        )
        let problem = try #require(RecipeCheck.problems(recipe, network: .preprod).first)
        #expect(problem.place == "Withdrawal 1")
        #expect(problem.field == "Stake address")
        #expect(problem.message != "Empty.")
    }

    @Test("An empty recipe, and validity the wrong way round, are caught")
    func recipeLevel() {
        let problems = RecipeCheck.problems(BuildRecipe(validFrom: 200, validUntil: 100), network: .preprod).map(\.field)
        #expect(problems.contains("Change address"))
        #expect(problems.contains("Output"))
        #expect(problems.contains("Validity"))
    }
}
