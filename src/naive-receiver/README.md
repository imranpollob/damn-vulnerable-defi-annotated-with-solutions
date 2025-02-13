# Naive Receiver

There’s a pool with 1000 WETH in balance offering flash loans. It has a fixed fee of 1 WETH. The pool supports meta-transactions by integrating with a permissionless forwarder contract. 

A user deployed a sample contract with 10 WETH in balance. Looks like it can execute flash loans of WETH.

All funds are at risk! Rescue all WETH from the user and the pool, and deposit it into the designated recovery account.

Explanation:
- **Flash Loan Pool**: This is a pool of funds (1000 WETH) that offers flash loans. Flash loans are special types of loans in decentralized finance (DeFi) where you can borrow money without collateral, but you have to return it in the same transaction block with some added fee.
- **Fixed Fee**: The pool charges a fixed fee of 1 WETH for every flash loan, regardless of the loan amount. This fee must be paid when the loan is returned within the same transaction.
- **Meta-Transactions**: The pool supports meta-transactions via a permissionless forwarder contract. Meta-transactions allow users to interact with blockchain protocols through a third party that sponsors the transaction fees. In this case, it implies that other contracts can trigger functions on behalf of the user’s contract without the user needing to initiate or pay for these transactions directly.
- **Vulnerable User Contract**: There is a user contract deployed with 10 WETH in its balance. The description suggests that this contract can execute flash loans but may not have safeguards against misuse.
- **Objective**: The challenge is to "rescue" all the WETH from both the user’s contract and the pool and deposit it into a designated recovery account. This likely involves exploiting the user contract’s ability to interact with flash loans and its lack of protection against repeated or malicious flash loan requests.