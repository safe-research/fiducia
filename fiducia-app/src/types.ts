// Type definitions for the Fiducia app

export interface SetAllowedTxFormData {
  to: string
  selector: string
  operation: number // Enum.Operation
  reset: boolean
}

export interface SetCosignerFormData {
  cosignerAddress?: string
  reset: boolean
}

export interface SetAllowedTokenTransferFormData {
  tokenAddress: string
  recipientAddress: string
  maxAmount: bigint
  reset: boolean
}
