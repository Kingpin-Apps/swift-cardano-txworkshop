import Foundation
import SwiftCardanoCore
import SwiftNaCl
import TxWorkshopCore

/// A value the builder takes that can be given in several forms: bech32,
/// hex, a key or id file, a `pool.json`, a script file, and so on. The forms
/// follow those the `scm` command-line tool accepts.
public enum ValueKind: Sendable, Equatable {
    /// An address that can hold funds: base, enterprise, pointer or Byron. A
    /// payment key gives its enterprise address.
    case address
    /// A stake (reward) address. A base address gives its stake part; a stake
    /// key or stake key hash gives its reward address.
    case stakeAddress
    /// A stake pool, stored as its `pool1…` id.
    case pool
    /// Any DRep, including `abstain` and `no-confidence`.
    case drep
    /// A key-based DRep, stored as its key hash.
    case drepKeyHash
    /// A constitutional committee hot key, stored as its key hash.
    case committeeHotKeyHash
    /// A constitutional committee cold key, stored as its key hash.
    case committeeColdKeyHash
    /// A stake pool's VRF key, stored as its 32-byte hash.
    case vrfKeyHash
    /// A governance action, stored as `transaction id#index`.
    case govActionID
    /// A 32-byte Blake2b-256 anchor hash. A file gives the hash of its bytes.
    case anchorHash
    /// A minting policy id. A script file gives its hash.
    case policyID
    /// An asset name, stored as hex. Text that is not hex is taken as UTF-8.
    case assetName
    /// Plutus data (a datum or redeemer), stored as CBOR hex.
    case plutusData
    /// A Plutus script of the given version, stored as CBOR hex.
    case plutusScript(version: Int)
    /// A native script, stored as its JSON.
    case nativeScript
    /// A transaction output reference, stored as `transaction id#index`.
    case transactionInput
    /// Any key's hash, for a required signer: a key file, `addr_vkh1…`, hex,
    /// or an address (its payment key).
    case keyHash
}

/// A value read from what was given.
public struct ReadValue: Sendable, Equatable {
    /// The value as the recipe stores it and the builder reads it.
    public let value: String
    /// What the input was recognised as, for showing beside the field.
    public let form: String
}

public struct ValueReadError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = description }
}

/// Reads the values the builder takes from whatever form they were given in.
public enum ValueReader {
    /// The network of the transaction being built, for reads made while
    /// composing it.
    @TaskLocal static var buildNetwork: CardanoNetwork?

    /// `text` as a value of `kind` on the network being built, or `failure`.
    static func value(_ kind: ValueKind, _ text: String, or failure: (String) -> ComposeError) throws -> String {
        do {
            return try read(kind, text: text, network: buildNetwork).value
        } catch let error as ValueReadError {
            throw failure(error.description)
        }
    }

