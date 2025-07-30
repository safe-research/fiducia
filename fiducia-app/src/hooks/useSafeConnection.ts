import { useCallback, useEffect, useState } from 'react'
import { useSafeAppsSDK } from '@safe-global/safe-apps-react-sdk'
import { FIDUCIA_ADDRESS_SEPOLIA, FIDUCIA_ADDRESS_GNOSIS } from '../constants'

/**
 * Custom hook to manage Safe connection and Fiducia address selection
 * @returns Object containing safe connection state and fiducia address
 */
export const useSafeConnection = () => {
  const [fiduciaAddress, setFiduciaAddress] = useState<string>()
  const [isConnected, setIsConnected] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { safe, connected, sdk } = useSafeAppsSDK()

  const selectFiduciaAddress = useCallback(async () => {
    try {
      const chainId = (await sdk.safe.getInfo()).chainId
      if (chainId === 100) {
        setFiduciaAddress(FIDUCIA_ADDRESS_GNOSIS)
      } else if (chainId === 11155111) {
        setFiduciaAddress(FIDUCIA_ADDRESS_SEPOLIA)
      } else {
        setError('Fiducia not available in this chain')
        return
      }
      setError(null)
    } catch (err) {
      setError('Failed to get chain information: ' + err)
    }
  }, [sdk.safe])

  useEffect(() => {
    if (connected && safe) {
      setIsConnected(true)
      selectFiduciaAddress()
    } else {
      setIsConnected(false)
      // Not setting error message here, as we handle it in the App component
    }
  }, [connected, safe, selectFiduciaAddress])

  return {
    safe,
    sdk,
    fiduciaAddress,
    isConnected,
    error,
  }
}
