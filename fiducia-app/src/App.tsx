import { useCallback, useEffect, useState } from 'react'
import './App.css'
import type { BaseTransaction } from '@safe-global/safe-apps-sdk'
import { useSafeAppsSDK } from '@safe-global/safe-apps-react-sdk'
import SafeAppsSDK from '@safe-global/safe-apps-sdk'
import { ethers, ZeroAddress } from 'ethers'
import Button from '@mui/material/Button'
import {
  Alert,
  Checkbox,
  FormControlLabel,
  FormGroup,
  Paper,
  Select,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  TextField,
} from '@mui/material'
import {
  CONTRACT_INTERFACE_ABI,
  GUARD_STORAGE_SLOT,
  FIDUCIA_ADDRESS_SEPOLIA,
  FIDUCIA_ADDRESS_GNOSIS,
  MILLISECONDS_IN_SECOND,
  MULTISEND_CALL_ONLY,
} from './constants'
import type {
  SetAllowedTokenTransferFormData,
  SetAllowedTxFormData,
  SetCosignerFormData,
} from './types'

const CONTRACT_INTERFACE = new ethers.Interface(CONTRACT_INTERFACE_ABI)

const call = async (
  sdk: SafeAppsSDK,
  address: string,
  method: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  params: any[]
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
): Promise<any> => {
  const resp = await sdk.eth.call([
    {
      to: address,
      data: CONTRACT_INTERFACE.encodeFunctionData(method, params),
    },
  ])
  return CONTRACT_INTERFACE.decodeFunctionResult(method, resp)[0]
}

