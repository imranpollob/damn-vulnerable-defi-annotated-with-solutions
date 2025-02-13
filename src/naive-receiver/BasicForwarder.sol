// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

interface IHasTrustedForwarder {
    function trustedForwarder() external view returns (address);
}

// handle meta-transactions using EIP-712, which standardizes typed structured data hashing and signing.
// This functionality is crucial in applications that require user interactions without direct transaction fees paid by the user, enabling a third party to pay the gas fees.
contract BasicForwarder is EIP712 {
    struct Request {
        address from;
        address target;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
        uint256 deadline;
    }

    error InvalidSigner();
    error InvalidNonce();
    error OldRequest();
    error InvalidTarget();
    error InvalidValue();

    // Defines the format of a forwarding request
    bytes32 private constant _REQUEST_TYPEHASH = keccak256(
        "Request(address from,address target,uint256 value,uint256 gas,uint256 nonce,bytes data,uint256 deadline)"
    );

    mapping(address => uint256) public nonces;

    /**
     * @notice Check request and revert when not valid. A valid request must:
     * - Include the expected value
     * - Not be expired
     * - Include the expected nonce
     * - Target a contract that accepts this forwarder
     * - Be signed by the original sender (`from` field)
     */
    function _checkRequest(Request calldata request, bytes calldata signature) private view {
        // checks that the value matches
        if (request.value != msg.value) revert InvalidValue();
        // the request has not expired
        if (block.timestamp > request.deadline) revert OldRequest();
        // uses the correct nonce
        if (nonces[request.from] != request.nonce) revert InvalidNonce();
        // targets a valid contract
        if (IHasTrustedForwarder(request.target).trustedForwarder() != address(this)) revert InvalidTarget();
        // is signed by the correct sender
        address signer = ECDSA.recover(_hashTypedData(getDataHash(request)), signature);
        if (signer != request.from) revert InvalidSigner();
    }

    // Processes the validated request
    /**
     * struct Request {
     *     address from;
     *     address target;
     *     uint256 value;
     *     uint256 gas;
     *     uint256 nonce;
     *     bytes data;
     *     uint256 deadline;
     * }
     */
    function execute(Request calldata request, bytes calldata signature) public payable returns (bool success) {
        _checkRequest(request, signature);
        // increments the nonce for the sender to prevent replay attacks, ensuring that each request is only processed once.
        nonces[request.from]++;

        uint256 gasLeft;
        uint256 value = request.value; // in wei
        address target = request.target;
        bytes memory payload = abi.encodePacked(request.data, request.from);
        uint256 forwardGas = request.gas;
        // Executes a call to the target contract address.
        assembly {
            success := call(forwardGas, target, value, add(payload, 0x20), mload(payload), 0, 0) // don't copy returndata
            gasLeft := gas()
        }

        // After the call, it checks if the gas left is less than 1/63rd of the provided gas. This check is based on the EVM's rule where if a call consumes more than 63/64 of the provided gas, additional gas is provided to finish the operation. This condition helps prevent out-of-gas errors in contracts called by this forwarder.
        if (gasLeft < request.gas / 63) {
            assembly {
                invalid()
            }
        }
    }

    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "BasicForwarder";
        version = "1";
    }

    function getDataHash(Request memory request) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _REQUEST_TYPEHASH,
                request.from,
                request.target,
                request.value,
                request.gas,
                request.nonce,
                keccak256(request.data),
                request.deadline
            )
        );
    }

    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator();
    }

    function getRequestTypehash() external pure returns (bytes32) {
        return _REQUEST_TYPEHASH;
    }
}
