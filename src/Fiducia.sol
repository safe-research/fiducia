// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ITransactionGuard, IERC165} from "safe-smart-account/contracts/base/GuardManager.sol";
import {IModuleGuard} from "safe-smart-account/contracts/base/ModuleManager.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {SafeInterface} from "./interfaces/SafeInterface.sol";
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
     * @param maxAmount The maximum amount of tokens that can be transferred in a single transaction.
     * @dev This struct is used to manage token transfers and their limits.
     *      IMPROVEMENT: Can have limit of tokens which can be transferred within a timeframe in next version.
     */
    struct TokenTransferInfo {
        uint256 activeFrom;
        uint256 maxAmount;
    }

    /**
     * @notice The storage slot for the guard
     * @dev This is used to check if the guard is set
     *      Value = `keccak256("guard_manager.guard.address")`
     */
    uint256 public constant GUARD_STORAGE_SLOT =
        uint256(0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8);

    /**
     * @notice The storage slot for the module guard
     * @dev This is used to check if the module guard is set
     *      Value = `keccak256("module_manager.module_guard.address")`
     */
    uint256 public constant MODULE_GUARD_STORAGE_SLOT =
        uint256(0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947);

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
     *      txIdentifier The identifier for the transaction, is a hash of the transaction details (to, selector, operation, required data)
     *      timestamp The timestamp when the transaction is allowed.
     */
    mapping(address safe => mapping(bytes32 txIdentifier => uint256 timestamp)) public allowedTx;

    /**
     * @notice The mapping of allowed token transactions.
     * @dev safe The address of the safe.
     *      tokenIdentifier The identifier for the token transfer, is a hash of the token address & recipient address.
     *      timestamp The timestamp when the token transfer is allowed.
     */
    mapping(address safe => mapping(bytes32 tokenIdentifier => TokenTransferInfo tokenTransferInfo)) public
        allowedTokenTxInfos;

    /**
     * @notice The mapping of cosigner information.
     * @dev safe The address of the safe.
     *      CosignerInfo The information about the cosigner.
     */
    mapping(address safe => CosignerInfo cosigner) public cosignerInfos;

    event GuardRemovalScheduled(address indexed safe, uint256 timestamp);
    event TxAllowed(
        address indexed safe, address indexed to, bytes4 selector, Enum.Operation operation, uint256 timestamp
    );
    event CosignerSet(address indexed safe, address indexed cosigner, uint256 activeFrom);
    event TokenTransferAllowed(
        address indexed safe, address indexed token, address indexed to, uint256 amount, uint256 activeFrom
    );

    error InvalidTimestamp();
    error TokenTransferNotAllowed();
    error TokenTransferExceedsLimit();
    error FirstTimeTx();
    error InvalidSelector();
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
        removalSchedule[msg.sender] = DELAY + block.timestamp;

        emit GuardRemovalScheduled(msg.sender, DELAY + block.timestamp);
    }

    /**
     * @notice Internal function to check if the guard removal is scheduled
     */
    function _removeGuard() internal {
        uint256 removalTimestamp = removalSchedule[msg.sender];
        require(removalTimestamp > 0 && removalTimestamp < block.timestamp, InvalidTimestamp());

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
        bytes32 safeTxHash = SafeInterface(payable(safe)).getTransactionHash(
            to,
            value,
            data,
            operation,
            0,
            0,
            0,
            address(0),
            address(0),
            SafeInterface(payable(safe)).nonce() - 1 // The Guard check is executed post nonce increment, so we need to subtract 1 from the nonce.
        );
        bytes32 txId = keccak256(abi.encode(to, _decodeSelector(data), operation));

        // Retrieve the co-signer configured for the Safe account.
        CosignerInfo memory info = cosignerInfos[safe];

        // Check if the cosigner is active
        if (info.activeFrom > 0 && info.activeFrom <= block.timestamp) {
            status = SignatureChecker.isValidSignatureNow(info.cosigner, safeTxHash, _decodeContext(signature));
            if (status) {
                // Add the txId to allowed transactions immediately.
                allowedTx[safe][txId] = block.timestamp;
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Decodes additional context to pass to the policy from the signatures bytes.
     */
    function _decodeContext(bytes calldata signatures) internal pure returns (bytes calldata) {
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

    function _emptyContext() internal pure returns (bytes calldata) {
        return msg.data[0:0];
    }

    /**
     * @notice Internal function to check if a transaction is allowed.
     * @param safe The address of the Safe contract.
     * @param to The address the transaction is sent to.
     * @param data The data payload of the transaction.
     * @param operation The operation type of the transaction.
     * @dev This function checks if the transaction is allowed mainly based on the allowed transactions mapping.
     */
    function _checkTransaction(address safe, address to, bytes calldata data, Enum.Operation operation) internal {
        bytes4 selector = _decodeSelector(data);
        bytes32 txId = keccak256(abi.encode(to, selector, operation));

        if (selector == MultiSendCallOnly.multiSend.selector) {
            bytes calldata transactions = _decodeMultiSendTransactions(data);
            while (transactions.length > 0) {
                (to, data, operation, transactions) = _decodeNextTransaction(transactions);
                _checkTransaction(safe, to, data, operation);
            }
            return;
        } else if (selector == IERC20.transfer.selector) {
            // IMPROVEMENT: Support for IERC20.transferFrom
            (address recipient, uint256 amount) = abi.decode(data[4:], (address, uint256));
            bytes32 tokenId = keccak256(abi.encode(to, recipient));
            TokenTransferInfo memory tokenTransferInfo = allowedTokenTxInfos[safe][tokenId];
            require(
                tokenTransferInfo.activeFrom > 0 && tokenTransferInfo.activeFrom <= block.timestamp,
                TokenTransferNotAllowed()
            );
            require(amount <= tokenTransferInfo.maxAmount, TokenTransferExceedsLimit());
            return;
        } else if (_setTransactions(to, selector, operation)) {
            return;
        } else if (_isGuardRemovalTransaction(safe, to, data)) {
            return;
        } else if (allowedTx[safe][txId] > 0 && allowedTx[safe][txId] <= block.timestamp) {
            return;
        }

        revert FirstTimeTx();
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
            if (selector == SafeInterface(payable(safe)).setGuard.selector) {
                address newGuard = abi.decode(data[4:], (address));
                return newGuard == address(0);
            } else if (selector == SafeInterface(payable(safe)).setModuleGuard.selector) {
                address newGuard = abi.decode(data[4:], (address));
                return newGuard == address(0);
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
        SafeInterface safe = SafeInterface(payable(msg.sender));
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

    function _checkGuardsSet() internal view returns (bool set) {
        SafeInterface safe = SafeInterface(payable(msg.sender));
        address guard = abi.decode(safe.getStorageAt(GUARD_STORAGE_SLOT, 1), (address));
        address moduleGuard = abi.decode(safe.getStorageAt(MODULE_GUARD_STORAGE_SLOT, 1), (address));

        if (guard == address(this) && moduleGuard == address(this)) {
            set = true;
        }
    }

    /**
     * @notice Function to set an allowed transaction type.
     * @param to The address the transaction is sent to.
     * @param selector The function selector of the transaction.
     * @param operation The operation type of the transaction.
     * @dev This function allows setting a transaction type that can be executed without delay.
     */
    function setAllowedTx(address to, bytes4 selector, Enum.Operation operation) public {
        uint256 allowedTimestamp = _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        bytes32 txId = keccak256(abi.encode(to, selector, operation));
        allowedTx[msg.sender][txId] = allowedTimestamp;

        emit TxAllowed(msg.sender, to, selector, operation, allowedTimestamp);
    }

    /**
     * @notice Function to set a cosigner for the Safe account.
     * @param cosigner The address of the cosigner.
     * @dev This function allows setting a cosigner that can approve transactions without delay.
     */
    function setCosigner(address cosigner) public {
        uint256 allowedTimestamp = _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        cosignerInfos[msg.sender] = CosignerInfo(allowedTimestamp, cosigner);

        emit CosignerSet(msg.sender, cosigner, allowedTimestamp);
    }

    /**
     * @notice Function to set an allowed token transfer.
     * @param token The address of the token contract.
     * @param to The address the tokens are sent to.
     * @param maxAmount The maximum amount of tokens that can be transferred in a single transaction.
     * @dev This function allows setting a token transfer that can be executed without delay.
     */
    function setAllowedTokenTransfer(address token, address to, uint256 maxAmount) public {
        uint256 allowedTimestamp = _checkGuardsSet() ? block.timestamp + DELAY : block.timestamp;
        bytes32 tokenId = keccak256(abi.encode(token, to));
        allowedTokenTxInfos[msg.sender][tokenId] = TokenTransferInfo(allowedTimestamp, maxAmount);

        emit TokenTransferAllowed(msg.sender, token, to, maxAmount, allowedTimestamp);
    }

    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool supported) {
        supported = interfaceId == type(IERC165).interfaceId || interfaceId == type(IModuleGuard).interfaceId
            || interfaceId == type(ITransactionGuard).interfaceId;
    }
}