function App() {
  const [loading, setLoading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [fiduciaAddress, setFiduciaAddress] = useState<string>()
  const [txGuard, setTxGuard] = useState<string | null>(null)
  // const [moduleGuard, setModuleGuard] = useState<string | null>(null)
  const [fiduciaInSafe, setFiduciaInSafe] = useState<boolean>(false)
  const [removalTimestamp, setRemovalTimestamp] = useState<bigint>(0n)
  const [allowedTxInfo, setAllowedTxInfo] = useState<
    {
      to: string
      selector: string
      operation: string
      allowedTimestamp: bigint
    }[]
  >([])
  const [allowedTokenTransferInfo, setAllowedTokenTransferInfo] = useState<
    {
      token: string
      recipient: string
      maxAmount: bigint
      allowedTimestamp: bigint
    }[]
  >([])
  const [cosignerInfo, setCosignerInfo] = useState<{
    cosigner: string
    allowedTimestamp: bigint
  }>()
  const useSafeSdk = useSafeAppsSDK()
  const { safe, sdk } = useSafeSdk

  const safeConnected = useCallback(() => {
    setLoading(true)
    setErrorMessage(null)
    if (!safe) {
      setErrorMessage('No Safe connected')
      setLoading(false)
      return
    }
    setLoading(false)
  }, [safe])

  const fetchTxGuardInfo = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    try {
      // Get the Tx Guard
      const result = ethers.getAddress(
        '0x' +
          (
            await call(sdk, safe.safeAddress, 'getStorageAt', [
              GUARD_STORAGE_SLOT,
              1,
            ])
          ).slice(26)
      )
      setTxGuard(result)
    } catch (error) {
      setErrorMessage('Failed to fetch transaction guard with error: ' + error)
    } finally {
      setLoading(false)
    }
  }, [safe.safeAddress, sdk])

  // const fetchModuleGuardInfo = useCallback(async () => {
  //   setLoading(true)
  //   setErrorMessage(null)
  //   try {
  //     // Get the Module Guard
  //     const result = ethers.getAddress("0x" + (await call(sdk, safe.safeAddress, "getStorageAt", [MODULE_GUARD_STORAGE_SLOT, 1])).slice(26))
  //     setModuleGuard(result)
  //   } catch (error) {
  //     setErrorMessage('Failed to fetch module guard with error: ' + error)
  //   } finally {
  //     setLoading(false)
  //   }
  // }, [safe.safeAddress, sdk])

  const fetchGuardRemovalInfo = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    try {
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      // Check if the Tx Guard removal is already set
      const result = await call(sdk, fiduciaAddress, 'removalSchedule', [
        ethers.getAddress(safe.safeAddress),
      ])
      if (result > 0n) {
        setRemovalTimestamp(result * MILLISECONDS_IN_SECOND) // Convert to milliseconds
      }
    } catch (error) {
      setErrorMessage('Failed to fetch guard removal info with error: ' + error)
    } finally {
      setLoading(false)
    }
  }, [fiduciaAddress, safe.safeAddress, sdk])

  const fetchCurrentAllowedTxs = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    try {
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      // Fetch allowed transactions
      const result = await call(sdk, fiduciaAddress, 'getTxIdentifiers', [
        ethers.getAddress(safe.safeAddress),
      ])
      // Process the result - combine both calls in a single Promise.all
      const allowedTxs = await Promise.all(
        result.map(async (txId: string) => {
          const [timestampInfo, txInfo] = await Promise.all([
            call(sdk, fiduciaAddress, 'allowedTxs', [
              ethers.getAddress(safe.safeAddress),
              txId,
            ]),
            call(sdk, fiduciaAddress, 'getTxIdentifierInfo', [txId]),
          ])

          return {
            to: txInfo.to,
            selector: txInfo.selector == '0x00000000' ? '' : txInfo.selector,
            operation: txInfo.operation == 0 ? 'Call' : 'Delegate Call',
            allowedTimestamp: timestampInfo * MILLISECONDS_IN_SECOND,
          }
        })
      )
      setAllowedTxInfo(allowedTxs)
    } catch (error) {
      setErrorMessage(
        'Failed to fetch current allowed transactions with error: ' + error
      )
    } finally {
      setLoading(false)
    }
  }, [fiduciaAddress, safe.safeAddress, sdk])

  const fetchCurrentAllowedTokenTransfers = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    try {
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      // Fetch allowed token transactions
      const result = await call(sdk, fiduciaAddress, 'getTokenIdentifiers', [
        ethers.getAddress(safe.safeAddress),
      ])

      // Process the result - combine both calls in a single Promise.all
      const allowedTokenTxs = await Promise.all(
        result.map(async (txId: string) => {
          const [tokenInfo, txInfo] = await Promise.all([
            call(sdk, fiduciaAddress, 'allowedTokenTransferInfos', [
              ethers.getAddress(safe.safeAddress),
              txId,
            ]),
            call(sdk, fiduciaAddress, 'getTokenIdentifierInfo', [txId]),
          ])

          return {
            token: txInfo.to,
            recipient: txInfo.recipient,
            maxAmount:
              tokenInfo.maxAmount /
              10n ** (await call(sdk, txInfo.to, 'decimals', [])),
            allowedTimestamp: tokenInfo.activeFrom * MILLISECONDS_IN_SECOND,
          }
        })
      )
      setAllowedTokenTransferInfo(allowedTokenTxs)
    } catch (error) {
      setErrorMessage(
        'Failed to fetch current allowed token transactions with error: ' +
          error
      )
    } finally {
      setLoading(false)
    }
  }, [fiduciaAddress, safe.safeAddress, sdk])

  const fetchCurrentCosigner = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    try {
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      // Fetch current cosigner
      const result = await call(sdk, fiduciaAddress, 'cosignerInfos', [
        ethers.getAddress(safe.safeAddress),
      ])
      // Only one cosigner can be set in contract at a time for a Safe
      // Check if the allowedTimestamp is greater than 0, if so, set the cosigner info
      if (result.allowedTimestamp > 0) {
        setCosignerInfo({
          cosigner: result.cosigner,
          allowedTimestamp: result.allowedTimestamp * MILLISECONDS_IN_SECOND,
        })
      } else {
        setCosignerInfo({
          cosigner: ZeroAddress,
          allowedTimestamp: 0n,
        })
      }
    } catch (error) {
      setErrorMessage('Failed to fetch current cosigner with error: ' + error)
    } finally {
      setLoading(false)
    }
  }, [fiduciaAddress, safe.safeAddress, sdk])

  const selectFiduciaAddress = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    const chainId = (await sdk.safe.getInfo()).chainId
    if (chainId === 100) {
      setFiduciaAddress(FIDUCIA_ADDRESS_GNOSIS)
    } else if (chainId === 11155111) {
      setFiduciaAddress(FIDUCIA_ADDRESS_SEPOLIA)
    } else {
      setLoading(false)
      return
    }
    setLoading(false)
  }, [sdk.safe])

  useEffect(() => {
    safeConnected()
    selectFiduciaAddress()
    if (safe && safe.safeAddress && fiduciaAddress) {
      fetchGuardRemovalInfo()
      fetchCurrentAllowedTxs()
      fetchCurrentAllowedTokenTransfers()
      fetchCurrentCosigner()
      fetchTxGuardInfo()
      // fetchModuleGuardInfo()
      if (txGuard == fiduciaAddress /* && moduleGuard == fiduciaAddress*/) {
        setFiduciaInSafe(true)
      }
    } else {
      setLoading(false)
    }
  }, [
    safe,
    sdk,
    safeConnected,
    fetchGuardRemovalInfo,
    fetchCurrentAllowedTxs,
    fetchCurrentAllowedTokenTransfers,
    fetchCurrentCosigner,
    selectFiduciaAddress,
    fiduciaAddress,
    fetchTxGuardInfo,
    txGuard,
  ])

  const activateFiducia = useCallback(
    async (activate: boolean) => {
      setLoading(true)
      setErrorMessage(null)
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      const guardAddress = activate ? fiduciaAddress : ethers.ZeroAddress
      const immediateMultiSendCallOnlyAllowance = {
        to: fiduciaAddress,
        value: '0',
        data: CONTRACT_INTERFACE.encodeFunctionData('setAllowedTx', [
          ethers.getAddress(MULTISEND_CALL_ONLY), // To
          CONTRACT_INTERFACE.getFunction('multiSend')?.selector, // Selector
          1, // Enum.Operation.DelegateCall
          false, // Not resetting
        ]),
      }
      try {
        const txs: BaseTransaction[] = [
          ...(activate ? [immediateMultiSendCallOnlyAllowance] : []),
          {
            to: safe.safeAddress,
            value: '0',
            data: CONTRACT_INTERFACE.encodeFunctionData('setGuard', [
              guardAddress,
            ]),
          },
          // {
          //   to: safe.safeAddress,
          //   value: "0",
          //   data: CONTRACT_INTERFACE.encodeFunctionData("setModuleGuard", [guardAddress])
          // }
        ]
        await sdk.txs.send({
          txs,
        })
      } catch (error) {
        setErrorMessage('Failed to submit transaction: ' + error)
      } finally {
        setLoading(false)
      }
    },
    [fiduciaAddress, safe.safeAddress, sdk.txs]
  )

  const scheduleFiduciaRemoval = useCallback(async () => {
    setLoading(true)
    setErrorMessage(null)
    if (!fiduciaAddress) {
      setErrorMessage('Fiducia address not available')
      setLoading(false)
      return
    }
    try {
      const txs: BaseTransaction[] = [
        {
          to: fiduciaAddress,
          value: '0',
          data: CONTRACT_INTERFACE.encodeFunctionData('scheduleGuardRemoval'),
        },
      ]
      await sdk.txs.send({
        txs,
      })
      // Refresh the removal timestamp after scheduling
      await fetchGuardRemovalInfo()
      // while (removalTimestamp == 0n) {
      //   await new Promise(resolve => setTimeout(resolve, 60000)) // Wait for 1 minute
      //   await fetchGuardRemovalInfo() // Re-fetch the removal timestamp
      // }
    } catch (error) {
      setErrorMessage('Failed to schedule fiducia removal: ' + error)
    } finally {
      setLoading(false)
    }
  }, [fetchGuardRemovalInfo, fiduciaAddress, sdk.txs])

  const setAllowedTx = useCallback(
    async (formData: SetAllowedTxFormData) => {
      setLoading(true)
      setErrorMessage(null)
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      if (!formData.selector) {
        formData.selector = '0x00000000' // Default to a no-op selector if not provided
      }
      if (formData.selector.length !== 10) {
        setErrorMessage('Selector must be 4 bytes (8 hex characters)')
        setLoading(false)
        return
      }
      if (!formData.selector.startsWith('0x')) {
        setErrorMessage('Selector must start with 0x')
        setLoading(false)
        return
      }
      if (formData.operation !== 0 && formData.operation !== 1) {
        setErrorMessage('Operation must be Call (0) or DelegateCall (1)')
        setLoading(false)
        return
      }
      try {
        const txs: BaseTransaction[] = [
          {
            to: fiduciaAddress,
            value: '0',
            data: CONTRACT_INTERFACE.encodeFunctionData('setAllowedTx', [
              ethers.getAddress(formData.to),
              formData.selector,
              formData.operation,
              formData.reset,
            ]),
          },
        ]
        await sdk.txs.send({
          txs,
        })
      } catch (error) {
        setErrorMessage('Failed to set Tx allowance: ' + error)
      } finally {
        setLoading(false)
      }
    },
    [fiduciaAddress, sdk.txs]
  )

  const setAllowedTokenTransfer = useCallback(
    async (formData: SetAllowedTokenTransferFormData) => {
      setLoading(true)
      setErrorMessage(null)
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      try {
        const txs: BaseTransaction[] = [
          {
            to: fiduciaAddress,
            value: '0',
            data: CONTRACT_INTERFACE.encodeFunctionData(
              'setAllowedTokenTransfer',
              [
                ethers.getAddress(formData.tokenAddress),
                ethers.getAddress(formData.recipientAddress),
                formData.maxAmount,
                formData.reset,
              ]
            ),
          },
        ]
        await sdk.txs.send({
          txs,
        })
      } catch (error) {
        setErrorMessage('Failed to set token transfer allowance: ' + error)
      } finally {
        setLoading(false)
      }
    },
    [fiduciaAddress, sdk.txs]
  )

  const setCosigner = useCallback(
    async (formData: SetCosignerFormData) => {
      setLoading(true)
      setErrorMessage(null)
      if (!fiduciaAddress) {
        setErrorMessage('Fiducia address not available')
        setLoading(false)
        return
      }
      if (!formData.cosignerAddress) {
        formData.cosignerAddress = ZeroAddress
      }
      try {
        const txs: BaseTransaction[] = [
          {
            to: fiduciaAddress,
            value: '0',
            data: CONTRACT_INTERFACE.encodeFunctionData('setCosigner', [
              ethers.getAddress(formData.cosignerAddress),
              formData.reset,
            ]),
          },
        ]
        await sdk.txs.send({
          txs,
        })
      } catch (error) {
        setErrorMessage('Failed to set cosigner: ' + error)
      } finally {
        setLoading(false)
      }
    },
    [fiduciaAddress, sdk.txs]
  )

  return (
    <>
      <div>
        <a href="https://github.com/safe-research/fiducia" target="_blank">
          <img src={'./vite.svg'} className="logo" alt="Fiducia logo" />
        </a>
      </div>
      <h1>Fiducia</h1>
      <div className="card">
        {loading ? (
          <p>Loading...</p>
        ) : !useSafeSdk.connected ? (
          <div className="error">Not connected to any Safe</div>
        ) : !fiduciaAddress ? (
          <div className="error">Fiducia not available in this chain</div>
        ) : (
          <>
            {/* Enable or disable Guard */}
            <div>
              {fiduciaInSafe ? (
                removalTimestamp == 0n ? (
                  <div className="card">
                    <Alert severity="success" style={{ margin: '1em' }}>
                      Fiducia is Activated!
                    </Alert>
                    <Button
                      variant="contained"
                      onClick={() => scheduleFiduciaRemoval()}
                      disabled={loading}
                    >
                      {loading
                        ? 'Submitting transaction...'
                        : 'Schedule Fiducia Removal'}
                    </Button>
                  </div>
                ) : (
                  <div className="card">
                    {removalTimestamp > 0n &&
                    removalTimestamp < BigInt(Date.now()) ? (
                      <Button
                        variant="contained"
                        color="error"
                        onClick={() => activateFiducia(false)}
                        disabled={loading}
                      >
                        {loading
                          ? 'Submitting transaction...'
                          : 'Deactivate Fiducia'}
                      </Button>
                    ) : (
                      <>
                        <Alert severity="info" style={{ margin: '1em' }}>
                          Fiducia Removal Scheduled for{' '}
                          {new Date(Number(removalTimestamp)).toLocaleString()}
                        </Alert>
                        <Button
                          variant="contained"
                          color="error"
                          style={{
                            color: 'grey',
                            border: '1px solid',
                            borderColor: 'grey',
                          }}
                          disabled
                        >
                          {'Deactivate Fiducia'}
                        </Button>
                      </>
                    )}
                  </div>
                )
              ) : (
                <div className="card">
                  <Button
                    variant="contained"
                    color="success"
                    onClick={() => activateFiducia(true)}
                    disabled={loading}
                  >
                    {loading ? 'Submitting transaction...' : 'Activate Fiducia'}
                  </Button>
                </div>
              )}
            </div>
            <br />
            {/* Set Cosigner */}
            <div>
              <h2>Set Cosigner</h2>
              {cosignerInfo && cosignerInfo.cosigner !== ZeroAddress ? (
                <>
                  {cosignerInfo.allowedTimestamp > 0 &&
                  cosignerInfo.allowedTimestamp <= BigInt(Date.now()) ? (
                    <Alert severity="info" style={{ margin: '1em' }}>
                      Cosigner is set to {cosignerInfo.cosigner}.
                    </Alert>
                  ) : (
                    <Alert severity="warning" style={{ margin: '1em' }}>
                      Cosigner is set but will be activated at{' '}
                      {new Date(
                        Number(cosignerInfo.allowedTimestamp)
                      ).toLocaleString()}
                      .
                    </Alert>
                  )}
                </>
              ) : (
                <Alert severity="warning" style={{ margin: '1em' }}>
                  No cosigner set.
                </Alert>
              )}
              <form
                onSubmit={(e: React.FormEvent<HTMLFormElement>) => {
                  e.preventDefault()
                  const formData: SetCosignerFormData = {
                    cosignerAddress: (
                      e.currentTarget.elements.namedItem(
                        'cosignerAddress'
                      ) as HTMLInputElement
                    ).value,
                    reset: (
                      e.currentTarget.elements.namedItem(
                        'reset'
                      ) as HTMLInputElement
                    ).checked,
                  }
                  setCosigner(formData)
                }}
              >
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '10px',
                  }}
                >
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    variant="outlined"
                    type="text"
                    id="cosignerAddress"
                    name="cosignerAddress"
                    label="Cosigner Address"
                  />
                  <FormGroup>
                    <FormControlLabel
                      sx={{
                        '& .MuiCheckbox-root': { color: '#fff' },
                      }}
                      control={<Checkbox />}
                      id="reset"
                      name="reset"
                      label="Reset Cosigner"
                    />
                  </FormGroup>
                  <Button
                    variant="contained"
                    color="primary"
                    type="submit"
                    disabled={loading}
                  >
                    {loading ? 'Submitting...' : 'Set Cosigner'}
                  </Button>
                </div>
              </form>
            </div>
            <br />
            {/* Set Allowed Tx */}
            <div>
              <h2>Set Allowed Transaction</h2>
              <form
                onSubmit={(e: React.FormEvent<HTMLFormElement>) => {
                  e.preventDefault()
                  const formData: SetAllowedTxFormData = {
                    to: (
                      e.currentTarget.elements.namedItem(
                        'to'
                      ) as HTMLInputElement
                    ).value,
                    selector: (
                      e.currentTarget.elements.namedItem(
                        'selector'
                      ) as HTMLInputElement
                    ).value,
                    // Operation should have select box with two options: Call (0) and DelegateCall (1) with default value as Call (0)
                    operation: parseInt(
                      (
                        e.currentTarget.elements.namedItem(
                          'operation'
                        ) as HTMLInputElement
                      ).value
                    ),
                    reset: false,
                  }
                  setAllowedTx(formData)
                }}
              >
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '10px',
                  }}
                >
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    variant="outlined"
                    type="text"
                    id="to"
                    name="to"
                    label="To Address"
                    required
                  />
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    variant="outlined"
                    type="text"
                    id="selector"
                    name="selector"
                    label="Function Selector (4 bytes)"
                  />
                  <Select
                    slotProps={{
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-notchedOutline': {
                        borderColor: '#fff',
                      },
                      '&:hover .MuiOutlinedInput-notchedOutline': {
                        borderColor: '#fff',
                        borderWidth: '0.15rem',
                      },
                    }}
                    native
                    id="operation"
                    name="operation"
                    defaultValue={0}
                    label="Operation"
                    required
                  >
                    <option value={0}>Call</option>
                    <option value={1}>DelegateCall</option>
                  </Select>
                  <Button
                    variant="contained"
                    color="primary"
                    type="submit"
                    disabled={loading}
                  >
                    {loading ? 'Submitting...' : 'Set Allowed Tx'}
                  </Button>
                </div>
              </form>
            </div>
            <br />
            {/* Current Allowed Transactions */}
            <div>
              {allowedTxInfo.length > 0 ? (
                <>
                  <h3>Showing current allowed transactions</h3>
                  <TableContainer component={Paper}>
                    <Table
                      sx={{ minWidth: 650 }}
                      aria-label="allowed txs table"
                    >
                      <TableHead>
                        <TableRow>
                          <TableCell>To Address</TableCell>
                          <TableCell>Function Selector</TableCell>
                          <TableCell>Operation</TableCell>
                          <TableCell>Active</TableCell>
                          <TableCell></TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {allowedTxInfo.map(tx => (
                          <TableRow
                            key={tx.to + tx.selector}
                            sx={{
                              '&:last-child td, &:last-child th': { border: 0 },
                            }}
                          >
                            <TableCell component="th" scope="row">
                              {tx.to}
                            </TableCell>
                            <TableCell>{tx.selector}</TableCell>
                            <TableCell>{tx.operation}</TableCell>
                            <TableCell>
                              {tx.allowedTimestamp < BigInt(Date.now())
                                ? 'Yes'
                                : 'Will be active at ' +
                                  new Date(
                                    Number(tx.allowedTimestamp)
                                  ).toLocaleString()}
                            </TableCell>
                            <TableCell align="right">
                              <Button
                                variant="contained"
                                color="error"
                                onClick={() => {
                                  setAllowedTx({
                                    to: tx.to,
                                    selector: tx.selector,
                                    operation: tx.operation == 'Call' ? 0 : 1,
                                    reset: true,
                                  })
                                }}
                              >
                                Remove
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableContainer>
                  <p>Allowed Transactions count: {allowedTxInfo.length}</p>
                </>
              ) : (
                <>
                  <h3>Showing current allowed transactions</h3>
                  <TableContainer component={Paper}>
                    <Table
                      sx={{ minWidth: 650 }}
                      aria-label="allowed txs table"
                    >
                      <TableHead>
                        <TableRow>
                          <TableCell align="center">
                            No Allowed Transactions Found
                          </TableCell>
                        </TableRow>
                      </TableHead>
                    </Table>
                  </TableContainer>
                </>
              )}
            </div>
            <br />
            {/* Set Allowed Token Transfer */}
            <div>
              <h2>Set Allowed Token Transfer</h2>
              <form
                onSubmit={(e: React.FormEvent<HTMLFormElement>) => {
                  e.preventDefault()
                  const formData: SetAllowedTokenTransferFormData = {
                    tokenAddress: (
                      e.currentTarget.elements.namedItem(
                        'tokenAddress'
                      ) as HTMLInputElement
                    ).value,
                    recipientAddress: (
                      e.currentTarget.elements.namedItem(
                        'recipientAddress'
                      ) as HTMLInputElement
                    ).value,
                    maxAmount: BigInt(
                      (
                        e.currentTarget.elements.namedItem(
                          'maxAmount'
                        ) as HTMLInputElement
                      ).value
                    ),
                    reset: false,
                  }
                  setAllowedTokenTransfer(formData)
                }}
              >
                <div
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: '10px',
                  }}
                >
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    variant="outlined"
                    type="text"
                    id="tokenAddress"
                    name="tokenAddress"
                    label="Token Address"
                    required
                  />
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    required
                    variant="outlined"
                    type="text"
                    id="recipientAddress"
                    name="recipientAddress"
                    label="Recipient Address"
                  />
                  <TextField
                    slotProps={{
                      inputLabel: { style: { color: '#fff' } },
                      input: { style: { color: '#fff' } },
                    }}
                    sx={{
                      '& .MuiOutlinedInput-root': {
                        '& fieldset': {
                          borderColor: '#fff',
                        },
                        '&:hover .MuiOutlinedInput-notchedOutline': {
                          borderColor: '#fff',
                          borderWidth: '0.15rem',
                        },
                      },
                    }}
                    variant="outlined"
                    type="text"
                    id="maxAmount"
                    name="maxAmount"
                    label="Max Amount"
                    required
                  />
                  <Button
                    variant="contained"
                    color="primary"
                    type="submit"
                    disabled={loading}
                  >
                    {loading ? 'Submitting...' : 'Set Allowed Token Transfer'}
                  </Button>
                </div>
              </form>
            </div>
            <br />
            {/* Current Allowed Token Transfers */}
            <div>
              {allowedTokenTransferInfo.length > 0 ? (
                <>
                  <h3>Showing current allowed token transfers</h3>
                  <TableContainer component={Paper}>
                    <Table
                      sx={{ minWidth: 650 }}
                      aria-label="allowed token transfers table"
                    >
                      <TableHead>
                        <TableRow>
                          <TableCell>Token Address</TableCell>
                          <TableCell>Recipient Address</TableCell>
                          <TableCell>Max Amount</TableCell>
                          <TableCell>Active</TableCell>
                          <TableCell></TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {allowedTokenTransferInfo.map(tx => (
                          <TableRow
                            key={tx.token + tx.recipient}
                            sx={{
                              '&:last-child td, &:last-child th': { border: 0 },
                            }}
                          >
                            <TableCell component="th" scope="row">
                              {tx.token}
                            </TableCell>
                            <TableCell>{tx.recipient}</TableCell>
                            <TableCell>{tx.maxAmount.toString()}</TableCell>
                            <TableCell>
                              {tx.allowedTimestamp < BigInt(Date.now())
                                ? 'Yes'
                                : 'Will be active at ' +
                                  new Date(
                                    Number(tx.allowedTimestamp)
                                  ).toLocaleString()}
                            </TableCell>
                            <TableCell align="right">
                              <Button
                                variant="contained"
                                color="error"
                                onClick={() => {
                                  setAllowedTokenTransfer({
                                    tokenAddress: tx.token,
                                    recipientAddress: tx.recipient,
                                    maxAmount: tx.maxAmount,
                                    reset: true,
                                  })
                                }}
                              >
                                Remove
                              </Button>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </TableContainer>
                  <p>
                    Allowed Token Transfers count:{' '}
                    {allowedTokenTransferInfo.length}
                  </p>
                </>
              ) : (
                <>
                  <h3>Showing current allowed token transfers</h3>
                  <TableContainer component={Paper}>
                    <Table
                      sx={{ minWidth: 650 }}
                      aria-label="allowed token transfers table"
                    >
                      <TableHead>
                        <TableRow>
                          <TableCell align="center">
                            No Allowed Transactions Found
                          </TableCell>
                        </TableRow>
                      </TableHead>
                    </Table>
                  </TableContainer>
                </>
              )}
            </div>
          </>
        )}
        {errorMessage ? <p className="error">{errorMessage}</p> : null}
      </div>
    </>
  )
}

export default App