    /// `text` as a value of `kind`. `network` turns key hashes and keys into
    /// addresses, and addresses on another network are refused.
    public static func read(_ kind: ValueKind, text: String, network: CardanoNetwork?) throws -> ReadValue {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ValueReadError("Nothing entered.") }
        switch kind {
        case .address: return try address(text, network: network)
        case .stakeAddress: return try stakeAddress(text, network: network)
        case .pool: return try pool(text)
        case .drep: return try drep(text)
        case .drepKeyHash: return try drepKeyHash(text)
        case .committeeHotKeyHash: return try committeeHotKeyHash(text)
        case .committeeColdKeyHash: return try committeeColdKeyHash(text)
        case .vrfKeyHash: return try vrfKeyHash(text)
        case .govActionID: return try govActionID(text)
        case .anchorHash: return try anchorHash(text)
        case .policyID: return try policyID(text)
        case .assetName: return try assetName(text)
        case .plutusData: return try plutusData(text)
        case .plutusScript(let version): return try plutusScript(text, version: version)
        case .nativeScript: return try nativeScript(text)
        case .transactionInput: return try transactionInput(text)
        case .keyHash: return try anyKeyHash(text)
        }
    }

    /// A file's contents as a value of `kind`. Text files (`.addr`, `.vkey`,
    /// `.skey`, id files, JSON) are read as their text; a binary file as CBOR;
    /// for an anchor hash, any file is hashed.
    /// `folder` is the file's own folder, where a pool.json's key files are
    /// looked for.
    public static func read(
        _ kind: ValueKind, file data: Data, name: String, network: CardanoNetwork?, folder: URL? = nil
    ) throws -> ReadValue {
        guard !data.isEmpty else { throw ValueReadError("\(name) is empty.") }
        if kind == .anchorHash {
            return ReadValue(value: blake2b(data, size: 32).hex, form: "Blake2b-256 of \(name)")
        }
        if kind == .pool, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let read = try poolJSON(json, folder: folder, name: name)
            return ReadValue(value: read.value, form: "\(read.form), from \(name)")
        }
        if let text = String(data: data, encoding: .utf8) {
            let read = try read(kind, text: text, network: network)
            return ReadValue(value: read.value, form: "\(read.form), from \(name)")
        }
        switch kind {
        case .plutusData:
            let data = try? PlutusData.fromCBOR(data: data)
            guard let data else { throw ValueReadError("\(name) is not Plutus data in CBOR.") }
            return ReadValue(value: try data.toCBORData().hex, form: "Plutus data, from \(name)")
        case .plutusScript(let version):
            return try plutusScript(data.hex, version: version, form: "Plutus V\(version) script, from \(name)")
        default:
            throw ValueReadError("\(name) is not a text file.")
        }
    }

    // MARK: Addresses

    static func address(_ text: String, network: CardanoNetwork?) throws -> ReadValue {
        if let key = try KeyFile(text) {
            guard key.role == .payment else {
                throw ValueReadError("A \(key.role.name) key has no payment address. Use a payment key or an address.")
            }
            let address = try Address(paymentPart: .verificationKeyHash(key.hash), network: try networkID(network, for: "a payment key"))
            return ReadValue(value: try address.toBech32(), form: "Enterprise address, from a payment \(key.kindName)")
        }
        let (address, fromHex) = try parseAddress(text)
        if address.addressType?.rawValue == 14 || address.addressType?.rawValue == 15 {
            throw ValueReadError("A stake address can't hold funds. Use a payment address.")
        }
        try check(address, network: network)
        return ReadValue(value: canonical(address, original: text), form: describe(address) + (fromHex ? " (hex)" : ""))
    }

    static func stakeAddress(_ text: String, network: CardanoNetwork?) throws -> ReadValue {
        if let key = try KeyFile(text) {
            guard key.role == .stake else {
                throw ValueReadError("A \(key.role.name) key is not a stake key.")
            }
            let address = try Address(stakingPart: .verificationKeyHash(key.hash), network: try networkID(network, for: "a stake key"))
            return ReadValue(value: try address.toBech32(), form: "Stake address, from a stake \(key.kindName)")
        }
        if let bytes = hexBytes(text), bytes.count == 28 {
            let address = try Address(
                stakingPart: .verificationKeyHash(VerificationKeyHash(payload: bytes)),
                network: try networkID(network, for: "a stake key hash")
            )
            return ReadValue(value: try address.toBech32(), form: "Stake address, from a stake key hash")
        }
        if let key = try bech32Key(text, prefixes: ["stake_vk", "stake_xvk"]) {
            let address = try Address(stakingPart: .verificationKeyHash(keyHash(key)), network: try networkID(network, for: "a stake key"))
            return ReadValue(value: try address.toBech32(), form: "Stake address, from a stake verification key")
        }
        let (address, fromHex) = try parseAddress(text)
        try check(address, network: network)
        guard let stakingPart = address.stakingPart else {
            throw ValueReadError("This address has no stake part.")
        }
        if address.paymentPart == nil {
            return ReadValue(value: try address.toBech32(), form: "Stake address" + (fromHex ? " (hex)" : ""))
        }
        guard case .pointerAddress = stakingPart else {
            let stake = try Address(stakingPart: stakingPart, network: address.network)
            return ReadValue(value: try stake.toBech32(), form: "Stake address of a base address")
        }
        throw ValueReadError("A pointer address has no stake credential to use.")
    }

    static func parseAddress(_ text: String) throws -> (Address, fromHex: Bool) {
        if let bytes = hexBytes(text), bytes.count > 28 {
            guard let address = try? Address(from: .bytes(bytes)) else { throw ValueReadError("That hex is not an address.") }
            return (address, true)
        }
        guard let address = try? Address(from: .string(text)) else {
            throw ValueReadError("Not an address. Enter bech32 (addr…, stake…), hex, or choose an address or key file.")
        }
        return (address, false)
    }

    static func check(_ address: Address, network: CardanoNetwork?) throws {
        guard let network, address.addressType?.rawValue != 8 else { return }
        let expected: NetworkId = network == .mainnet ? .mainnet : .testnet
        guard address.network == expected else {
            throw ValueReadError(address.network == .mainnet
                ? "This is a mainnet address, but the document is on \(network.id)."
                : "This is a testnet address, but the document is on mainnet.")
        }
    }

    static func canonical(_ address: Address, original: String) -> String {
        address.addressType?.rawValue == 8 ? original : ((try? address.toBech32()) ?? original)
    }

    static func describe(_ address: Address) -> String {
        switch address.addressType?.rawValue ?? -1 {
        case 0...3: "Base address"
        case 4, 5: "Pointer address"
        case 6, 7: "Enterprise address"
        case 8: "Byron address"
        case 14, 15: "Stake address"
        default: "Address"
        }
    }

    static func networkID(_ network: CardanoNetwork?, for what: String) throws -> NetworkId {
        guard let network else { throw ValueReadError("Choose the document's network to turn \(what) into an address.") }
        return network == .mainnet ? .mainnet : .testnet
    }

    // MARK: Pools

    /// The keys a pool.json, or a provider's pool record, gives the id under.
    static let poolIDKeys = ["id_bech", "id_hex", "pool_id_bech32", "pool_id_hex", "pool_id", "poolId", "pool"]

    /// The pool a pool.json names: by its id, or by its cold key, read from
    /// the path it gives, relative to `folder`.
    static func poolJSON(_ json: [String: Any], folder: URL?, name: String) throws -> ReadValue {
        for key in poolIDKeys {
            if let id = (json[key] as? String)?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
                return try relabel(pool(id), "Pool, from pool.json")
            }
        }
        if let path = (json["cold_vkey"] as? String)?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            let url = path.hasPrefix("/") || path.hasPrefix("~")
                ? URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                : folder.map { $0.appendingPathComponent(path) } ?? URL(fileURLWithPath: path)
            guard let key = try? String(contentsOf: url, encoding: .utf8) else {
                throw ValueReadError("\(name) names its cold key as \(path), which can't be read here. Choose that cold key file, or enter the pool id.")
            }
            return try relabel(pool(key), "Pool, from pool.json's cold key")
        }
        if json["ticker"] != nil || json["homepage"] != nil {
            throw ValueReadError("\(name) is the pool's metadata, which doesn't say which pool it is. Enter the pool id, or choose its pool.json or cold key file.")
        }
        throw ValueReadError("\(name) doesn't name a pool: it has no pool id or cold key.")
    }

    static func pool(_ text: String) throws -> ReadValue {
        if let key = try KeyFile(text) {
            guard key.role == .stakePool else {
                throw ValueReadError(key.role == .vrf
                    ? "That is the pool's VRF key. Use its cold key (the node or cold .vkey)."
                    : "A \(key.role.name) key is not a pool cold key.")
            }
            return try poolValue(PoolKeyHash(payload: key.hash.payload), form: "Pool, from its cold \(key.kindName)")
        }
        if let json = jsonObject(text) {
            return try poolJSON(json, folder: nil, name: "That JSON")
        }
        if text.hasPrefix("pool1") {
            guard let pool = try? PoolOperator(from: text) else { throw ValueReadError("That is not a valid pool id.") }
            return ReadValue(value: try pool.toBech32(), form: "Pool id")
        }
        if let key = try bech32Key(text, prefixes: ["pool_vk", "pool_xvk"]) {
            return try poolValue(PoolKeyHash(payload: keyHash(key).payload), form: "Pool, from its cold verification key")
        }
        if let bytes = hexBytes(text) {
            switch bytes.count {
            case 28: return try poolValue(PoolKeyHash(payload: bytes), form: "Pool id (hex)")
            case 32, 64: return try poolValue(PoolKeyHash(payload: keyHash(bytes.prefix(32)).payload), form: "Pool, from its cold key (hex)")
            default: break
            }
        }
        throw ValueReadError("Not a pool. Enter pool1…, pool_vk1…, a 56-character hex id, or choose a pool.json, pool id or cold key file.")
    }

    static func poolValue(_ hash: PoolKeyHash, form: String) throws -> ReadValue {
        ReadValue(value: try PoolOperator(poolKeyHash: hash).toBech32(), form: form)
    }

    // MARK: Governance

    static func drep(_ text: String) throws -> ReadValue {
        switch text.lowercased() {
        case "abstain", "always-abstain", "alwaysabstain", "drep_always_abstain":
            return ReadValue(value: "abstain", form: "Always abstain")
        case "no-confidence", "noconfidence", "always-no-confidence", "alwaysnoconfidence", "drep_always_no_confidence":
            return ReadValue(value: "no-confidence", form: "Always no confidence")
        default:
            break
        }
        if text.lowercased().hasPrefix("drep"), !text.lowercased().hasPrefix("drep_vk"), !text.lowercased().hasPrefix("drep_xvk") {
            guard let drep = try? DRep(from: text) else { throw ValueReadError("That is not a valid DRep id.") }
            return ReadValue(value: try drep.id(), form: describe(drep))
        }
        if let bytes = hexBytes(text), bytes.count == 29 {
            guard let drep = try? DRep(from: bytes) else { throw ValueReadError("That hex is not a CIP-129 DRep id.") }
            return ReadValue(value: try drep.id(), form: describe(drep) + " (CIP-129 hex)")
        }
        let key = try drepKey(text)
        let drep = DRep(credential: .verificationKeyHash(key.hash))
        return ReadValue(value: try drep.id(), form: key.form)
    }

    static func drepKeyHash(_ text: String) throws -> ReadValue {
        if text.lowercased().hasPrefix("drep"), !text.lowercased().hasPrefix("drep_vk"), !text.lowercased().hasPrefix("drep_xvk") {
            guard let drep = try? DRep(from: text) else { throw ValueReadError("That is not a valid DRep id.") }
            return try drepHashValue(drep, form: "DRep key hash, from its id")
        }
        if let bytes = hexBytes(text), bytes.count == 29 {
            guard let drep = try? DRep(from: bytes) else { throw ValueReadError("That hex is not a CIP-129 DRep id.") }
            return try drepHashValue(drep, form: "DRep key hash, from its CIP-129 id")
        }
        let key = try drepKey(text)
        return ReadValue(value: key.hash.payload.hex, form: key.form.replacingOccurrences(of: "DRep", with: "DRep key hash"))
    }

    static func drepHashValue(_ drep: DRep, form: String) throws -> ReadValue {
        switch drep.credential {
        case .verificationKeyHash(let hash): return ReadValue(value: hash.payload.hex, form: form)
        case .scriptHash: throw ValueReadError("That is a script DRep; this needs a key-based DRep.")
        default: throw ValueReadError("That is not a key-based DRep.")
        }
    }

    /// A DRep key from a key file, a `drep_vk1…` key or a 28-byte hex hash.
    static func drepKey(_ text: String) throws -> (hash: VerificationKeyHash, form: String) {
        if let key = try KeyFile(text) {
            guard key.role == .drep else { throw ValueReadError("A \(key.role.name) key is not a DRep key.") }
            return (key.hash, "DRep, from its \(key.kindName)")
        }
        if let key = try bech32Key(text, prefixes: ["drep_vk", "drep_xvk"]) {
            return (keyHash(key), "DRep, from its verification key")
        }
        if let bytes = hexBytes(text), bytes.count == 28 {
            return (VerificationKeyHash(payload: bytes), "DRep key hash (hex)")
        }
        throw ValueReadError("Not a DRep. Enter drep1…, a 56-character hex key hash, abstain or no-confidence, or choose a DRep id or key file.")
    }

    static func describe(_ drep: DRep) -> String {
        switch drep.credential {
        case .verificationKeyHash: "DRep id"
        case .scriptHash: "Script DRep id"
        case .alwaysAbstain: "Always abstain"
        case .alwaysNoConfidence: "Always no confidence"
        }
    }

    static func committeeHotKeyHash(_ text: String) throws -> ReadValue {
        if let key = try KeyFile(text) {
            guard key.role == .committeeHot else {
                throw ValueReadError(key.role == .committeeCold
                    ? "That is a committee cold key. Votes are cast with the hot key."
                    : "A \(key.role.name) key is not a committee hot key.")
            }
            return ReadValue(value: key.hash.payload.hex, form: "Committee hot key hash, from its \(key.kindName)")
        }
        if let key = try bech32Key(text, prefixes: ["cc_hot_vk", "cc_hot_xvk"]) {
            return ReadValue(value: keyHash(key).payload.hex, form: "Committee hot key hash, from its verification key")
        }
        if text.lowercased().hasPrefix("cc_hot") {
            guard let (hrp, data) = bech32(text) else { throw ValueReadError("That is not a valid committee hot id.") }
            switch (hrp, data.count) {
            case ("cc_hot", 29) where data[0] == 0x02: return ReadValue(value: data.dropFirst().hex, form: "Committee hot id (CIP-129)")
            case ("cc_hot", 28): return ReadValue(value: data.hex, form: "Committee hot id")
            case ("cc_hot_script", _), ("cc_hot", 29): throw ValueReadError("That is a script committee credential; this needs a key.")
            default: throw ValueReadError("That is not a valid committee hot id.")
            }
        }
        if let bytes = hexBytes(text), bytes.count == 28 {
            return ReadValue(value: bytes.hex, form: "Committee hot key hash (hex)")
        }
        throw ValueReadError("Not a committee hot key. Enter cc_hot1…, a 56-character hex key hash, or choose the hot key file.")
    }

    static func committeeColdKeyHash(_ text: String) throws -> ReadValue {
        if let key = try KeyFile(text) {
            guard key.role == .committeeCold else {
                throw ValueReadError(key.role == .committeeHot
                    ? "That is a committee hot key. This needs the cold key."
                    : "A \(key.role.name) key is not a committee cold key.")
            }
            return ReadValue(value: key.hash.payload.hex, form: "Committee cold key hash, from its \(key.kindName)")
        }
        if let key = try bech32Key(text, prefixes: ["cc_cold_vk", "cc_cold_xvk"]) {
            return ReadValue(value: keyHash(key).payload.hex, form: "Committee cold key hash, from its verification key")
        }
        if text.lowercased().hasPrefix("cc_cold") {
            guard let (hrp, data) = bech32(text) else { throw ValueReadError("That is not a valid committee cold id.") }
            switch (hrp, data.count) {
            case ("cc_cold", 29) where data[0] == 0x12: return ReadValue(value: data.dropFirst().hex, form: "Committee cold id (CIP-129)")
            case ("cc_cold", 28): return ReadValue(value: data.hex, form: "Committee cold id")
            case ("cc_cold_script", _), ("cc_cold", 29): throw ValueReadError("That is a script committee credential; this needs a key.")
            default: throw ValueReadError("That is not a valid committee cold id.")
            }
        }
        if let bytes = hexBytes(text), bytes.count == 28 {
            return ReadValue(value: bytes.hex, form: "Committee cold key hash (hex)")
        }
        throw ValueReadError("Not a committee cold key. Enter cc_cold1…, a 56-character hex key hash, or choose the cold key file.")
    }

    /// A VRF key's hash: Blake2b-256 of its 32-byte verification key.
    static func vrfKeyHash(_ text: String) throws -> ReadValue {
        if let json = jsonObject(text), let type = json["type"] as? String {
            guard type.hasPrefix("Vrf") else { throw ValueReadError("That key file is not a VRF key.") }
            guard let cborHex = json["cborHex"] as? String, let cbor = try? TxDocumentCodec.bytes(fromHex: cborHex),
                case .bytes(let payload)? = try? Primitive.fromCBOR(data: cbor), payload.count == 32 || payload.count == 64
            else { throw ValueReadError("That VRF key file has no readable key.") }
            // A VRF signing key is the seed followed by the verification key.
            let vkey = payload.count == 32 ? payload : payload.suffix(32)
            let kind = type.contains("Signing") ? "signing key" : "verification key"
            return ReadValue(value: blake2b(vkey, size: 32).hex, form: "VRF key hash, from its \(kind)")
        }
        if let key = try bech32Key(text, prefixes: ["vrf_vk"]) {
            return ReadValue(value: blake2b(key.prefix(32), size: 32).hex, form: "VRF key hash, from its verification key")
        }
        if let bytes = hexBytes(text), bytes.count == 32 {
            return ReadValue(value: bytes.hex, form: "VRF key hash (hex)")
        }
        throw ValueReadError("Not a VRF key. Enter the 64-character hex VRF key hash, vrf_vk1…, or choose the VRF key file.")
    }

    static func govActionID(_ text: String) throws -> ReadValue {
        let action: GovActionID
        let form: String
        if text.lowercased().hasPrefix("gov_action") {
            guard let parsed = try? GovActionID(from: text) else { throw ValueReadError("That is not a valid gov_action id.") }
            (action, form) = (parsed, "Governance action id (CIP-129)")
        } else if text.contains("#") {
            let parts = text.split(separator: "#")
            guard parts.count == 2, let index = UInt16(parts[1]), let id = hexBytes(String(parts[0])), id.count == 32 else {
                throw ValueReadError("A governance action is its transaction id#index.")
            }
            (action, form) = (GovActionID(transactionID: TransactionId(payload: id), govActionIndex: index), "Governance action")
        } else if let bytes = hexBytes(text), bytes.count == 33 || bytes.count == 34 {
            guard let parsed = try? GovActionID(from: bytes) else { throw ValueReadError("That hex is not a governance action id.") }
            (action, form) = (parsed, "Governance action id (hex)")
        } else {
            throw ValueReadError("Not a governance action. Enter gov_action1…, transaction id#index, or choose a gov action id file.")
        }
        return ReadValue(value: "\(action.transactionID.payload.hex)#\(action.govActionIndex)", form: form)
    }

    static func anchorHash(_ text: String) throws -> ReadValue {
        guard let bytes = hexBytes(text), bytes.count == 32 else {
            throw ValueReadError("An anchor hash is 64 hex characters. Or choose the anchor's file to hash it.")
        }
        return ReadValue(value: bytes.hex, form: "Blake2b-256 hash")
    }

    /// The Blake2b-256 hash of the document at `url`, as an anchor hash.
    /// `ipfs://` URLs are fetched through `gateway`.
    public static func anchorHash(downloading url: String, gateway: URL = URL(string: "https://ipfs.io/")!) async throws -> ReadValue {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let fetchURL: URL?
        if trimmed.hasPrefix("ipfs://") {
            fetchURL = URL(string: "ipfs/" + trimmed.dropFirst("ipfs://".count), relativeTo: gateway)?.absoluteURL
        } else {
            fetchURL = URL(string: trimmed)
        }
        guard let fetchURL, fetchURL.scheme == "https" || fetchURL.scheme == "http" else {
            throw ValueReadError("Enter an http(s) or ipfs:// anchor URL first.")
        }
        let (data, response) = try await URLSession.shared.data(from: fetchURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ValueReadError("The anchor URL did not answer with its document.")
        }
        return ReadValue(value: blake2b(data, size: 32).hex, form: "Blake2b-256 of the document at the URL (\(data.count) bytes)")
    }

    // MARK: Assets and scripts

    static func policyID(_ text: String) throws -> ReadValue {
        if let bytes = hexBytes(text), bytes.count == 28 {
            return ReadValue(value: bytes.hex, form: "Policy id")
        }
        if let json = jsonObject(text) {
            if json["cborHex"] != nil {
                let type = json["type"] as? String ?? ""
                guard let version = Int(type.replacingOccurrences(of: "PlutusScriptV", with: "")), type.hasPrefix("PlutusScriptV") else {
                    throw ValueReadError("A \(type) is not a script.")
                }
                let script = try TransactionComposer.plutusScript(version: version, hex: json["cborHex"] as? String ?? "")
                return ReadValue(value: try scriptHash(script: script).payload.hex, form: "Policy id, from a Plutus V\(version) script")
            }
            guard let native = try? NativeScript.fromJSON(text) else { throw ValueReadError("That JSON is not a script.") }
            return ReadValue(value: try scriptHash(script: .nativeScript(native)).payload.hex, form: "Policy id, from a native script")
        }
        throw ValueReadError("A policy id is 56 hex characters. Or choose a policy script or policy.id file.")
    }

    static func assetName(_ text: String) throws -> ReadValue {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            return try textName(String(text.dropFirst().dropLast()))
        }
        if let bytes = hexBytes(text) {
            guard bytes.count <= 32 else { throw ValueReadError("An asset name is at most 32 bytes.") }
            return ReadValue(value: bytes.hex, form: "Asset name (hex)")
        }
        return try textName(text)
    }

    static func textName(_ text: String) throws -> ReadValue {
        let bytes = Data(text.utf8)
        guard bytes.count <= 32 else { throw ValueReadError("An asset name is at most 32 bytes.") }
        return ReadValue(value: bytes.hex, form: "Asset name “\(text)” as text")
    }

    static func plutusData(_ text: String) throws -> ReadValue {
        if let number = Int(text) {
            return try plutusData(#"{"int": \#(number)}"#).relabelled("Plutus data: the integer \(number)")
        }
        if text.hasPrefix("{") || text.hasPrefix("[") {
            if let object = jsonObject(text), let hex = object["cborHex"] as? String {
                return try relabel(plutusData(hex), "Plutus data (CBOR hex)")
            }
            guard let data = try? PlutusData.fromJSON(text) else {
                throw ValueReadError("That JSON is not Plutus data in the detailed schema.")
            }
            return ReadValue(value: try data.toCBORData().hex, form: "Plutus data (JSON)")
        }
        guard let bytes = hexBytes(text), let data = try? PlutusData.fromCBOR(data: bytes) else {
            throw ValueReadError("Not Plutus data. Enter CBOR hex, detailed-schema JSON or an integer, or choose a datum or redeemer file.")
        }
        return ReadValue(value: try data.toCBORData().hex, form: "Plutus data (CBOR hex)")
    }

    static func plutusScript(_ text: String, version: Int, form: String? = nil) throws -> ReadValue {
        var hex = text
        var label = form ?? "Plutus V\(version) script (CBOR hex)"
        if let json = jsonObject(text) {
            let type = json["type"] as? String ?? ""
            guard let cborHex = json["cborHex"] as? String, type.hasPrefix("PlutusScriptV") else {
                throw ValueReadError("That JSON is not a Plutus script envelope.")
            }
            guard type == "PlutusScriptV\(version)" else {
                throw ValueReadError("That is a \(type.replacingOccurrences(of: "PlutusScript", with: "Plutus ")) script, not Plutus V\(version).")
            }
            hex = cborHex
            label = form ?? "Plutus V\(version) script"
        }
        let compact = hex.filter { !$0.isWhitespace }
        _ = try TransactionComposer.plutusScript(version: version, hex: compact)
        return ReadValue(value: compact.lowercased(), form: label)
    }

    static func nativeScript(_ text: String) throws -> ReadValue {
        guard let native = try? NativeScript.fromJSON(text) else { throw ValueReadError("That is not a native script's JSON.") }
        let hash = try scriptHash(script: .nativeScript(native)).payload.hex
        return ReadValue(value: text, form: "Native script, policy id \(hash.prefix(8))…")
    }

    static func transactionInput(_ text: String) throws -> ReadValue {
        let parts = text.split(separator: "#")
        guard parts.count == 2, let index = UInt16(parts[1]), let id = hexBytes(String(parts[0])), id.count == 32 else {
            throw ValueReadError("A UTxO is its transaction id#index.")
        }
        return ReadValue(value: "\(id.hex)#\(index)", form: "UTxO")
    }

    static func anyKeyHash(_ text: String) throws -> ReadValue {
        if let key = try KeyFile(text) {
            return ReadValue(value: key.hash.payload.hex, form: "Key hash, from a \(key.role.name) \(key.kindName)")
        }
        if let bytes = hexBytes(text), bytes.count == 28 {
            return ReadValue(value: bytes.hex, form: "Key hash")
        }
        if let (hrp, data) = bech32(text), hrp.hasSuffix("_vkh"), data.count == 28 {
            return ReadValue(value: data.hex, form: "Key hash (\(hrp))")
        }
        if let (hrp, data) = bech32(text), hrp.hasSuffix("_vk") || hrp.hasSuffix("_xvk"), data.count == 32 || data.count == 64 {
            return ReadValue(value: keyHash(data).payload.hex, form: "Key hash, from a verification key")
        }
        if let (address, _) = try? parseAddress(text) {
            switch address.paymentPart {
            case .verificationKeyHash(let hash)?: return ReadValue(value: hash.payload.hex, form: "Payment key hash of an address")
            case .scriptHash?: throw ValueReadError("That address is locked by a script, not a key.")
            case nil:
                if case .verificationKeyHash(let hash)? = address.stakingPart {
                    return ReadValue(value: hash.payload.hex, form: "Stake key hash of a stake address")
                }
            }
        }
        throw ValueReadError("Not a key hash. Enter 56 hex characters, addr_vkh1…, an address, or choose a key file.")
    }

    // MARK: Helpers

    /// Even-length hex, with or without `0x`.
    static func hexBytes(_ text: String) -> Data? {
        var hex = text.lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard !hex.isEmpty, hex.count.isMultiple(of: 2), hex.allSatisfy(\.isHexDigit) else { return nil }
        return try? TxDocumentCodec.bytes(fromHex: hex)
    }

    static func jsonObject(_ text: String) -> [String: Any]? {
        guard text.hasPrefix("{") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    static func bech32(_ text: String) -> (hrp: String, data: Data)? {
        guard let separator = text.lastIndex(of: "1"), let data = Bech32().decode(addr: text.lowercased()) else { return nil }
        return (String(text[..<separator]).lowercased(), data)
    }

    /// The key bytes of a bech32 key with one of `prefixes`, or `nil` when
    /// `text` has none of them.
    static func bech32Key(_ text: String, prefixes: [String]) throws -> Data? {
        guard let (hrp, data) = bech32(text), prefixes.contains(hrp) else { return nil }
        guard data.count == 32 || data.count == 64 else { throw ValueReadError("That \(hrp) key has the wrong length.") }
        return data
    }

    static func keyHash(_ key: Data) -> VerificationKeyHash {
        VerificationKeyHash(payload: blake2b(key.prefix(32), size: 28))
    }

    static func blake2b(_ data: Data, size: Int) -> Data {
        (try? Hash().blake2b(data: data, digestSize: size, encoder: RawEncoder.self)) ?? Data()
    }

    static func relabel(_ value: ReadValue, _ form: String) -> ReadValue {
        ReadValue(value: value.value, form: form)
    }
}

extension ReadValue {
    func relabelled(_ form: String) -> ReadValue { ReadValue(value: value, form: form) }
}

/// A cardano-cli key file (text envelope): its role and its key's hash.
/// Signing keys are read only to derive their verification key.
struct KeyFile {
    enum Role: Equatable {
        case payment, stake, stakePool, drep, committeeCold, committeeHot, vrf, other

        var name: String {
            switch self {
            case .payment: "payment"
            case .stake: "stake"
            case .stakePool: "pool cold"
            case .drep: "DRep"
            case .committeeCold: "committee cold"
            case .committeeHot: "committee hot"
            case .vrf: "VRF"
            case .other: "other"
            }
        }
    }

    let role: Role
    let isSigning: Bool
    let hash: VerificationKeyHash

    var kindName: String { isSigning ? "signing key" : "verification key" }

    /// `nil` when `text` is not a JSON object with a `type`; an error when it
    /// is a key file that can't be used.
    init?(_ text: String) throws {
        guard let json = ValueReader.jsonObject(text), let type = json["type"] as? String else { return nil }
        guard type.contains("VerificationKey") || type.contains("SigningKey") else { return nil }
        if json["cborHex"] == nil, json["encrHex"] != nil {
            throw ValueReadError("That key file is encrypted. Decrypt it first.")
        }
        guard let cborHex = json["cborHex"] as? String, let cbor = try? TxDocumentCodec.bytes(fromHex: cborHex),
            case .bytes(let payload)? = try? Primitive.fromCBOR(data: cbor)
        else {
            throw ValueReadError("That key file has no readable key.")
        }
        // Longest prefixes first: StakePool before Stake.
        let roles: [(String, Role)] = [
            ("StakePool", .stakePool), ("Stake", .stake), ("Payment", .payment), ("GenesisUTxO", .payment),
            ("DRep", .drep), ("ConstitutionalCommitteeCold", .committeeCold), ("ConstitutionalCommitteeHot", .committeeHot),
            ("Vrf", .vrf),
        ]
        role = roles.first { type.hasPrefix($0.0) }?.1 ?? .other
        isSigning = type.contains("SigningKey")
        let publicKey: Data
        switch (isSigning, payload.count) {
        case (false, 32), (false, 64):
            publicKey = payload.prefix(32)
        case (true, 32):
            publicKey = try SwiftNaCl.SigningKey(seed: payload).verifyKey.bytes
        case (true, 128):
            // Extended: 64 bytes of private key, the public key, then the chain code.
            publicKey = payload.subdata(in: payload.startIndex + 64 ..< payload.startIndex + 96)
        default:
            throw ValueReadError("That key file's key has an unexpected length.")
        }
        hash = ValueReader.keyHash(publicKey)
    }
}
