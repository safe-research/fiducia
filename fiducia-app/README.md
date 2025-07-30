# Fiducia App

A React-based Safe app for managing the Fiducia protocol - a transaction guard and security framework for Safe wallets.

## Overview

Fiducia is a security layer for Safe wallets that allows users to:

- Set up transaction guards with time-delayed activation
- Configure allowed transactions and token transfers
- Establish cosigners for additional security
- Schedule guard removal with time delays

## Features

- **Transaction Guards**: Configure which transactions are allowed
- **Token Transfer Controls**: Set limits on token transfers to specific recipients
- **Cosigner Management**: Add additional signers for transactions
- **Time-Delayed Activation**: All security changes have time delays before becoming active
- **Guard Removal**: Securely remove guards with time delays

## Supported Networks

- **Sepolia Testnet** (Chain ID: 11155111)
- **Gnosis Chain** (Chain ID: 100)

## Development

### Prerequisites

- Node.js 18+
- npm or yarn

### Setup

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Run linting
npm run lint

# Format code
npm run format
```

## Usage

1. Connect your Safe wallet to the app
2. Activate Fiducia guard on your Safe
3. Configure allowed transactions and token transfers
4. Set up cosigners if needed
5. Manage guard settings as needed

## Smart Contract Integration

The app interacts with Fiducia smart contracts deployed on supported networks. Contract addresses and ABIs are defined in `src/constants.ts`.
