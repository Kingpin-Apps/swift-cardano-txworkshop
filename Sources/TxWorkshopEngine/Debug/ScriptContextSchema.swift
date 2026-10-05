import Foundation

/// The Plutus V2 and V3 script contexts as a CIP-57 blueprint, so a debugger
/// can show them by field name. Written from the Plutus ledger API
/// (`ScriptContext`, `TxInfo`, `ScriptInfo` …). Certificates and proposal
/// procedures are left as plain data.
enum ScriptContextSchema {
    /// The blueprint, read once.
    static let blueprint: Blueprint? = try? Blueprint(json: Data(json.utf8))

    /// The context's type for a Plutus version (2 or 3); `nil` for V1.
    static func schema(version: Int) -> BlueprintSchema? {
        blueprint?.validators.first { $0.title == "ledger.context_v\(version).else" }?.redeemer?.schema
    }

    static let json = #"""
    {
      "preamble": {"title": "Plutus V3 script context", "plutusVersion": "v3"},
      "validators": [
        {"title": "ledger.context_v3.else", "redeemer": {"title": "context", "schema": {"$ref": "#/definitions/ScriptContext"}}},
        {"title": "ledger.context_v2.else", "redeemer": {"title": "context", "schema": {"$ref": "#/definitions/ScriptContextV2"}}}],
      "definitions": {
        "Data": {"title": "Data"},
        "Int": {"dataType": "integer"},
        "ByteArray": {"dataType": "bytes"},
        "Bool": {"title": "Bool", "anyOf": [
          {"title": "False", "dataType": "constructor", "index": 0, "fields": []},
          {"title": "True", "dataType": "constructor", "index": 1, "fields": []}]},
        "Option$Int": {"title": "Option", "anyOf": [
          {"title": "Some", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/Int"}]},
          {"title": "None", "dataType": "constructor", "index": 1, "fields": []}]},
        "Option$ByteArray": {"title": "Option", "anyOf": [
          {"title": "Some", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/ByteArray"}]},
          {"title": "None", "dataType": "constructor", "index": 1, "fields": []}]},
        "Option$Data": {"title": "Option", "anyOf": [
          {"title": "Some", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/Data"}]},
          {"title": "None", "dataType": "constructor", "index": 1, "fields": []}]},
        "Option$StakingCredential": {"title": "Option", "anyOf": [
          {"title": "Some", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/StakingCredential"}]},
          {"title": "None", "dataType": "constructor", "index": 1, "fields": []}]},
        "ScriptContext": {"title": "ScriptContext", "anyOf": [
          {"title": "ScriptContext", "dataType": "constructor", "index": 0, "fields": [
            {"title": "transaction", "$ref": "#/definitions/TxInfo"},
            {"title": "redeemer", "$ref": "#/definitions/Data"},
            {"title": "info", "$ref": "#/definitions/ScriptInfo"}]}]},
        "TxInfo": {"title": "TxInfo", "anyOf": [
          {"title": "TxInfo", "dataType": "constructor", "index": 0, "fields": [
            {"title": "inputs", "$ref": "#/definitions/List$TxInInfo"},
            {"title": "reference_inputs", "$ref": "#/definitions/List$TxInInfo"},
            {"title": "outputs", "$ref": "#/definitions/List$TxOut"},
            {"title": "fee", "$ref": "#/definitions/Int"},
            {"title": "mint", "$ref": "#/definitions/Value"},
            {"title": "certificates", "$ref": "#/definitions/List$Data"},
            {"title": "withdrawals", "$ref": "#/definitions/Pairs$Credential_Int"},
            {"title": "validity_range", "$ref": "#/definitions/Interval"},
            {"title": "extra_signatories", "$ref": "#/definitions/List$ByteArray"},
            {"title": "redeemers", "$ref": "#/definitions/Pairs$ScriptPurpose_Data"},
            {"title": "datums", "$ref": "#/definitions/Pairs$ByteArray_Data"},
            {"title": "id", "$ref": "#/definitions/ByteArray"},
            {"title": "votes", "$ref": "#/definitions/Pairs$Voter_Votes"},
            {"title": "proposal_procedures", "$ref": "#/definitions/List$Data"},
            {"title": "current_treasury_amount", "$ref": "#/definitions/Option$Int"},
            {"title": "treasury_donation", "$ref": "#/definitions/Option$Int"}]}]},
        "List$TxInInfo": {"dataType": "list", "items": {"$ref": "#/definitions/TxInInfo"}},
        "List$TxOut": {"dataType": "list", "items": {"$ref": "#/definitions/TxOut"}},
        "List$Data": {"dataType": "list", "items": {"$ref": "#/definitions/Data"}},
        "List$ByteArray": {"dataType": "list", "items": {"$ref": "#/definitions/ByteArray"}},
        "Pairs$Credential_Int": {"title": "Pairs<Credential, Int>", "dataType": "map", "keys": {"$ref": "#/definitions/Credential"}, "values": {"$ref": "#/definitions/Int"}},
        "Pairs$ScriptPurpose_Data": {"title": "Pairs<ScriptPurpose, Data>", "dataType": "map", "keys": {"$ref": "#/definitions/ScriptPurpose"}, "values": {"$ref": "#/definitions/Data"}},
        "Pairs$ByteArray_Data": {"title": "Pairs<ByteArray, Data>", "dataType": "map", "keys": {"$ref": "#/definitions/ByteArray"}, "values": {"$ref": "#/definitions/Data"}},
        "Pairs$Voter_Votes": {"title": "Pairs<Voter, Pairs<GovActionId, Vote>>", "dataType": "map", "keys": {"$ref": "#/definitions/Voter"}, "values": {"$ref": "#/definitions/Pairs$GovActionId_Vote"}},
        "Pairs$GovActionId_Vote": {"title": "Pairs<GovActionId, Vote>", "dataType": "map", "keys": {"$ref": "#/definitions/GovActionId"}, "values": {"$ref": "#/definitions/Vote"}},
        "Value": {"title": "Value", "dataType": "map", "keys": {"title": "policy_id", "$ref": "#/definitions/ByteArray"}, "values": {"$ref": "#/definitions/Assets"}},
        "Assets": {"title": "Assets", "dataType": "map", "keys": {"title": "asset_name", "$ref": "#/definitions/ByteArray"}, "values": {"$ref": "#/definitions/Int"}},
        "TxInInfo": {"title": "Input", "anyOf": [
          {"title": "Input", "dataType": "constructor", "index": 0, "fields": [
            {"title": "output_reference", "$ref": "#/definitions/OutputReference"},
            {"title": "output", "$ref": "#/definitions/TxOut"}]}]},
        "OutputReference": {"title": "OutputReference", "anyOf": [
          {"title": "OutputReference", "dataType": "constructor", "index": 0, "fields": [
            {"title": "transaction_id", "$ref": "#/definitions/ByteArray"},
            {"title": "output_index", "$ref": "#/definitions/Int"}]}]},
        "TxOut": {"title": "Output", "anyOf": [
          {"title": "Output", "dataType": "constructor", "index": 0, "fields": [
            {"title": "address", "$ref": "#/definitions/Address"},
            {"title": "value", "$ref": "#/definitions/Value"},
            {"title": "datum", "$ref": "#/definitions/OutputDatum"},
            {"title": "reference_script", "$ref": "#/definitions/Option$ByteArray"}]}]},
        "Address": {"title": "Address", "anyOf": [
          {"title": "Address", "dataType": "constructor", "index": 0, "fields": [
            {"title": "payment_credential", "$ref": "#/definitions/Credential"},
            {"title": "stake_credential", "$ref": "#/definitions/Option$StakingCredential"}]}]},
        "Credential": {"title": "Credential", "anyOf": [
          {"title": "VerificationKey", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/ByteArray"}]},
          {"title": "Script", "dataType": "constructor", "index": 1, "fields": [{"$ref": "#/definitions/ByteArray"}]}]},
        "StakingCredential": {"title": "StakeCredential", "anyOf": [
          {"title": "Inline", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/Credential"}]},
          {"title": "Pointer", "dataType": "constructor", "index": 1, "fields": [
            {"title": "slot_number", "$ref": "#/definitions/Int"},
            {"title": "transaction_index", "$ref": "#/definitions/Int"},
            {"title": "certificate_index", "$ref": "#/definitions/Int"}]}]},
        "OutputDatum": {"title": "Datum", "anyOf": [
          {"title": "NoDatum", "dataType": "constructor", "index": 0, "fields": []},
          {"title": "DatumHash", "dataType": "constructor", "index": 1, "fields": [{"$ref": "#/definitions/ByteArray"}]},
          {"title": "InlineDatum", "dataType": "constructor", "index": 2, "fields": [{"$ref": "#/definitions/Data"}]}]},
        "Interval": {"title": "ValidityRange", "anyOf": [
          {"title": "Interval", "dataType": "constructor", "index": 0, "fields": [
            {"title": "lower_bound", "$ref": "#/definitions/Bound"},
            {"title": "upper_bound", "$ref": "#/definitions/Bound"}]}]},
        "Bound": {"title": "IntervalBound", "anyOf": [
          {"title": "IntervalBound", "dataType": "constructor", "index": 0, "fields": [
            {"title": "bound_type", "$ref": "#/definitions/BoundType"},
            {"title": "is_inclusive", "$ref": "#/definitions/Bool"}]}]},
        "BoundType": {"title": "IntervalBoundType", "anyOf": [
          {"title": "NegativeInfinity", "dataType": "constructor", "index": 0, "fields": []},
          {"title": "Finite", "dataType": "constructor", "index": 1, "fields": [{"title": "posix_time_ms", "$ref": "#/definitions/Int"}]},
          {"title": "PositiveInfinity", "dataType": "constructor", "index": 2, "fields": []}]},
        "ScriptPurpose": {"title": "ScriptPurpose", "anyOf": [
          {"title": "Mint", "dataType": "constructor", "index": 0, "fields": [{"title": "policy_id", "$ref": "#/definitions/ByteArray"}]},
          {"title": "Spend", "dataType": "constructor", "index": 1, "fields": [{"$ref": "#/definitions/OutputReference"}]},
          {"title": "Withdraw", "dataType": "constructor", "index": 2, "fields": [{"$ref": "#/definitions/Credential"}]},
          {"title": "Publish", "dataType": "constructor", "index": 3, "fields": [
            {"title": "at", "$ref": "#/definitions/Int"}, {"title": "certificate", "$ref": "#/definitions/Data"}]},
          {"title": "Vote", "dataType": "constructor", "index": 4, "fields": [{"$ref": "#/definitions/Voter"}]},
          {"title": "Propose", "dataType": "constructor", "index": 5, "fields": [
            {"title": "at", "$ref": "#/definitions/Int"}, {"title": "proposal", "$ref": "#/definitions/Data"}]}]},
        "ScriptInfo": {"title": "ScriptInfo", "anyOf": [
          {"title": "Minting", "dataType": "constructor", "index": 0, "fields": [{"title": "policy_id", "$ref": "#/definitions/ByteArray"}]},
          {"title": "Spending", "dataType": "constructor", "index": 1, "fields": [
            {"title": "output", "$ref": "#/definitions/OutputReference"}, {"title": "datum", "$ref": "#/definitions/Option$Data"}]},
          {"title": "Withdrawing", "dataType": "constructor", "index": 2, "fields": [{"$ref": "#/definitions/Credential"}]},
          {"title": "Publishing", "dataType": "constructor", "index": 3, "fields": [
            {"title": "at", "$ref": "#/definitions/Int"}, {"title": "certificate", "$ref": "#/definitions/Data"}]},
          {"title": "Voting", "dataType": "constructor", "index": 4, "fields": [{"$ref": "#/definitions/Voter"}]},
          {"title": "Proposing", "dataType": "constructor", "index": 5, "fields": [
            {"title": "at", "$ref": "#/definitions/Int"}, {"title": "proposal", "$ref": "#/definitions/Data"}]}]},
        "Voter": {"title": "Voter", "anyOf": [
          {"title": "ConstitutionalCommitteeMember", "dataType": "constructor", "index": 0, "fields": [{"$ref": "#/definitions/Credential"}]},
          {"title": "DelegateRepresentative", "dataType": "constructor", "index": 1, "fields": [{"$ref": "#/definitions/Credential"}]},
          {"title": "StakePool", "dataType": "constructor", "index": 2, "fields": [{"$ref": "#/definitions/ByteArray"}]}]},
        "GovActionId": {"title": "GovernanceActionId", "anyOf": [
          {"title": "GovernanceActionId", "dataType": "constructor", "index": 0, "fields": [
            {"title": "transaction", "$ref": "#/definitions/ByteArray"}, {"title": "proposal_procedure", "$ref": "#/definitions/Int"}]}]},
        "ScriptContextV2": {"title": "ScriptContext", "anyOf": [
          {"title": "ScriptContext", "dataType": "constructor", "index": 0, "fields": [
            {"title": "transaction", "$ref": "#/definitions/TxInfoV2"},
            {"title": "purpose", "$ref": "#/definitions/ScriptPurposeV2"}]}]},
        "TxInfoV2": {"title": "TxInfo", "anyOf": [
          {"title": "TxInfo", "dataType": "constructor", "index": 0, "fields": [
            {"title": "inputs", "$ref": "#/definitions/List$TxInInfoV2"},
            {"title": "reference_inputs", "$ref": "#/definitions/List$TxInInfoV2"},
            {"title": "outputs", "$ref": "#/definitions/List$TxOut"},
            {"title": "fee", "$ref": "#/definitions/Value"},
            {"title": "mint", "$ref": "#/definitions/Value"},
            {"title": "certificates", "$ref": "#/definitions/List$Data"},
            {"title": "withdrawals", "$ref": "#/definitions/Pairs$StakingCredential_Int"},
            {"title": "validity_range", "$ref": "#/definitions/Interval"},
            {"title": "extra_signatories", "$ref": "#/definitions/List$ByteArray"},
            {"title": "redeemers", "$ref": "#/definitions/Pairs$ScriptPurposeV2_Data"},
            {"title": "datums", "$ref": "#/definitions/Pairs$ByteArray_Data"},
            {"title": "id", "$ref": "#/definitions/TxId"}]}]},
        "List$TxInInfoV2": {"dataType": "list", "items": {"$ref": "#/definitions/TxInInfoV2"}},
        "TxInInfoV2": {"title": "Input", "anyOf": [
          {"title": "Input", "dataType": "constructor", "index": 0, "fields": [
            {"title": "output_reference", "$ref": "#/definitions/OutputReferenceV2"},
            {"title": "output", "$ref": "#/definitions/TxOut"}]}]},
        "OutputReferenceV2": {"title": "OutputReference", "anyOf": [
          {"title": "OutputReference", "dataType": "constructor", "index": 0, "fields": [
            {"title": "transaction_id", "$ref": "#/definitions/TxId"},
            {"title": "output_index", "$ref": "#/definitions/Int"}]}]},
        "TxId": {"title": "TransactionId", "anyOf": [
          {"title": "TransactionId", "dataType": "constructor", "index": 0, "fields": [{"title": "hash", "$ref": "#/definitions/ByteArray"}]}]},
        "Pairs$StakingCredential_Int": {"title": "Pairs<StakeCredential, Int>", "dataType": "map", "keys": {"$ref": "#/definitions/StakingCredential"}, "values": {"$ref": "#/definitions/Int"}},
        "Pairs$ScriptPurposeV2_Data": {"title": "Pairs<ScriptPurpose, Data>", "dataType": "map", "keys": {"$ref": "#/definitions/ScriptPurposeV2"}, "values": {"$ref": "#/definitions/Data"}},
        "ScriptPurposeV2": {"title": "ScriptPurpose", "anyOf": [
          {"title": "Mint", "dataType": "constructor", "index": 0, "fields": [{"title": "policy_id", "$ref": "#/definitions/ByteArray"}]},
          {"title": "Spend", "dataType": "constructor", "index": 1, "fields": [{"$ref": "#/definitions/OutputReferenceV2"}]},
          {"title": "Withdraw", "dataType": "constructor", "index": 2, "fields": [{"$ref": "#/definitions/StakingCredential"}]},
          {"title": "Publish", "dataType": "constructor", "index": 3, "fields": [{"title": "certificate", "$ref": "#/definitions/Data"}]}]},
        "Vote": {"title": "Vote", "anyOf": [
          {"title": "No", "dataType": "constructor", "index": 0, "fields": []},
          {"title": "Yes", "dataType": "constructor", "index": 1, "fields": []},
          {"title": "Abstain", "dataType": "constructor", "index": 2, "fields": []}]}
      }
    }
    """#
}
