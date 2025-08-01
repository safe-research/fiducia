// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ITransactionGuard, IERC165} from "safe-smart-account/contracts/base/GuardManager.sol";
import {IModuleGuard} from "safe-smart-account/contracts/base/ModuleManager.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {ISafe} from "safe-smart-account/contracts/interfaces/ISafe.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {SignatureChecker} from "openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title Fiducia
 * @dev A guard contract to track interactions and enforce stricter checks, initially by requiring co-signers or time delays for new contracts.
 * @author Safe Research - <research@safe.dev>
 */
contract Fiducia is ITransactionGuard, IModuleGuard {
    /**
     * @notice The CosignerInfo struct holds information about a cosigner.
     * @param activeFrom The timestamp from which the cosigner is considered active.
     * @param cosigner The address of the cosigner.
     * @dev This struct is used to manage the cosigner's active status and address.
     */
    struct CosignerInfo {
        uint256 activeFrom;
        address cosigner;
    }

    /**
     * @notice The TokenTransferInfo struct holds information about a token transfer.
     * @param activeFrom The timestamp from which the token transfer is considered allowed.
     * @param amount The amount of tokens that can be transferred in a single transaction.
     * @dev This struct is used to manage token transfers and their limits.
     */
    struct TokenTransferInfo {
        uint256 activeFrom;
        uint256 amount;
    }

    /**
     * @notice The storage slot for the guard.
     * @dev This is used to check if the guard is set.
     *      Value = `keccak256("guard_manager.guard.address")`
     */
    uint256 public constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    /**
     * @notice The storage slot for the module guard.
     * @dev This is used to check if the module guard is set.
     *      Value = `keccak256("module_manager.module_guard.address")`
     */
    uint256 public constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    /**
     * @notice The delay for the guard removal and delegate allowance.
     */
    uint256 public immutable DELAY;

    /**
     * @notice The schedule for the guard removal.
     * @dev safe The address of the safe.
     *      timestamp The timestamp of the schedule.
     */
    mapping(address safe => uint256 timestamp) public removalSchedule;

    /**
     * @notice The mapping of allowed transaction types.
     * @dev safe The address of the safe.
     *      txIdentifier The identifier for the transaction, is a hash of the transaction details (to, selector, operation)
     *      activeFrom The timestamp when the transaction is active.
     */
    mapping(address safe => mapping(bytes32 txIdentifier => uint256 activeFrom)) public allowedTxs;

    /**
     * @notice The mapping of allowed token transactions for particular recipients.
     * @dev safe The address of the safe.
     *      token The address of the token contract.
     *      recipient The address the tokens are sent to.
     *      tokenTransferInfo The information about the token transfer, which includes the activeFrom timestamp and amount.
     */
    mapping(address safe => mapping(address token => mapping(address recipient => TokenTransferInfo))) public
        allowedTokenTransferInfos;

    /**
     * @notice The mapping of cosigner information.
     * @dev safe The address of the safe.
     *      cosigner The information about the cosigner, which includes the activeFrom timestamp and cosigner address.
     */
    mapping(address safe => CosignerInfo cosigner) public cosignerInfos;

    /**
     * @notice Event emitted when the guard removal is scheduled.
     * @param safe The address of the safe.
     * @param timestamp The timestamp when the guard removal is scheduled.
     */
    event GuardRemovalScheduled(address indexed safe, uint256 timestamp);

    /**
     * @notice Event emitted when a transaction is allowed
     * @param safe The address of the safe.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction.
     * @param timestamp The timestamp when the transaction is allowed.
     * @dev This event is emitted when a transaction is allowed by the guard or when allowance is reset.
     */
    event TxAllowed(
        address indexed safe, address indexed to, bytes4 selector, Enum.Operation operation, uint256 timestamp
    );

    /**
     * @notice Event emitted when a cosigner is set.
     * @param safe The address of the safe.
     * @param cosigner The address of the cosigner.
     * @param activeFrom The timestamp from which the cosigner is considered active.
     * @dev This event is emitted when a cosigner is set or reset.
     */
    event CosignerSet(address indexed safe, address indexed cosigner, uint256 activeFrom);

    /**
     * @notice Event emitted when a token transfer is allowed.
     * @param safe The address of the safe.
     * @param token The address of the token contract.
     * @param recipient The address the tokens are sent to.
     * @param amount The maximum amount of tokens that can be transferred in a single transaction.
     * @param activeFrom The timestamp from which the token transfer is considered allowed.
     * @dev This event is emitted when a token transfer is allowed or reset.
     */
    event TokenTransferAllowed(
        address indexed safe, address indexed token, address indexed recipient, uint256 amount, uint256 activeFrom
    );

    /**
     * @notice Error thrown when the timestamp for guard removal is not passed or have scheduled.
     */
    error InvalidTimestamp();

    /**
     * @notice Error thrown when a token transfer is not allowed.
     */
    error TokenTransferNotAllowed();

    /**
     * @notice Error thrown when a token transfer exceeds the allowed limit.
     */
    error TokenTransferExceedsLimit();

    /**
     * @notice Error thrown when a transaction is the first time it is being executed.
     */
    error FirstTimeTx();

    /**
     * @notice Error thrown when the function selector is invalid.
     */
    error InvalidSelector();

    /**
     * @notice Error thrown when the guard is not set up properly.
     */
    error ImproperGuardSetup();

    /**
     * @notice The constructor initializes the contract with a delay.
     * @param delay The delay in seconds for guard removal and delegate allowance.
     */
    constructor(uint256 delay) {
        DELAY = delay;
    }

    /**
     * @notice Function to schedule the guard removal
     */
    function scheduleGuardRemoval() public {
        require(_checkGuardsSet(), ImproperGuardSetup());
        removalSchedule[msg.sender] = DELAY + block.timestamp;

        emit GuardRemovalScheduled(msg.sender, DELAY + block.timestamp);
    }

    /**
     * @notice Internal function to check if the guard removal is scheduled
     */
    function _removeGuard() internal {
        uint256 removalTimestamp = removalSchedule[msg.sender];
        require(removalTimestamp > 0 && removalTimestamp <= block.timestamp, InvalidTimestamp());

        removalSchedule[msg.sender] = 0;
    }

    /**
     * @inheritdoc ITransactionGuard
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes calldata signatures,
        address
    ) external override {
        if (_checkCosigner(msg.sender, to, value, data, operation, signatures)) {
            return;
        }
        _checkTransaction(msg.sender, to, data, operation);
    }

    /**
     * @inheritdoc IModuleGuard
     */
    function checkModuleTransaction(address to, uint256, bytes calldata data, Enum.Operation operation, address)
        external
        override
        returns (bytes32)
    {
        _checkTransaction(msg.sender, to, data, operation);

        return bytes32(0);
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
        virtual
    {
        bytes4 selector = _decodeSelector(data);
        bytes32 txId = keccak256(abi.encode(to, selector, operation));

        // Add the txId to allowed transactions immediately if not already present.
        uint256 currentTxActiveFrom = allowedTxs[safe][txId];
        if (currentTxActiveFrom == 0 || currentTxActiveFrom > block.timestamp) {
            allowedTxs[safe][txId] = block.timestamp;
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
            emit TokenTransferAllowed(safe, to, recipient, newAmount, newTimestamp);
        }
    }

    /**
     * @notice Internal function to check if a transaction is approved by a cosigner.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param value The value of the transaction.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @param signature The signature of the transaction.
     * @return status A boolean indicating if the transaction is approved by the cosigner.
     * @dev This is to allow transaction execution without delay if a cosigner approves it.
     */
    function _checkCosigner(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        bytes calldata signature
    ) internal returns (bool status) {
        // Compute the transaction hash. (Not same as Safe Tx Hash)
        bytes32 safeTxHash = ISafe(payable(safe)).getTransactionHash(
            to,
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            address(0),
            ISafe(payable(safe)).nonce() - 1 // The Guard check is executed post nonce increment, so we need to subtract 1 from the nonce.
        );

        // Retrieve the co-signer configured for the Safe account.
        CosignerInfo memory info = cosignerInfos[safe];

        // Check if the cosigner is active
        if (info.activeFrom > 0 && info.activeFrom <= block.timestamp) {
            status =
                SignatureChecker.isValidSignatureNow(info.cosigner, safeTxHash, _decodeCosignerSignature(signature));
            if (status) {
                _allowanceByCosigner(safe, to, data, operation);
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Decodes the cosigner signature from the provided signatures.
     */
    function _decodeCosignerSignature(bytes calldata signatures) internal pure virtual returns (bytes calldata) {
        if (signatures.length < 66) {
            return _emptyContext();
        }

        uint256 end = signatures.length - 32;
        uint256 length = uint256(bytes32(signatures[end:]));
        if (length > end) {
            return _emptyContext();
        }

        return signatures[end - length:end];
    }

    /**
     * @notice Internal function to return an empty context.
     * @return An empty bytes calldata.
     * @dev This function is used when no additional context is provided in the signatures.
     */
    function _emptyContext() internal pure returns (bytes calldata) {
        return msg.data[0:0];
    }

    /**
     * @notice Internal function to check if a transaction is allowed.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @dev This function checks if the transaction is allowed through multiple validation paths:
     *      1. Token transfer allowances (for ERC20 transfers)
     *      2. Guard internal transactions (setCosigner, setAllowedTx, etc.)
     *      3. Guard removal transactions (with delay)
     *      4. General allowed transactions (with multiSend support)
     */
    function _checkTransaction(address safe, address to, bytes calldata data, Enum.Operation operation) internal {
        bytes4 selector = _decodeSelector(data);

        // Check for guard internal transactions (setCosigner, setAllowedTx, etc.)
        if (_setTransactions(to, selector, operation)) {
            return;
        }

        // Check for guard removal transactions
        if (_isGuardRemovalTransaction(safe, to, data)) {
            return;
        }

        // Check for token transfer allowances first (most common case for ERC20 tokens)
        if (_checkTokenTransfer(safe, to, selector, data, operation)) {
            return;
        }

        // Check for general allowed transactions
        bytes32 txId = keccak256(abi.encode(to, selector, operation));
        if (allowedTxs[safe][txId] > 0 && allowedTxs[safe][txId] <= block.timestamp) {
            _handleMultiSendIfNeeded(safe, selector, data);
            return;
        }

        revert FirstTimeTx();
    }

    /**
     * @notice Internal function to check if a token transfer is allowed.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @return allowed True if the token transfer is allowed, false otherwise.
     */
    function _checkTokenTransfer(
        address safe,
        address to,
        bytes4 selector,
        bytes calldata data,
        Enum.Operation operation
    ) internal view returns (bool allowed) {
        // Only check ERC20 transfers with sufficient data length
        if (selector != IERC20.transfer.selector || operation != Enum.Operation.Call || data.length <= 67) {
            return false;
        }

        (address recipient, uint256 amount) = abi.decode(data[4:], (address, uint256));
        TokenTransferInfo memory tokenTransferInfo = allowedTokenTransferInfos[safe][to][recipient];

        // Check if token transfer is configured and active
        if (tokenTransferInfo.amount == 0) {
            return false;
        }

        require(
            tokenTransferInfo.activeFrom > 0 && tokenTransferInfo.activeFrom <= block.timestamp,
            TokenTransferNotAllowed()
        );
        require(amount <= tokenTransferInfo.amount, TokenTransferExceedsLimit());

        return true;
    }

    /**
     * @notice Internal function to handle multiSend transactions recursively.
     * @param safe The address of the Safe contract.
     * @param selector The function selector of the transaction.
     * @param data The data payload of the transaction.
     */
    function _handleMultiSendIfNeeded(address safe, bytes4 selector, bytes calldata data) internal {
        if (selector != MultiSendCallOnly.multiSend.selector) {
            return;
        }

        bytes calldata transactions = _decodeMultiSendTransactions(data);
        while (transactions.length > 0) {
            address to;
            bytes calldata txData;
            Enum.Operation operation;
            (to, txData, operation, transactions) = _decodeNextTransaction(transactions);
            _checkTransaction(safe, to, txData, operation);
        }
    }

    /**
     * @notice Internal function to check if a transaction is a guard removal transaction.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param data The data payload of the transaction.
     * @return status A boolean indicating if the transaction is an allowed guard removal.
     */
    function _isGuardRemovalTransaction(address safe, address to, bytes calldata data)
        internal
        view
        returns (bool status)
    {
        bytes4 selector = _decodeSelector(data);

        // Check if removal is scheduled
        uint256 removalTimestamp = removalSchedule[safe];
        if (removalTimestamp == 0 || removalTimestamp > block.timestamp) {
            return false;
        }

        // Check if this is a call to remove guards
        if (to == safe) {
            if (
                selector == ISafe(payable(safe)).setGuard.selector
                    || selector == ISafe(payable(safe)).setModuleGuard.selector
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Internal function to decode the function selector from the provided data.
     * @param data The data containing the function selector.
     * @return selector The decoded function selector.
     * @dev This function checks if the length of the data is at least 4 bytes.
     *      If the length is 0, it returns a zero selector. If the length is less than 4,
     *      it reverts with an InvalidSelector error.
     */
    function _decodeSelector(bytes calldata data) internal pure returns (bytes4 selector) {
        if (data.length >= 4) {
            return bytes4(data);
        } else if (data.length == 0) {
            return bytes4(0);
        } else {
            revert InvalidSelector();
        }
    }

    /**
     * @notice Internal function to decode multiSend transactions.
     * @param data The data payload of the multiSend transaction.
     * @return The decoded transactions.
     * @dev This function decodes the multiSend transactions and returns the remaining data.
     */
    function _decodeMultiSendTransactions(bytes calldata data) internal pure returns (bytes calldata) {
        // Explicitly not checking if data[:4] == MultiSendCallOnly.multiSend.selector, as this is already checked in the _checkTransaction function.
        data = data[4:];

        uint256 offset = uint256(bytes32(data[:32]));
        data = data[offset:];
        uint256 length = uint256(bytes32(data[:32]));
        data = data[32:];

        return data[:length];
    }

    /**
     * @notice Internal function to decode the next transaction from the multiSend transactions.
     * @param transactions The remaining transactions data.
     * @return to The address the transaction is sent to.
     * @return data The data payload of the transaction.
     * @return operation The operation type of the transaction.
     * @return rest The remaining transactions data after decoding the next transaction.
     */
    function _decodeNextTransaction(bytes calldata transactions)
        internal
        pure
        returns (address to, bytes calldata data, Enum.Operation operation, bytes calldata rest)
    {
        operation = Enum.Operation(uint8(transactions[0]));
        to = address(uint160(bytes20(transactions[1:21])));
        // value = uint256(bytes32(transactions[21:53]));
        uint256 dataLength = uint256(bytes32(transactions[53:85]));
        data = transactions[85:85 + dataLength];

        rest = transactions[85 + dataLength:];
    }

    /**
     * @notice Internal function to check if the transaction is a set transaction within this guard.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction.
     * @return status A boolean indicating if the transaction is a set transaction within this guard.
     */
    function _setTransactions(address to, bytes4 selector, Enum.Operation operation)
        internal
        view
        returns (bool status)
    {
        if (to != address(this)) {
            return false;
        }
        if (operation != Enum.Operation.Call) {
            return false;
        }
        if (
            selector != this.setAllowedTx.selector && selector != this.setCosigner.selector
                && selector != this.setAllowedTokenTransfer.selector && selector != this.scheduleGuardRemoval.selector
        ) {
            return false;
        }
        return true;
    }

    /**
     * @inheritdoc ITransactionGuard
     */
    function checkAfterExecution(bytes32, bool) external {
        // This function is called after the transaction is executed, so we can check if the guard should be removed
        _checkAfterExecution();
    }

    /**
     * @inheritdoc IModuleGuard
     */
    function checkAfterModuleExecution(bytes32, bool) external {
        // This function is called after the transaction is executed, so we can check if the guard should be removed
        _checkAfterExecution();
    }

    /**
     * @notice Internal function to check the state of the guard after execution.
     * @dev This function checks if the guard is still set up correctly and check removal setup, if necessary.
     */
    function _checkAfterExecution() internal virtual {
        ISafe safe = ISafe(payable(msg.sender));
        address guard = abi.decode(safe.getStorageAt(GUARD_STORAGE_SLOT, 1), (address));
        address moduleGuard = abi.decode(safe.getStorageAt(MODULE_GUARD_STORAGE_SLOT, 1), (address));

        // Higher chance of this being true, so added the check first as a circuit breaker
        if (guard == address(this) && moduleGuard == address(this)) {
            return;
        } else if (guard != address(this) && moduleGuard != address(this)) {
            _removeGuard();
        } else if (guard != address(this) || moduleGuard != address(this)) {
            revert ImproperGuardSetup();
        }
    }

    /**
     * @notice Internal function to check if the guards are set.
     * @return status A boolean indicating if the guards are set correctly.
     * @dev This function checks both the Tx Guard and the Module Guard.
     */
    function _checkGuardsSet() internal view virtual returns (bool) {
        ISafe safe = ISafe(payable(msg.sender));
        address guard = abi.decode(safe.getStorageAt(GUARD_STORAGE_SLOT, 1), (address));
        address moduleGuard = abi.decode(safe.getStorageAt(MODULE_GUARD_STORAGE_SLOT, 1), (address));

        return guard == address(this) && moduleGuard == address(this);
    }

    /**
     * @notice Function to set an allowed transaction type.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction.
     * @param reset Whether to reset the timestamp to 0 (immediate allowance).
     * @dev This function allows setting a transaction type that can be executed without delay.
     */
    function setAllowedTx(address to, bytes4 selector, Enum.Operation operation, bool reset) public virtual {
        uint256 activeFrom = reset ? 0 : _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        bytes32 txId = keccak256(abi.encode(to, selector, operation));
        allowedTxs[msg.sender][txId] = activeFrom;

        emit TxAllowed(msg.sender, to, selector, operation, activeFrom);
    }

    /**
     * @notice Function to set a cosigner for the Safe account.
     * @param cosigner The address of the cosigner.
     * @param reset Whether to reset the timestamp to 0 (immediate allowance).
     * @dev This function allows setting a cosigner that can approve transactions without delay.
     */
    function setCosigner(address cosigner, bool reset) public virtual {
        uint256 activeFrom = reset ? 0 : _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        cosignerInfos[msg.sender] = CosignerInfo({activeFrom: activeFrom, cosigner: cosigner});

        emit CosignerSet(msg.sender, cosigner, activeFrom);
    }

    /**
     * @notice Function to set an allowed token transfer.
     * @param token The address of the token contract.
     * @param recipient The address the tokens are sent to.
     * @param amount The amount of tokens that can be transferred in a single transaction.
     * @param reset Whether to reset the timestamp to 0 (immediate allowance).
     * @dev This function allows setting a token transfer that can be executed without delay.
     */
    function setAllowedTokenTransfer(address token, address recipient, uint256 amount, bool reset) public virtual {
        uint256 activeFrom = reset ? 0 : _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        allowedTokenTransferInfos[msg.sender][token][recipient] = TokenTransferInfo(activeFrom, amount);

        emit TokenTransferAllowed(msg.sender, token, recipient, amount, activeFrom);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool supported) {
        supported = interfaceId == type(IERC165).interfaceId || interfaceId == type(IModuleGuard).interfaceId
            || interfaceId == type(ITransactionGuard).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a transaction would be allowed without executing it.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @return allowed True if the transaction would be allowed, false otherwise.
     * @return reason A string describing why the transaction is not allowed (empty if allowed).
     */
    function isTransactionAllowed(address safe, address to, bytes calldata data, Enum.Operation operation)
        public
        view
        returns (bool allowed, string memory reason)
    {
        bytes4 selector = _decodeSelector(data);

        // Check for guard internal transactions
        if (_setTransactions(to, selector, operation)) {
            return (true, "");
        }

        // Check for guard removal transactions
        if (_isGuardRemovalTransaction(safe, to, data)) {
            return (true, "");
        }

        // Check for token transfer allowances first
        if (selector == IERC20.transfer.selector && operation == Enum.Operation.Call && data.length > 67) {
            (address recipient, uint256 amount) = abi.decode(data[4:], (address, uint256));
            TokenTransferInfo memory tokenTransferInfo = allowedTokenTransferInfos[safe][to][recipient];

            if (tokenTransferInfo.amount > 0) {
                if (tokenTransferInfo.activeFrom == 0 || tokenTransferInfo.activeFrom > block.timestamp) {
                    return (false, "Token transfer not yet active");
                }
                if (amount > tokenTransferInfo.amount) {
                    return (false, "Token transfer exceeds limit");
                }
                return (true, "");
            }
        }

        // Check for general allowed transactions
        bytes32 txId = keccak256(abi.encode(to, selector, operation));
        if (allowedTxs[safe][txId] > 0 && allowedTxs[safe][txId] <= block.timestamp) {
            // Check if the transaction is a multiSend
            if (selector == MultiSendCallOnly.multiSend.selector) {
                bytes calldata transactions = _decodeMultiSendTransactions(data);
                while (transactions.length > 0) {
                    address nextTo;
                    bytes calldata nextData;
                    Enum.Operation nextOperation;
                    (nextTo, nextData, nextOperation, transactions) = _decodeNextTransaction(transactions);
                    (bool nextAllowed, string memory nextReason) =
                        isTransactionAllowed(safe, nextTo, nextData, nextOperation);
                    if (!nextAllowed) {
                        return (false, nextReason);
                    }
                }
            }
            return (true, "");
        }

        return (false, "Transaction not allowed - first time execution");
    }

    /**
     * @notice Check if a cosigner is active for a given Safe.
     * @param safe The address of the Safe contract.
     * @return active True if the cosigner is active, false otherwise.
     * @return cosigner The address of the cosigner.
     * @return activeFrom The timestamp from which the cosigner is active.
     */
    function getCosignerInfo(address safe) external view returns (bool active, address cosigner, uint256 activeFrom) {
        CosignerInfo memory info = cosignerInfos[safe];
        active = info.activeFrom > 0 && info.activeFrom <= block.timestamp;
        cosigner = info.cosigner;
        activeFrom = info.activeFrom;
    }
}
