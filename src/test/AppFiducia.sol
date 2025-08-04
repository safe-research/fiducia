// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Fiducia, SignatureChecker, Enum, ISafe, IERC20} from "../Fiducia.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title AppFiducia
 * @dev This contract extends the Fiducia contract to provide additional functionality for Safe App.
 *      This should only be used for demo purposes.
 */
contract AppFiducia is Fiducia {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /**
     * @dev Information about a transaction identifier.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction (Call, DelegateCall, etc.).
     */
    struct TxIdentifierInfo {
        address to;
        bytes4 selector;
        Enum.Operation operation;
    }

    /**
     * @dev Information about a token transfer.
     * @param token The token address.
     * @param recipient The address the tokens are sent to.
     */
    struct TokenIdentifierInfo {
        address token;
        address recipient;
    }

    /**
     * @dev Mapping of safe to transaction identifiers.
     */
    mapping(address => EnumerableSet.Bytes32Set) private _txIdentifiers;

    /**
     * @dev Mapping of transaction identifiers to their information.
     */
    mapping(bytes32 txIdentifier => TxIdentifierInfo) private _txIdentifiersInfo;

    /**
     * @dev Mapping of safe to allowed token transfer information.
     */
    mapping(address => EnumerableSet.Bytes32Set) private _tokenIdentifiers;

    /**
     * @dev Mapping of token identifiers to their information.
     */
    mapping(bytes32 tokenId => TokenIdentifierInfo) private _tokenIdentifiersInfo;

    /**
     * @dev Constructor that initializes the Fiducia contract with a specified delay.
     * @param delay The delay in seconds before actions can be executed.
     */
    constructor(uint256 delay) Fiducia(delay) {}

    /**
     * @notice Internal function to check if the guards are set.
     * @return status A boolean indicating if the guards are set correctly.
     * @dev This function only checks the Tx Guard and not the Module Guard. This is done for v1.4.1 Wallet Interface compatibility.
     */
    function _checkGuardsSet() internal view override returns (bool) {
        ISafe safe = ISafe(payable(msg.sender));
        address guard = abi.decode(safe.getStorageAt(GUARD_STORAGE_SLOT, 1), (address));

        return guard == address(this);
    }

    /**
     * @notice Internal function to add transactions executed by a cosigner.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @dev This function is called when a cosigner approves a transaction, allowing it to be executed immediately next time.
     */
    function _allowanceByCosigner(address safe, address to, bytes calldata data, Enum.Operation operation)
        internal
        override
    {
        bytes4 selector = _decodeSelector(data);
        bytes32 txId = keccak256(abi.encode(to, selector, operation));

        // Add the txId to allowed transactions immediately if not already present.
        uint256 currentTxTimestamp = allowedTxs[safe][txId];
        if (currentTxTimestamp == 0 || currentTxTimestamp > block.timestamp) {
            allowedTxs[safe][txId] = block.timestamp;
            _txIdentifiers[safe].add(txId);
            _txIdentifiersInfo[txId] = TxIdentifierInfo({to: to, selector: selector, operation: operation});
            emit TxAllowed(safe, to, selector, operation, block.timestamp);
        }

        if (operation == Enum.Operation.Call && selector == IERC20.transfer.selector && data.length > 67) {
            // Decode the recipient and amount from the data.
            (address recipient, uint256 amount) = abi.decode(data[4:], (address, uint256));
            // Set the token transfer info if not already present or tokenTransferInfo.amount < amount.
            TokenTransferInfo memory tokenTransferInfo = allowedTokenTransferInfos[safe][to][recipient];
            uint256 newTimestamp = tokenTransferInfo.activeFrom == 0 || tokenTransferInfo.activeFrom > block.timestamp
                ? block.timestamp
                : tokenTransferInfo.activeFrom;
            uint256 newAmount = tokenTransferInfo.amount < amount ? amount : tokenTransferInfo.amount;
            allowedTokenTransferInfos[safe][to][recipient] =
                TokenTransferInfo({activeFrom: newTimestamp, amount: newAmount});
            bytes32 tokenId = keccak256(abi.encode(to, recipient));
            _tokenIdentifiers[safe].add(tokenId);
            _tokenIdentifiersInfo[tokenId] = TokenIdentifierInfo({token: to, recipient: recipient});
            emit TokenTransferAllowed(safe, to, recipient, newAmount, newTimestamp);
        }
    }

    /**
     * @notice This function is called after the execution of a transaction to check if the guard is set up correctly.
     * @dev This function only checks the Tx Guard and not the Module Guard. This is done for v1.4.1 Wallet Interface compatibility.
     */
    function _checkAfterExecution() internal override {
        ISafe safe = ISafe(payable(msg.sender));
        address guard = abi.decode(safe.getStorageAt(GUARD_STORAGE_SLOT, 1), (address));

        // Higher chance of this being true, so added the check first as a circuit breaker
        if (guard == address(this)) {
            return;
        } else {
            _removeGuard();
        }
    }

    /**
     * @notice Function to set an allowed transaction type.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction.
     * @dev This function allows setting a transaction type that can be executed without delay.
     */
    function setAllowedTx(address to, bytes4 selector, Enum.Operation operation, bool reset) public override {
        uint256 allowedTimestamp = reset ? 0 : _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        bytes32 txId = keccak256(abi.encode(to, selector, operation));
        allowedTxs[msg.sender][txId] = allowedTimestamp;

        if (reset) {
            _txIdentifiers[msg.sender].remove(txId);
            delete _txIdentifiersInfo[txId];
        } else {
            _txIdentifiers[msg.sender].add(txId);
            _txIdentifiersInfo[txId] = TxIdentifierInfo({to: to, selector: selector, operation: operation});
        }

        emit TxAllowed(msg.sender, to, selector, operation, allowedTimestamp);
    }

    /**
     * @notice Function to set an allowed token transfer.
     * @param token The address of the token contract.
     * @param recipient The address the tokens are sent to.
     * @param amount The amount of tokens that can be transferred in a single transaction.
     * @dev This function allows setting a token transfer that can be executed without delay.
     */
    function setAllowedTokenTransfer(address token, address recipient, uint256 amount, bool reset) public override {
        uint256 allowedTimestamp = reset ? 0 : _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        allowedTokenTransferInfos[msg.sender][token][recipient] =
            TokenTransferInfo({activeFrom: allowedTimestamp, amount: amount});

        bytes32 tokenId = keccak256(abi.encode(token, recipient));
        if (reset) {
            _tokenIdentifiers[msg.sender].remove(tokenId);
            delete _tokenIdentifiersInfo[tokenId];
        } else {
            _tokenIdentifiers[msg.sender].add(tokenId);
            _tokenIdentifiersInfo[tokenId] = TokenIdentifierInfo({token: token, recipient: recipient});
        }

        emit TokenTransferAllowed(msg.sender, token, recipient, amount, allowedTimestamp);
    }

    /**
     * @notice Function to get the transaction identifier information for a specific transaction identifier.
     * @param txIdentifier The identifier of the transaction to retrieve information for.
     * @return The transaction identifier information.
     */
    function getTxIdentifierInfo(bytes32 txIdentifier) external view returns (TxIdentifierInfo memory) {
        return _txIdentifiersInfo[txIdentifier];
    }

    /**
     * @notice Function to get the transaction identifiers for a specific account.
     * @param account The address of the account to retrieve transaction identifiers for.
     * @return An array of bytes32 representing the transaction identifiers.
     */
    function getTxIdentifiers(address account) external view returns (bytes32[] memory) {
        return _txIdentifiers[account].values();
    }

    /**
     * @notice Function to get the token transfer information for a specific token identifier.
     * @param tokenId The identifier of the token transfer to retrieve information for.
     * @return The token transfer information.
     */
    function getTokenIdentifierInfo(bytes32 tokenId) external view returns (TokenIdentifierInfo memory) {
        return _tokenIdentifiersInfo[tokenId];
    }

    /**
     * @notice Function to get the token identifiers for a specific account.
     * @param account The address of the account to retrieve token identifiers for.
     * @return An array of bytes32 representing the token identifiers.
     */
    function getTokenIdentifiers(address account) external view returns (bytes32[] memory) {
        return _tokenIdentifiers[account].values();
    }
}
