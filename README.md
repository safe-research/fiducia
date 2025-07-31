# Fiducia

> [!WARNING]  
> Code in this repository is not audited and may contain serious security holes. Use at your own risk.

![Fiducia](./fiducia-app/public/fiducia.svg)

Fiducia is a comprehensive Safe transaction guard that adds enhanced security controls through time delays and cosigner requirements. It enforces stricter transaction validation while providing flexible permission management for Safe multisig wallets.

## Features

### 🔐 Core Security Features
- **Time-Delayed Transactions**: Delay for new transaction types
- **Cosigner Support**: Allow immediate execution with valid cosigner signatures
- **Token Transfer Controls**: Granular limits for ERC20 token transfers
- **Guard Removal Protection**: Secure process for disabling the guard

### ⚙️ Transaction Management
- **Allowlist System**: Pre-approve transaction patterns for immediate execution
- **Module Integration**: Support for Safe module transactions
- **Multisend Support**: Handle complex batched operations
- **Event Logging**: Comprehensive event emission for transparency

## Architecture

Fiducia implements both `ITransactionGuard` and `IModuleGuard` interfaces to provide comprehensive transaction monitoring for Safe wallets.

### Key Components

1. **Guard Setup**: Must be set as both transaction guard and module guard
2. **Transaction Validation**: Pre-execution checks with allowlist/delay logic  
3. **State Management**: Post-execution validation and guard integrity checks

## Usage

### Installation

```shell
git clone --recurse-submodules https://github.com/safe-research/fiducia.git
cd fiducia
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
# Set deployment parameters in script/Fiducia.s.sol
forge script script/Fiducia.s.sol --broadcast --rpc-url <RPC_URL>
```

## Integration Guide

### 1. Deploy Fiducia

```solidity
// Deploy with 24-hour delay
Fiducia guard = new Fiducia(86400); // 1 day in seconds
```

### 2. Setup Guard on Safe

```solidity
// Setup guard on your Safe (requires Safe owner signatures)
safe.setGuard(address(guard));
safe.setModuleGuard(address(guard)); 
```

### 3. Configure Permissions

```solidity
// Allow immediate token transfers up to 1000 tokens
guard.setAllowedTokenTransfer(tokenAddress, recipient, 1000e18);

// Set cosigner for immediate execution
guard.setCosigner(cosignerAddress);

// Allow specific transaction types
guard.setAllowedTx(targetContract, selector, Enum.Operation.Call);
```

### 4. Execute Transactions

```solidity
// With cosigner signature (immediate)
safe.execTransaction(to, value, data, operation, 0, 0, 0, address(0), payable(0), 
    abi.encodePacked(ownerSig, cosignerSig));

// Standard transaction (respects delay/allowlist)
safe.execTransaction(to, value, data, operation, 0, 0, 0, address(0), payable(0), ownerSig);
```

## Error Reference

| Error | Description |
|-------|-------------|
| `FirstTimeTx()` | Transaction not in allowlist and no valid cosigner |
| `InvalidTimestamp()` | Guard Removal Transaction attempted before delay |
| `TokenTransferNotAllowed()` | Token transfer not pre-approved |
| `TokenTransferExceedsLimit()` | Transfer amount exceeds configured limit |
| `InvalidSelector()` | Invalid function selector in transaction data |
| `ImproperGuardSetup()` | Guard configuration is inconsistent |

## ⚠️ Security Considerations

### Risk Assessment

- **Guard Removal**: Improper guard removal can lock the Safe permanently
- **Cosigner Compromise**: Cosigner keys bypass all delays - secure with HSM/hardware wallet
- **Delay Too Short**: Insufficient time to detect and respond to malicious transactions

#### Cosigner Security
- Use dedicated hardware wallet
- Rotate keys periodically  
- Monitor cosigner usage

#### Permission Management
- Start with restrictive settings
- Gradually expand as needed
- Regular permission audits

## Development

### Format Code

```shell
forge fmt
```

### Generate Gas Reports

```shell
forge snapshot
```

### Run Specific Tests

```shell
forge test --match-test test_GuardSetup -vv
```
## Frequently Asked Questions

### General Questions

#### Q: What happens if I lose the cosigner private key?
**A:** You can still execute transactions by waiting for the delay period. Update the cosigner address using `setCosigner()` to set a new cosigner or disable cosigning by setting it to `address(0)`.

#### Q: Can the guard prevent me from accessing my Safe?
**A:** No. You can always schedule guard removal using `scheduleGuardRemoval()` and remove the guard after the delay period expires.

### Technical Questions

#### Q: Why do my transactions fail with "Transaction not allowed"?
**A:** Check if:
1. Transaction matches an allowed pattern (`getAllowedTx()`)
2. Token transfer is within limits (`getAllowedTokenTransfer()`)  
3. Delay period has passed for non-cosigned transactions
4. Cosigner signature is valid (if required)

#### Q: How do I handle ERC20 token transfers?
**A:** Use `setAllowedTokenTransfer()` to set per-token limits. The guard automatically detects ERC20 `transfer()` calls.

#### Q: Can I batch multiple operations?
**A:** Yes, use MultiSendCallOnly and allow each transaction in the batch calldata pattern with `setAllowedTx()`.

#### Q: What contracts can I interact with safely?
**A:** Only contracts with allowed transaction patterns. Start restrictive and gradually expand based on your needs.

### Security Questions

#### Q: What if there's a bug in the guard contract?
**A:** The guard can be removed using `scheduleGuardRemoval()`.

#### Q: How do I monitor guard activity?
**A:** Listen for events:
- `TransactionAllowed`: Successful transactions
- `CosignerSet`: Cosigner changes
- `GuardRemovalScheduled`: Guard removal initiated

#### Q: Can the guard be bypassed?
**A:** No, except through:
1. Valid cosigner signatures (if enabled)
2. Waiting for delay periods
3. Following allowed transaction patterns

## Improvements

- Support for `ERC20.transferFrom`
- Can have limit of tokens which can be transferred within a timeframe.
