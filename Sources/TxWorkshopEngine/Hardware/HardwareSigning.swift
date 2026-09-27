import CardanoHWKit
import CardanoHWWalletLedger
import CardanoHWWalletTrezor
import Foundation
import SwiftCardanoCore
import TxWorkshopCore

/// A hardware wallet connection the app can sign through.
public enum HardwareConnection: String, CaseIterable, Sendable, Codable {
    /// A Ledger over USB (macOS).
    case ledgerUSB
    /// A Ledger Nano X or Flex over Bluetooth.
    case ledgerBluetooth
    /// A Trezor over USB (macOS; Model One and the older THP-less firmware).
    case trezorUSB
    /// A Keystone, air-gapped, through animated QR codes (iOS).
    case keystoneQR

    /// The connections this platform has.
    public static var available: [HardwareConnection] {
        #if os(macOS)
        [.ledgerUSB, .ledgerBluetooth, .trezorUSB]
        #elseif os(iOS)
        [.ledgerBluetooth, .keystoneQR]
        #else
        [.ledgerBluetooth]
        #endif
    }

    /// Whether signing is a QR exchange the person drives, rather than a
    /// connection the app talks over.
    public var isQR: Bool { self == .keystoneQR }
}

/// Signs through a hardware wallet: imports its account key, describes the
/// transaction to it, and turns what it returns into witnesses. The device
/// shows the transaction and the person approves it there.
public struct HardwareSigning: Sendable {
    public init() {}

    static func magic(_ network: CardanoNetwork) -> UInt32 {
        switch network {
        case .mainnet: 764_824_073
        case .preprod: 1
        case .preview: 2
        case .custom(let magic): magic
        }
    }

    public static func networkID(_ network: CardanoNetwork) -> NetworkId { network == .mainnet ? .mainnet : .testnet }

    static func signer(_ connection: HardwareConnection, network: CardanoNetwork, account: HardwareAccountModel?) throws -> any HardwareSigner {
        let id: UInt8 = network == .mainnet ? 1 : 0
        switch connection {
        case .ledgerUSB:
            #if os(macOS)
            let transport = HidLedgerTransport()
            try transport.open()
            return LedgerSignSession(
                transport: transport, network: LedgerNetwork(networkId: id, protocolMagic: magic(network)),
                derivation: try account.map(PublicHDDerivation.init(account:))
            )
            #else
            throw HardwareSigningError.unavailable
            #endif
        case .ledgerBluetooth:
            return LedgerSignSession(
                transport: BleLedgerTransport(), network: LedgerNetwork(networkId: id, protocolMagic: magic(network)),
                derivation: try account.map(PublicHDDerivation.init(account:))
            )
        case .trezorUSB:
            #if os(macOS)
            return TrezorSignSession(link: TrezorHIDPacketLink(), network: TrezorNetwork(networkId: UInt32(id), protocolMagic: magic(network)))
            #else
            throw HardwareSigningError.unavailable
            #endif
        case .keystoneQR:
            // Keystone signs through a QR session the UI drives.
            throw HardwareSigningError.unavailable
        }
    }

    /// Reads account `index`'s extended public key from the device.
    public func importAccount(_ connection: HardwareConnection, network: CardanoNetwork, index: Int) async throws -> HardwareAccountModel {
        let signer = try Self.signer(connection, network: network, account: nil)
        do {
            return try await signer.importAccount(network: Self.networkID(network), accountIndex: index)
        } catch {
            throw HardwareSigningError.device(String(describing: error))
        }
    }

    /// Signs `bytes` on the device with `account`, returning its witnesses.
    public func sign(
        _ bytes: Data, utxos: [String], account: HardwareAccountModel, connection: HardwareConnection, network: CardanoNetwork
    ) async throws -> [VerificationKeyWitness] {
        let request = try Self.request(for: bytes, utxos: utxos, account: account)
        let signer = try Self.signer(connection, network: network, account: account)
        let witnessSet: String
        do {
            witnessSet = try await signer.sign(request)
        } catch {
            throw HardwareSigningError.device(String(describing: error))
        }
        return try WitnessAssembler.witnesses(fromCBOR: TxDocumentCodec.bytes(fromHex: witnessSet))
    }

    // MARK: Describing the transaction to a device

    /// The key hashes `account` holds: the first 20 external and change
    /// payment keys, and stake key 0.
    public static func keyHashes(of account: HardwareAccountModel) throws -> Set<String> {
        let derivation = try PublicHDDerivation(account: account)
        var hashes: Set<String> = []
        for role in [UInt32(0), 1] {
            for index in 0..<UInt32(KeyRing.addressGap) {
                hashes.insert(try derivation.paymentVerificationKey(role: role, index: index).hash().payload.hex)
            }
        }
        hashes.insert(try derivation.stakeVerificationKey().hash().payload.hex)
        return hashes
    }

