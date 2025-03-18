# Damn Vulnerable DeFi Annotated With Solution

Solution Videos:
1. [Challenge 1](https://www.loom.com/share/4cd1c77826304a3ebfd0a406ba0ac12e)
2. [Challenge 2](https://www.loom.com/share/780e1e61d1f14d9db39ee446b79eb0f6)
3. [Challenge 3](https://www.loom.com/share/8db8769aa727469b9277436438518c4e)
4. [Challenge 4](https://www.loom.com/share/b6c4757daf8a403cbd4ddc20e3abc2ca)
5. [Challenge 5](https://www.loom.com/share/3e50478a955446f597a3a6902eb49708)
6. [Challenge 6](https://www.loom.com/share/04e85407c4ff465595c2f74193c9b5b9)
7. [Challenge 7](https://www.loom.com/share/b50cd4f869fb4fc3800528c83b6f8d07)
8. [Challenge 8](https://www.loom.com/share/fc33292618474477842416c868d0de84)
9. [Challenge 9](https://www.loom.com/share/8f9ef5f80e8b4aad94c3dc13142c9524)
10. [Challenge 10](https://www.loom.com/share/a221bd57455640d3ac972de878b09099)

Damn Vulnerable DeFi is _the_ smart contract security playground for developers, security researchers and educators.

Perhaps the most sophisticated vulnerable set of Solidity smart contracts ever witnessed, it features flashloans, price oracles, governance, NFTs, DEXs, lending pools, smart contract wallets, timelocks, vaults, meta-transactions, token distributions, upgradeability and more.

Use Damn Vulnerable DeFi to:

- Sharpen your auditing and bug-hunting skills.
- Learn how to detect, test and fix flaws in realistic scenarios to become a security-minded developer.
- Benchmark smart contract security tooling.
- Create educational content on smart contract security with articles, tutorials, talks, courses, workshops, trainings, CTFs, etc. 

## Install

1. Clone the repository.
2. Checkout the latest release (for example, `git checkout v4.0.1`)
3. Rename the `.env.sample` file to `.env` and add a valid RPC URL. This is only needed for the challenges that fork mainnet state.
4. Either install [Foundry](https://book.getfoundry.sh/getting-started/installation), or use the [provided devcontainer](./.devcontainer/) (In VSCode, open the repository as a devcontainer with the command "Devcontainer: Open Folder in Container...")
5. Run `forge build` to initialize the project.

## Usage

Each challenge is made up of:

- A prompt located in `src/<challenge-name>/README.md`.
- A set of contracts located in `src/<challenge-name>/`.
- A [Foundry test](https://book.getfoundry.sh/forge/tests) located in `test/<challenge-name>/<ChallengeName>.t.sol`.

To solve a challenge:

1. Read the challenge's prompt.
2. Uncover the flaw(s) in the challenge's smart contracts.
3. Code your solution in the corresponding test file.
4. Try your solution with `forge test --mp test/<challenge-name>/<ChallengeName>.t.sol`.

> In challenges that restrict the number of transactions, you might need to run the test with the `--isolate` flag.

If the test passes, you've solved the challenge!

Challenges may have more than one possible solution.

### Rules

- You must always use the `player` account.
- You must not modify the challenges' initial nor final conditions.
- You can code and deploy your own smart contracts.
- You can use Foundry's cheatcodes to advance time when necessary.
- You can import external libraries that aren't installed, although it shouldn't be necessary.

## Troubleshooting

You can ask the community for help in [the discussions section](https://github.com/theredguild/damn-vulnerable-defi/discussions).

## Disclaimer

All code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.
