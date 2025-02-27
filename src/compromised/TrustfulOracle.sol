// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {LibSort} from "solady/utils/LibSort.sol";

/**
 * @notice A price oracle with a number of trusted sources that individually report prices for symbols.
 *         The oracle's price for a given symbol is the median price of the symbol over all sources.
 */
contract TrustfulOracle is AccessControlEnumerable {
    uint256 public constant MIN_SOURCES = 1;
    // Role granted to addresses that are allowed to report prices.
    bytes32 public constant TRUSTED_SOURCE_ROLE = keccak256("TRUSTED_SOURCE_ROLE");
    //  Role granted temporarily to the deployer to set up initial prices.
    bytes32 public constant INITIALIZER_ROLE = keccak256("INITIALIZER_ROLE");

    // Source address => (symbol => price)
    // A nested mapping to store prices reported by each trusted source for each symbol.
    mapping(address => mapping(string => uint256)) private _pricesBySource;

    error NotEnoughSources();

    event UpdatedPrice(address indexed source, string indexed symbol, uint256 oldPrice, uint256 newPrice);

    constructor(address[] memory sources, bool enableInitialization) {
        if (sources.length < MIN_SOURCES) {
            revert NotEnoughSources();
        }
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                // Grants TRUSTED_SOURCE_ROLE to provided addresses
                _grantRole(TRUSTED_SOURCE_ROLE, sources[i]);
                ++i;
            }
        }
        if (enableInitialization) {
            // Grants INITIALIZER_ROLE to the deployer if enabled
            _grantRole(INITIALIZER_ROLE, msg.sender);
        }
    }

    // A handy utility allowing the deployer to setup initial prices (only once)
    function setupInitialPrices(address[] calldata sources, string[] calldata symbols, uint256[] calldata prices)
        external
        onlyRole(INITIALIZER_ROLE)
    {
        // Only allow one (symbol, price) per source
        require(sources.length == symbols.length && symbols.length == prices.length);
        for (uint256 i = 0; i < sources.length;) {
            unchecked {
                // Sets initial prices for each source and symbol
                _setPrice(sources[i], symbols[i], prices[i]);
                ++i;
            }
        }

        // Revokes INITIALIZER_ROLE after initial setup
        renounceRole(INITIALIZER_ROLE, msg.sender);
    }

    function postPrice(string calldata symbol, uint256 newPrice) external onlyRole(TRUSTED_SOURCE_ROLE) {
        // Allows trusted sources to update prices
        _setPrice(msg.sender, symbol, newPrice);
    }

    function getMedianPrice(string calldata symbol) external view returns (uint256) {
        // Returns the median price for a symbol
        return _computeMedianPrice(symbol);
    }

    function getAllPricesForSymbol(string memory symbol) public view returns (uint256[] memory prices) {
        uint256 numberOfSources = getRoleMemberCount(TRUSTED_SOURCE_ROLE);
        prices = new uint256[](numberOfSources);
        for (uint256 i = 0; i < numberOfSources;) {
            address source = getRoleMember(TRUSTED_SOURCE_ROLE, i);
            // Retrieves all prices for a symbol from each source
            prices[i] = getPriceBySource(symbol, source);
            unchecked {
                ++i;
            }
        }
    }

    function getPriceBySource(string memory symbol, address source) public view returns (uint256) {
        return _pricesBySource[source][symbol];
    }

    function _setPrice(address source, string memory symbol, uint256 newPrice) private {
        uint256 oldPrice = _pricesBySource[source][symbol];
        // Updates the price for a source and symbol
        _pricesBySource[source][symbol] = newPrice;
        emit UpdatedPrice(source, symbol, oldPrice, newPrice);
    }

    function _computeMedianPrice(string memory symbol) private view returns (uint256) {
        // Gets all prices for the symbol
        uint256[] memory prices = getAllPricesForSymbol(symbol);
        // Sorts the prices
        LibSort.insertionSort(prices);
        if (prices.length % 2 == 0) {
            // Calculates median for even number of sources
            uint256 leftPrice = prices[(prices.length / 2) - 1];
            uint256 rightPrice = prices[prices.length / 2];
            return (leftPrice + rightPrice) / 2;
        } else {
            // Calculates median for odd number of sources
            return prices[prices.length / 2];
        }
    }
}
