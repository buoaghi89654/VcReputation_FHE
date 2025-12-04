# VcReputation_FHE

A privacy-first decentralized on-chain social reputation system, leveraging verifiable credentials (VCs) and fully homomorphic encryption (FHE). Users' reputations are composed of encrypted VCs, which can be aggregated and verified without exposing individual credentials. The system enables privacy-preserving, verifiable reputation scores while maintaining anonymity and trust in Web3 identities.

## Project Background

Traditional on-chain reputation systems often face critical privacy and trust challenges:

- **Exposure of sensitive credentials:** Users’ personal or professional achievements may be exposed to the public blockchain.  
- **Limited privacy-preserving computation:** Aggregating reputations typically requires decrypting sensitive data.  
- **Lack of verifiable anonymity:** Verifying a reputation often compromises user privacy.  

VcReputation_FHE addresses these challenges using FHE, enabling:

- Encrypted aggregation of VCs without decrypting them.  
- Privacy-preserving reputation computation across multiple sources.  
- Verifiable reputation proofs while keeping individual VCs confidential.  

## Features

### Core Functionality

- **VC Submission:** Users submit encrypted verifiable credentials securely.  
- **Reputation Calculation:** Aggregates encrypted VCs to compute reputation scores using FHE.  
- **Proof Generation:** Generates verifiable proofs of reputation without revealing underlying credentials.  
- **User Dashboard:** Displays encrypted reputation scores and aggregated metrics.  

### Privacy & Anonymity

- **Fully Encrypted Storage:** All VCs stored in encrypted form.  
- **FHE Computation:** Reputation calculations occur directly on encrypted data.  
- **Anonymous Proofs:** Users can prove reputation levels without revealing individual credentials.  
- **Immutable Records:** Encrypted VCs and computed reputations are stored immutably on-chain.  

### Advanced Analytics

- **Cross-Platform Aggregation:** Combines VCs from multiple sources while preserving privacy.  
- **Encrypted Scoring Models:** Supports configurable scoring rules applied over encrypted credentials.  
- **Historical Reputation Tracking:** Maintains encrypted history for auditing and analytics.  

## Architecture

### Smart Contracts

- **VcReputation.sol**  
  - Handles encrypted VC submissions.  
  - Stores reputation scores and proofs immutably.  
  - Facilitates privacy-preserving aggregation and verification.  

### Frontend Application

- **React + TypeScript:** Interactive dashboard and VC submission interface.  
- **Ethers.js:** Blockchain interaction for contract calls.  
- **Real-time Feedback:** Displays reputation updates as encrypted computations complete.  
- **User-Friendly UI:** Supports credential visualization and proof generation.  

## Technology Stack

### Blockchain

- **Solidity ^0.8.x:** Smart contract development.  
- **OpenZeppelin:** Secure contract libraries.  
- **Hardhat:** Testing and deployment framework.  

### Frontend

- **React 18 + TypeScript:** Responsive web interface.  
- **Ethers.js:** Blockchain communication.  
- **Tailwind CSS:** Styling and layout.  
- **Local FHE Engine:** Performs encrypted reputation computations in-browser.  

## Installation

### Prerequisites

- Node.js 18+  
- npm / yarn / pnpm package manager  
- Ethereum wallet (MetaMask, WalletConnect, etc.)  

### Setup

1. Clone the repository.  
2. Install dependencies: `npm install`  
3. Configure blockchain network and wallet.  
4. Deploy smart contracts.  
5. Start frontend server: `npm start`  

## Usage

- **Submit VCs:** Users can securely submit encrypted credentials.  
- **View Reputation:** Encrypted scores are displayed in the dashboard.  
- **Generate Proofs:** Users can produce verifiable reputation proofs without revealing underlying credentials.  
- **Audit & Analytics:** Administrators can compute encrypted metrics across all VCs.  

## Security Features

- **Encrypted Submission & Storage:** All credentials remain confidential.  
- **FHE Computation:** Scores calculated without decryption.  
- **Immutable Ledger:** Blockchain ensures tamper-proof records.  
- **Anonymous Proofs:** Users can validate reputation without exposing identity.  

## Future Enhancements

- Multi-chain deployment for decentralized identity ecosystems.  
- Enhanced scoring algorithms supporting weighted VCs.  
- Mobile-optimized interface for seamless cross-device access.  
- DAO-driven governance for reputation scoring policies.  
- Integration with additional Web3 DID and credential standards.  

Built with ❤️ for secure, private, and verifiable Web3 reputations.