    /// Every address of `account` a spent output may be at, with its path:
    /// base addresses (the device's own table) and enterprise addresses.
    static func addressPaths(_ account: HardwareAccountModel) throws -> [String: String] {
        let derivation = try PublicHDDerivation(account: account)
        var paths = try derivation.deriveAddressTable(gapLimit: KeyRing.addressGap)
        for role in [UInt32(0), 1] {
            for index in 0..<UInt32(KeyRing.addressGap) {
                let key = try derivation.paymentVerificationKey(role: role, index: index)
                let enterprise = try Address(paymentPart: .verificationKeyHash(try key.hash()), network: account.network).toBech32()
                paths[enterprise] = derivation.path(role: role, index: index)
            }
        }
        return paths
    }

    /// The request a device signs: the unsigned transaction, the outputs its
    /// inputs spend, their paths, and its certificates and withdrawals in the
    /// device's terms.
    public static func request(for bytes: Data, utxos: [String], account: HardwareAccountModel) throws -> HardwareSignRequest {
        let transaction = try TransactionValidation.decode(bytes)
        let body = transaction.transactionBody
        let known = Dictionary(
            utxos.compactMap { hex in (try? TransactionComposer.utxo(hex)).map { (InputResolver.id($0.input), $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let spent = try body.inputs.asArray.map { input in
            guard let utxo = known[InputResolver.id(input)] else { throw HardwareSigningError.unknownInput(InputResolver.id(input)) }
            return utxo
        }
        let paths = try addressPaths(account)
        for utxo in spent where paths[try utxo.output.address.toBech32()] == nil {
            throw HardwareSigningError.notThisAccount(try utxo.output.address.toBech32())
        }

        let derivation = try PublicHDDerivation(account: account)
        let stakePath = derivation.path(role: 2, index: 0)
        let stakeHash = try derivation.stakeVerificationKey().hash()
        func ours(_ credential: StakeCredential) throws -> Bool {
            guard case .verificationKeyHash(let hash) = credential.credential, hash == stakeHash else {
                throw HardwareSigningError.unsupported("a certificate for a stake key this account does not hold")
            }
            return true
        }
        var certificates: [HardwareCertificate] = []
        for certificate in body.certificates?.asList ?? [] {
            switch certificate {
            case .register(let register) where try ours(register.stakeCredential):
                certificates.append(.stakeRegistrationConway(stakePath: stakePath, deposit: register.coin))
            case .unregister(let unregister) where try ours(unregister.stakeCredential):
                certificates.append(.stakeDeregistrationConway(stakePath: stakePath, deposit: unregister.coin))
            case .stakeDelegation(let delegation) where try ours(delegation.stakeCredential):
                certificates.append(.stakeDelegation(stakePath: stakePath, poolKeyHashHex: delegation.poolKeyHash.payload.hex))
            case .voteDelegate(let delegation) where try ours(delegation.stakeCredential):
                let drep: HardwareDRepKind = switch delegation.drep.credential {
                case .verificationKeyHash(let hash): .keyHash(hash.payload.hex)
                case .scriptHash(let hash): .scriptHash(hash.payload.hex)
                case .alwaysAbstain: .abstain
                case .alwaysNoConfidence: .noConfidence
                }
                certificates.append(.voteDelegation(stakePath: stakePath, drep: drep))
            default:
                throw HardwareSigningError.unsupported("this kind of certificate")
            }
        }
        var withdrawals: [HardwareWithdrawal] = []
        for (account, coin) in body.withdrawals?.data ?? [:] {
            withdrawals.append(HardwareWithdrawal(stakePath: stakePath, rewardAccountHex: account.hex, amount: coin))
        }
        if body.votingProcedures != nil || body.proposalProcedures != nil {
            throw HardwareSigningError.unsupported("votes and proposals")
        }
        return HardwareSignRequest(
            requestId: UUID().uuidString, unsigned: transaction, spentUTxOs: spent, addressPaths: paths,
            masterFingerprint: account.masterFingerprint, origin: "Tx Workshop", certificates: certificates, withdrawals: withdrawals
        )
    }
}

public enum HardwareSigningError: Error, Sendable, Equatable, CustomStringConvertible {
    case unavailable
    case device(String)
    case unknownInput(String)
    case notThisAccount(String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .unavailable: "That connection is not available on this device."
        case .device(let reason): "The hardware wallet reported: \(reason)"
        case .unknownInput(let id): "The output \(id) spends is not known; fetch chain data first."
        case .notThisAccount(let address): "\(address) is not an address of this hardware account."
        case .unsupported(let what): "Hardware wallets cannot sign \(what) here yet."
        }
    }
}
