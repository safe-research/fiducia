/**
 * Type definitions for the Fiducia app
 */

/**
 * Form data for setting allowed transactions
 */
export interface SetAllowedTxFormData {
  /** Target contract address for the transaction */
  to: string
  /** Function selector (4 bytes) - leave empty for value transfers */
  selector: string
  /** Operation type: 0 = Call, 1 = DelegateCall */
  operation: number
  /** Whether to reset/remove the allowance instead of adding it */
  reset: boolean
}

/**
 * Form data for setting a cosigner
 */
export interface SetCosignerFormData {
  /** Address of the cosigner (optional, defaults to zero address) */
  cosignerAddress?: string
  /** Whether to reset/remove the cosigner instead of setting it */
  reset: boolean
}

/**
 * Form data for setting allowed token transfers
 */
export interface SetAllowedTokenTransferFormData {
  /** Address of the token contract */
  tokenAddress: string
  /** Address of the allowed recipient */
  recipientAddress: string
  /** Amount that can be transferred */
  amount: bigint
  /** Whether to reset/remove the allowance instead of adding it */
  reset: boolean
}

/**
 * Transaction information structure
 */
export interface AllowedTxInfo {
  /** Target contract address */
  to: string
  /** Function selector */
  selector: string
  /** Operation type as string */
  operation: string
  /** Timestamp when the allowance becomes active (in milliseconds) */
  activeFrom: bigint
}

/**
 * Token transfer information structure
 */
export interface AllowedTokenTransferInfo {
  /** Token contract address */
  token: string
  /** Recipient address */
  recipient: string
  /** Allowed amount */
  amount: bigint
  /** Timestamp when the allowance becomes active (in milliseconds) */
  activeFrom: bigint
}

/**
 * Cosigner information structure
 */
export interface CosignerInfo {
  /** Cosigner address */
  cosigner: string
  /** Timestamp when the cosigner becomes active (in milliseconds) */
  activeFrom: bigint
}
