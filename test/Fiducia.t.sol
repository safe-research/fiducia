// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Fiducia} from "../src/Fiducia.sol";
import {Enum} from "safe-smart-account/contracts/libraries/Enum.sol";
import {SafeL2} from "safe-smart-account/contracts/SafeL2.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {ERC20Token} from "safe-smart-account/contracts/test/ERC20Token.sol";
import {MultiSendCallOnly} from "safe-smart-account/contracts/libraries/MultiSendCallOnly.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ITransactionGuard} from "safe-smart-account/contracts/base/GuardManager.sol";
import {IModuleGuard} from "safe-smart-account/contracts/base/ModuleManager.sol";
import {MockModule} from "../src/test/MockModule.sol";

contract FiduciaTest is Test {
    // Constants
    uint256 public constant DELAY = 1 days;
    bytes32 public constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    bytes32 public constant MODULE_GUARD_STORAGE_SLOT =
        0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947;

    // Contract instances
    Fiducia public fiducia;
    SafeL2 public safe;
    SafeProxyFactory public safeProxyFactory;
    ERC20Token public testToken;
    address public multiSendLibrary;

    // Addresses and keys
    address public owner;
    uint256 public ownerPrivateKey;
    address public cosigner;
    uint256 public cosignerPrivateKey;
    address public recipient;
    address[] public owners;

    // Test variables
    uint256 public threshold = 1;
    bytes public emptyBytes = "";
    address public zeroAddress = address(0);

    function setUp() public {
        // Setup addresses
        (owner, ownerPrivateKey) = makeAddrAndKey("owner");
        (cosigner, cosignerPrivateKey) = makeAddrAndKey("cosigner");
        recipient = makeAddr("recipient");
        owners = [owner];

        // Deploy contracts
        fiducia = new Fiducia(DELAY);
        vm.prank(owner);
        testToken = new ERC20Token();
        multiSendLibrary = address(new MultiSendCallOnly());

        // Setup Safe
        setupSafe();

        // Fund safe with tokens and ETH
        vm.deal(address(safe), 10 ether);
        vm.prank(owner);
        testToken.transfer(address(safe), 500e12); // Transfer half of the minted tokens
    }

    /*//////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Sets up a Safe contract instance
     */
    function setupSafe() private {
        address singleton = address(new SafeL2());
        safeProxyFactory = new SafeProxyFactory();

        bytes memory setupData = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            zeroAddress,
            emptyBytes,
            zeroAddress,
            zeroAddress,
            0,
            payable(zeroAddress)
        );

        safe = SafeL2(payable(safeProxyFactory.createProxyWithNonce(singleton, setupData, 1)));
    }

    /**
     * @dev Helper to get executor signature for Safe transactions
     */
    function getExecutorSignature(address signer) private pure returns (bytes memory) {
        return abi.encodePacked(abi.encode(signer), bytes32(0), uint8(1));
    }

    /**
     * @dev Sets up both transaction and module guards in a single multisend transaction
     */
    function setupGuard() private {
        bytes memory guardSetupData = abi.encodeWithSelector(safe.setGuard.selector, address(fiducia));
        bytes memory moduleGuardSetupData = abi.encodeWithSelector(safe.setModuleGuard.selector, address(fiducia));

        bytes[] memory txs = new bytes[](2);

        // Transaction guard setup
        txs[0] = abi.encodePacked(
            uint8(0), // Operation: Call
            address(safe), // Target
            uint256(0), // Value
            guardSetupData.length,
            guardSetupData
        );

        // Module guard setup
        txs[1] = abi.encodePacked(
            uint8(0), // Operation: Call
            address(safe), // Target
            uint256(0), // Value
            moduleGuardSetupData.length,
            moduleGuardSetupData
        );

        bytes memory transactions;
        for (uint256 i = 0; i < txs.length; i++) {
            transactions = abi.encodePacked(transactions, txs[i]);
        }

        bytes memory multiSendTxs = abi.encodeWithSelector(MultiSendCallOnly.multiSend.selector, transactions);

        vm.prank(owner);
        safe.execTransaction(
            multiSendLibrary,
            0,
            multiSendTxs,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /**
     * @dev Creates multisend data for guard removal
     */
    function removeGuardData() private view returns (bytes memory) {
        bytes memory guardRemoveData = abi.encodeWithSelector(safe.setGuard.selector, zeroAddress);
        bytes memory moduleGuardRemoveData = abi.encodeWithSelector(safe.setModuleGuard.selector, zeroAddress);

        bytes[] memory txs = new bytes[](2);

        txs[0] = abi.encodePacked(uint8(0), address(safe), uint256(0), guardRemoveData.length, guardRemoveData);

        txs[1] =
            abi.encodePacked(uint8(0), address(safe), uint256(0), moduleGuardRemoveData.length, moduleGuardRemoveData);

        bytes memory transactions;
        for (uint256 i = 0; i < txs.length; i++) {
            transactions = abi.encodePacked(transactions, txs[i]);
        }

        return abi.encodeWithSelector(MultiSendCallOnly.multiSend.selector, transactions);
    }

    /**
     * @dev Creates a cosigner signature for Safe transaction
     */
    function createCosignerSignature(address to, uint256 value, bytes memory data, Enum.Operation operation)
        private
        view
        returns (bytes memory)
    {
        bytes32 safeTxHash =
            safe.getTransactionHash(to, value, data, operation, 0, 0, 0, zeroAddress, zeroAddress, safe.nonce());

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, safeTxHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Add signature length at the end
        return abi.encodePacked(signature, uint256(signature.length));
    }

    /*//////////////////////////////////////////////////////////////
                              GUARD SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test setting up the guard for a Safe
     */
    function testSettingUpGuard() public {
        // Initially no guard is set
        assertEq(abi.decode(safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1), (address)), zeroAddress);
        assertEq(abi.decode(safe.getStorageAt(uint256(MODULE_GUARD_STORAGE_SLOT), 1), (address)), zeroAddress);

        setupGuard();

        // Guard should be set after setup
        assertEq(abi.decode(safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1), (address)), address(fiducia));
        assertEq(abi.decode(safe.getStorageAt(uint256(MODULE_GUARD_STORAGE_SLOT), 1), (address)), address(fiducia));
    }

    /*//////////////////////////////////////////////////////////////
                           TRANSACTION DELAY TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test that transaction delay is enforced after guard setup
     */
    function testTxDelayEnforcedAfterGuardSetup() public {
        setupGuard();

        // Try to execute a transaction to a new address without prior allowance
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        vm.expectRevert(Fiducia.FirstTimeTx.selector);
        safe.execTransaction(
            newRecipient,
            1 ether,
            emptyBytes,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /**
     * @dev Test immediate transaction execution when cosigner signs
     */
    function testImmediateTxExecutionWithCosigner() public {
        // Set cosigner first
        bytes memory setCosignerData = abi.encodeWithSelector(fiducia.setCosigner.selector, cosigner);
        vm.prank(owner);
        safe.execTransaction(
            address(fiducia),
            0,
            setCosignerData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Setup guard
        setupGuard();

        // Create transaction with cosigner signature
        bytes memory cosignerSig = createCosignerSignature(recipient, 1 ether, emptyBytes, Enum.Operation.Call);

        uint256 initialBalance = recipient.balance;

        vm.prank(owner);
        safe.execTransaction(
            recipient,
            1 ether,
            emptyBytes,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            abi.encodePacked(getExecutorSignature(owner), cosignerSig)
        );

        // Transaction should execute immediately
        assertEq(recipient.balance - initialBalance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                           GUARD REMOVAL TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test guard removal requires delay
     */
    function testGuardRemovalRequiresDelay() public {
        setupGuard();

        // Schedule guard removal
        bytes memory scheduleData = abi.encodeWithSelector(fiducia.scheduleGuardRemoval.selector);
        vm.prank(owner);
        safe.execTransaction(
            address(fiducia),
            0,
            scheduleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Wait for delay
        vm.warp(block.timestamp + DELAY + 1);

        // Remove guard
        bytes memory removeData = removeGuardData();
        vm.prank(owner);
        safe.execTransaction(
            multiSendLibrary,
            0,
            removeData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Guard should be removed
        assertEq(abi.decode(safe.getStorageAt(uint256(GUARD_STORAGE_SLOT), 1), (address)), zeroAddress);
        assertEq(abi.decode(safe.getStorageAt(uint256(MODULE_GUARD_STORAGE_SLOT), 1), (address)), zeroAddress);
    }

    /**
     * @dev Test revert if guard removal is tried before delay
     */
    function testRevertGuardRemovalBeforeDelay() public {
        setupGuard();

        // Schedule guard removal
        bytes memory scheduleData = abi.encodeWithSelector(fiducia.scheduleGuardRemoval.selector);
        vm.prank(owner);
        safe.execTransaction(
            address(fiducia),
            0,
            scheduleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Try to remove guard immediately (should fail)
        bytes memory removeData = removeGuardData();
        vm.prank(owner);
        // In this, the timestamp check is done within _isGuardRemovalTransaction and returned false.
        // Thus it errors out with FirstTimeTx instead of InvalidTimestamp.
        vm.expectRevert(Fiducia.FirstTimeTx.selector);
        safe.execTransaction(
            multiSendLibrary,
            0,
            removeData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /**
     * @dev Test revert when only one guard is removed
     */
    function testRevertSingleGuardRemoval() public {
        setupGuard();

        // Schedule guard removal
        bytes memory scheduleData = abi.encodeWithSelector(fiducia.scheduleGuardRemoval.selector);
        vm.prank(owner);
        safe.execTransaction(
            address(fiducia),
            0,
            scheduleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Wait for delay
        vm.warp(block.timestamp + DELAY + 1);

        // Try to remove only transaction guard
        bytes memory guardRemoveData = abi.encodeWithSelector(safe.setGuard.selector, zeroAddress);
        bytes memory guardRemovalTx =
            abi.encodePacked(uint8(0), address(safe), uint256(0), guardRemoveData.length, guardRemoveData);

        bytes memory partialRemoveData = abi.encodeWithSelector(MultiSendCallOnly.multiSend.selector, guardRemovalTx);

        vm.prank(owner);
        vm.expectRevert(Fiducia.ImproperGuardSetup.selector);
        safe.execTransaction(
            multiSendLibrary,
            0,
            partialRemoveData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ALLOWED TRANSACTION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test addition of allowed transaction immediately when guard is not setup
     */
    function testAddAllowedTxImmediatelyNoGuard() public {
        vm.prank(address(safe));
        vm.expectEmit(true, true, false, true);
        emit Fiducia.TxAllowed(address(safe), recipient, bytes4(0), Enum.Operation.Call, block.timestamp);
        fiducia.setAllowedTx(recipient, bytes4(0), Enum.Operation.Call);

        // Should be immediately allowed
        bytes32 txId = keccak256(abi.encode(recipient, bytes4(0), Enum.Operation.Call));
        assertEq(fiducia.allowedTx(address(safe), txId), block.timestamp);
    }

    /**
     * @dev Test addition of allowed transaction after delay when guard is setup
     */
    function testAddAllowedTxWithDelayGuardSetup() public {
        setupGuard();

        vm.prank(address(safe));
        vm.expectEmit(true, true, false, true);
        emit Fiducia.TxAllowed(address(safe), recipient, bytes4(0), Enum.Operation.Call, block.timestamp + DELAY);
        fiducia.setAllowedTx(recipient, bytes4(0), Enum.Operation.Call);

        // Should be allowed after delay
        bytes32 txId = keccak256(abi.encode(recipient, bytes4(0), Enum.Operation.Call));
        assertEq(fiducia.allowedTx(address(safe), txId), block.timestamp + DELAY);
    }

    /*//////////////////////////////////////////////////////////////
                           COSIGNER TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test addition of allowed cosigner immediately when guard is not setup
     */
    function testAddCosignerImmediatelyNoGuard() public {
        vm.prank(address(safe));
        vm.expectEmit(true, true, false, true);
        emit Fiducia.CosignerSet(address(safe), cosigner, block.timestamp);
        fiducia.setCosigner(cosigner);

        (uint256 activeFrom, address cosignerAddr) = fiducia.cosignerInfos(address(safe));
        assertEq(activeFrom, block.timestamp);
        assertEq(cosignerAddr, cosigner);
    }

    /**
     * @dev Test addition of allowed cosigner after delay when guard is setup
     */
    function testAddCosignerWithDelayGuardSetup() public {
        setupGuard();

        vm.prank(address(safe));
        vm.expectEmit(true, true, false, true);
        emit Fiducia.CosignerSet(address(safe), cosigner, block.timestamp + DELAY);
        fiducia.setCosigner(cosigner);

        (uint256 activeFrom, address cosignerAddr) = fiducia.cosignerInfos(address(safe));
        assertEq(activeFrom, block.timestamp + DELAY);
        assertEq(cosignerAddr, cosigner);
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN TRANSFER TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test addition of token transfer immediately when guard is not setup
     */
    function testAddTokenTransferImmediatelyNoGuard() public {
        uint256 maxAmount = 100e12;

        vm.prank(address(safe));
        vm.expectEmit(true, true, true, true);
        emit Fiducia.TokenTransferAllowed(address(safe), address(testToken), recipient, maxAmount, block.timestamp);
        fiducia.setAllowedTokenTransfer(address(testToken), recipient, maxAmount);

        bytes32 tokenId = keccak256(abi.encode(address(testToken), recipient));
        (uint256 activeFrom, uint256 storedMaxAmount) = fiducia.allowedTokenTxInfos(address(safe), tokenId);
        assertEq(activeFrom, block.timestamp);
        assertEq(storedMaxAmount, maxAmount);
    }

    /**
     * @dev Test addition of token transfer after delay when guard is setup
     */
    function testAddTokenTransferWithDelayGuardSetup() public {
        setupGuard();
        uint256 maxAmount = 100e12;

        vm.prank(address(safe));
        vm.expectEmit(true, true, true, true);
        emit Fiducia.TokenTransferAllowed(
            address(safe), address(testToken), recipient, maxAmount, block.timestamp + DELAY
        );
        fiducia.setAllowedTokenTransfer(address(testToken), recipient, maxAmount);

        bytes32 tokenId = keccak256(abi.encode(address(testToken), recipient));
        (uint256 activeFrom, uint256 storedMaxAmount) = fiducia.allowedTokenTxInfos(address(safe), tokenId);
        assertEq(activeFrom, block.timestamp + DELAY);
        assertEq(storedMaxAmount, maxAmount);
    }

    /**
     * @dev Test token transfer execution with proper allowance
     */
    function testTokenTransferExecution() public {
        uint256 transferAmount = 50e12;
        uint256 maxAmount = 100e12;

        // Set token transfer allowance
        vm.prank(address(safe));
        fiducia.setAllowedTokenTransfer(address(testToken), recipient, maxAmount);

        // Setup guard
        setupGuard();

        // Execute token transfer
        bytes memory transferData = abi.encodeWithSelector(testToken.transfer.selector, recipient, transferAmount);

        uint256 initialBalance = testToken.balanceOf(recipient);

        vm.prank(owner);
        safe.execTransaction(
            address(testToken),
            0,
            transferData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        // Check transfer was successful
        assertEq(testToken.balanceOf(recipient) - initialBalance, transferAmount);
    }

    /**
     * @dev Test token transfer revert when exceeding limit
     */
    function testTokenTransferExceedsLimit() public {
        uint256 transferAmount = 150e12;
        uint256 maxAmount = 100e12;

        // Set token transfer allowance
        vm.prank(address(safe));
        fiducia.setAllowedTokenTransfer(address(testToken), recipient, maxAmount);

        // Setup guard
        setupGuard();

        // Try to transfer more than allowed
        bytes memory transferData = abi.encodeWithSelector(testToken.transfer.selector, recipient, transferAmount);

        vm.prank(owner);
        vm.expectRevert(Fiducia.TokenTransferExceedsLimit.selector);
        safe.execTransaction(
            address(testToken),
            0,
            transferData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MODULE TRANSACTION TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test transaction flow through module execution
     */
    function testModuleTxFlow() public {
        // Deploy mock module and enable it in Safe
        MockModule mockModule = new MockModule();
        bytes memory setModuleData = abi.encodeWithSelector(safe.enableModule.selector, address(mockModule));
        vm.prank(owner);
        safe.execTransaction(
            address(safe),
            0,
            setModuleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        setupGuard();

        // Allow a transaction through module
        vm.prank(address(safe));
        fiducia.setAllowedTx(recipient, bytes4(0), Enum.Operation.Call);

        // Wait for allowance to be active
        vm.warp(block.timestamp + DELAY + 1);

        uint256 initialBalance = recipient.balance;

        // Simulate module transaction check
        mockModule.execTransaction(address(safe), recipient, 1 ether, emptyBytes, Enum.Operation.Call);

        assertEq(recipient.balance - initialBalance, 1 ether);
    }

    /**
     * @dev Test module transaction reverts when not allowed
     */
    function testModuleTxRevertsWhenNotAllowed() public {
        // Deploy mock module and enable it in Safe
        MockModule mockModule = new MockModule();
        bytes memory setModuleData = abi.encodeWithSelector(safe.enableModule.selector, address(mockModule));
        vm.prank(owner);
        safe.execTransaction(
            address(safe),
            0,
            setModuleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );

        setupGuard();

        // Simulate module transaction check
        vm.expectRevert(Fiducia.FirstTimeTx.selector);
        mockModule.execTransaction(address(safe), recipient, 1 ether, emptyBytes, Enum.Operation.Call);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test guard removal scheduled event emission
     */
    function testGuardRemovalScheduledEvent() public {
        setupGuard();

        vm.expectEmit(true, false, false, true);
        emit Fiducia.GuardRemovalScheduled(address(safe), block.timestamp + DELAY);

        bytes memory scheduleData = abi.encodeWithSelector(fiducia.scheduleGuardRemoval.selector);
        vm.prank(owner);
        safe.execTransaction(
            address(fiducia),
            0,
            scheduleData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           INTERFACE TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test ERC165 interface support
     */
    function testSupportsInterface() public view {
        // Test IERC165 interface
        assertTrue(fiducia.supportsInterface(type(IERC165).interfaceId));
        // Test ITransactionGuard interface
        assertTrue(fiducia.supportsInterface(type(ITransactionGuard).interfaceId));
        // Test IModuleGuard interface
        assertTrue(fiducia.supportsInterface(type(IModuleGuard).interfaceId));
    }

    /*//////////////////////////////////////////////////////////////
                             REVERT TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Test various revert conditions
     */
    function testRevertInvalidSelector() public {
        setupGuard();

        // Create data with invalid selector length
        bytes memory invalidData = hex"010203"; // Less than 4 bytes

        vm.prank(owner);
        vm.expectRevert(Fiducia.InvalidSelector.selector);
        safe.execTransaction(
            recipient,
            0,
            invalidData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }

    /**
     * @dev Test token transfer not allowed revert
     */
    function testRevertTokenTransferNotAllowed() public {
        setupGuard();

        // Try token transfer without allowance
        bytes memory transferData = abi.encodeWithSelector(testToken.transfer.selector, recipient, 50e12);

        vm.prank(owner);
        vm.expectRevert(Fiducia.TokenTransferNotAllowed.selector);
        safe.execTransaction(
            address(testToken),
            0,
            transferData,
            Enum.Operation.Call,
            0,
            0,
            0,
            zeroAddress,
            payable(zeroAddress),
            getExecutorSignature(owner)
        );
    }
}
