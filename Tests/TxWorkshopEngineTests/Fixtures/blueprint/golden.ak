use aiken/cbor
use aiken/primitive/bytearray
use cardano/address.{Address, Inline, Script, VerificationKey}
use market.{Action, Leaf, Node, Order, Update}

test golden_order() {
  let order =
    Order {
      owner: #"00112233445566778899aabbccddeeff00112233445566778899aabb",
      price: 5000000,
      deadline: Some(1700000000000),
      partial: True,
      tags: [#"6869", #""],
      splits: [Pair(#"aa", 1), Pair(#"bb", -2)],
      pair: (18446744073709551616, #"ff"),
      payout: Address {
        payment_credential: VerificationKey(#"aabbccddeeff00112233445566778899aabbccddeeff001122334455"),
        stake_credential: Some(Inline(Script(#"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c"))),
      },
      tree: Node(Leaf(1), Node(Leaf(-2), Leaf(3))),
      extra: 42,
    }
  trace bytearray.to_hex(cbor.serialise(order))
  True
}

test golden_action() {
  let a: Action = Update { price: 7, deadline: None }
  trace bytearray.to_hex(cbor.serialise(a))
  True
}

test golden_long_bytes() {
  let b: ByteArray = #"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f40414243"
  trace bytearray.to_hex(cbor.serialise(b))
  True
}
