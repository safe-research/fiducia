import { ethers } from 'ethers'

// Configuration constants for the Fiducia app
export const FIDUCIA_ADDRESS_SEPOLIA = ethers.getAddress(
  '0x7bdc54da3dfe4675a43048b3bb2e5cd7fa809283'
) // Sepolia
export const FIDUCIA_ADDRESS_GNOSIS = ethers.getAddress(
  '0x7bdc54da3dfe4675a43048b3bb2e5cd7fa809283'
) // Gnosis
export const MULTISEND_CALL_ONLY = ethers.getAddress(
  '0x9641d764fc13c8B624c04430C7356C1C7C8102e2'
) // Sepolia

// Storage slots for Safe contract
export const GUARD_STORAGE_SLOT =
  '0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8' as const
export const MODULE_GUARD_STORAGE_SLOT =
  '0xb104e0b93118902c651344349b610029d694cfdec91c589c91ebafbcd0289947' as const

// Contract ABI interface
export const CONTRACT_INTERFACE_ABI = [
  'function setGuard(address guard)',
  // "function setModuleGuard(address moduleGuard)",
  'function getStorageAt(uint256 offset, uint256 length) public view returns (bytes memory)',
  'function removalSchedule(address safe) public view returns (uint256)',
  'function scheduleGuardRemoval() public',
  'function setAllowedTx(address to, bytes4 selector, uint8 operation, bool reset) public',
  'function setCosigner(address cosigner, bool reset) public',
  'function setAllowedTokenTransfer(address token, address to, uint256 maxAmount, bool reset) public',
  'function getTxIdentifierInfo(bytes32 txIdentifier) external view returns (tuple(address to, bytes4 selector, uint8 operation) memory)',
  'function getTxIdentifiers(address account) external view returns (bytes32[] memory)',
  'function getTokenIdentifierInfo(bytes32 tokenId) external view returns (tuple(address to, address recipient) memory)',
  'function getTokenIdentifiers(address account) external view returns (bytes32[] memory)',
  'function allowedTxs(address safe, bytes32 txIdentifier) public view returns (uint256 timestamp)',
  'function allowedTokenTransferInfos(address safe, bytes32 tokenIdentifier) public view returns (tuple(uint256 activeFrom, uint256 maxAmount) memory)',
  'function cosignerInfos(address safe) public view returns (tuple(uint256 allowedTimestamp, address cosigner) memory)',
  'function multiSend(bytes memory transactions) public payable',
  'function decimals() public view returns (uint8)',
] as const

// Time constants
export const MILLISECONDS_IN_SECOND = 1000n
