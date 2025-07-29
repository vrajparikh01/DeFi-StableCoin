# DeFi‑StableCoin

## 🚀 Overview

A decentralized, over-collateralized stablecoin protocol built on Ethereum using Foundry. Users deposit allowed collateral (e.g., WETH, WBTC) to mint a USD‑pegged token (DSC). If collateral ratios drop, automated liquidation ensures solvency. The system is optimized for low‑gas usage and is designed to integrate with DeFi protocols for scalability.

## 🧩 Key Features
- **Collateralized minting:** Users lock crypto assets to mint DSC and maintain a safety buffer.
- **Automated liquidation:** Ensures system stability if collateral falls below thresholds.
- **Gas-efficient design:** Smart contract optimizations to reduce transaction costs.
- **Composable architecture:** Modular structure (DSC, DSCEngine, Oracle, etc.) for easy integration.
- **Full test coverage:** Includes unit tests and invariant/fuzz testing with Forge.

## ⚙️ Technical Components

### `DecentralizedStableCoin.sol`
- Implements the stablecoin token (DSC) as an ERC20 variant with mint & burn operations controlled by the engine.

### `DSCEngine.sol`
- Tracks collateral deposits per user
- Computes collateralization ratio based on live price data
- Allows minting DSC against collateral
- Executes liquidation if ratio breaches threshold

### `OracleLib.sol`
- Library for connecting to external oracles (e.g., Chainlink) to fetch asset prices securely.

### `Liquidation Mechanism`
- If user collateral value drops below the required ratio, any external actor can trigger liquidation—selling collateral to cover minted DSC.

### 📁 Installation

1. Clone the repository:
   ```
   git clone https://github.com/vrajparikh01/DeFi-Stablecoin.git
   ```

2. Navigate to the project directory:
   ```
   cd DeFi-Stablecoin
   ```

3. Install dependencies:
   ```
   forge install
   ```

### 🧪 Deployment and Testing
1. Deploy the Stablecoin contracts on Sepolia testnet using the following command:
   ```
   forge script script/DeployDSC.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
   ```
2. Tests include fuzzing, invariant checking, and unit tests:
   ```
   forge test
   ```

## 🧠 Smart‑Contract Design & Security
1. Over‑collateralization ensures DSC peg stability.
2. Reentrancy guards (e.g. nonReentrant) to block flash-loan style exploits.
3. Access control: Only DSCEngine can mint/burn DSC.
4. Fuzz testing & invariants: Protect against unexpected edge cases.
