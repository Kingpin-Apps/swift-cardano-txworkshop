use aiken/crypto.{VerificationKeyHash}
use cardano/address.{Address}
use cardano/assets.{PolicyId}
use cardano/transaction.{OutputReference, Transaction}

pub type Tree {
  Leaf(Int)
  Node { left: Tree, right: Tree }
}

pub type Order {
  owner: VerificationKeyHash,
  price: Int,
  deadline: Option<Int>,
  partial: Bool,
  tags: List<ByteArray>,
  splits: Pairs<ByteArray, Int>,
  pair: (Int, ByteArray),
  payout: Address,
  tree: Tree,
  extra: Data,
}

pub type Action {
  Buy
  Cancel
  Update { price: Int, deadline: Option<Int> }
}

validator market {
  spend(datum: Option<Order>, redeemer: Action, _own: OutputReference, _tx: Transaction) {
    when datum is {
      Some(order) -> order.price > 0 && redeemer != Buy
      None -> False
    }
  }
}

validator token(owner: VerificationKeyHash, nonce: Int) {
  mint(redeemer: List<Int>, _policy: PolicyId, _tx: Transaction) {
    owner != #"" && nonce >= 0 && redeemer != []
  }
}
