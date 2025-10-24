# Product Requirements Document (PRD): Decentralized Stablecoin (DSC)

## 1. Project Overview

### 1.1. Introduction

This document outlines the product requirements for the Decentralized Stablecoin (DSC), a crypto-collateralized stablecoin pegged to the US Dollar. The system is designed to be minimal, decentralized, and algorithmically stable, ensuring that the value of all collateral always exceeds the value of all outstanding DSC.

### 1.2. Goals and Objectives

- **Stability:** Maintain a 1:1 peg with the US Dollar.
- **Decentralization:** Operate without a central governing body.
- **Security:** Ensure the system is robust against economic attacks and smart contract vulnerabilities.
- **Transparency:** All operations and system health metrics should be publicly verifiable on the blockchain.

## 2. Functional Requirements

### 2.1. Core Modules

- **`DecentralizedStableCoin.sol` (DSC Token):** An ERC20 token contract representing the stablecoin.
- **`DSCEngine.sol` (Core Logic):** The main contract that manages collateral, minting, burning, and liquidations.

### 2.2. User Stories

- **As a user, I want to deposit collateral and mint DSC so that I can leverage my crypto assets.**
- **As a user, I want to redeem my collateral by burning DSC so that I can exit my position.**
- **As a liquidator, I want to liquidate undercollateralized positions to earn a bonus and help maintain system stability.**

### 2.3. Detailed Functionality

#### 2.3.1. `DSCEngine.sol`

- **Collateral Management:**
    - `depositCollateral(token, amount)`: Allows users to deposit supported ERC20 tokens as collateral.
    - `redeemCollateral(token, amount)`: Allows users to withdraw their collateral.
- **Minting and Burning:**
    - `mintDsc(amount)`: Mints a specified amount of DSC for the user.
    - `burnDsc(amount)`: Burns a specified amount of DSC from the user's balance.
- **Combined Operations:**
    - `depositCollateralAndMintDsc(token, collateralAmount, dscAmount)`: A convenience function to deposit collateral and mint DSC in a single transaction.
    - `redeemCollateralForDsc(token, collateralAmount, dscAmount)`: A convenience function to burn DSC and redeem collateral in a single transaction.
- **Liquidation:**
    - `liquidate(collateral, user, debtToCover)`: Allows a liquidator to repay a user's debt and claim their collateral at a discount.

#### 2.3.2. `DecentralizedStableCoin.sol`

- **`mint(to, amount)`:** Mints new DSC tokens. Restricted to be called only by the `DSCEngine`.
- **`burn(amount)`:** Burns DSC tokens. Restricted to be called only by the `DSCEngine`.

### 2.4. Core Concepts

#### 2.4.1. Health Factor

The Health Factor is a critical metric representing the safety of a user's position (i.e., their deposited collateral against their minted DSC debt). A Health Factor below 1.0 indicates that a position is undercollateralized and eligible for liquidation.

*   **Calculation Formula:**
    The Health Factor is calculated as follows:
    ```
    Health Factor = (Total Collateral Value in USD * Liquidation Threshold) / Total DSC Minted Value
    ```
    - `Total Collateral Value in USD`: The sum of the USD value of all collateral deposited by the user, determined by the Chainlink price oracles.
    - `Liquidation Threshold`: A system-wide parameter (set to 50% in the contract) that determines the collateralization ratio. For example, a 50% threshold means the collateral value must be at least 200% of the debt value to be considered safe.
    - `Total DSC Minted Value`: The total amount of DSC the user has minted.

*   **Risk Tiers:**
    - **Safe (Health Factor >= 1.5):** The position is well-collateralized.
    - **Moderate (1.0 < Health Factor < 1.5):** The position is approaching the liquidation threshold. Users should consider adding more collateral or burning DSC.
    - **Unsafe (Health Factor <= 1.0):** The position is undercollateralized and at high risk of liquidation. The `MIN_HEALTH_FACTOR` is set to `1e18` (or 1.0), and any action that would result in the health factor dropping below this value will be reverted.

*   **Monitoring and Alerts:**
    While the smart contract itself does not implement off-chain alerts, a robust monitoring system should be built on top of the protocol. This system would track the Health Factor of all user positions and trigger alerts (e.g., email, push notifications) when a user's Health Factor drops into the "Moderate" or "Unsafe" tiers.

*   **Improving Health Factor:**
    Users can improve their Health Factor by:
    1.  **Depositing more collateral:** Calling `depositCollateral()` to increase the `Total Collateral Value in USD`.
    2.  **Burning DSC:** Calling `burnDsc()` to decrease the `Total DSC Minted Value`.

#### 2.4.2. Liquidation Mechanism

Liquidation is the process of selling an undercollateralized user's collateral to repay their debt, thereby ensuring the solvency of the entire system.

*   **Trigger Condition:**
    A position becomes eligible for liquidation when its Health Factor drops below the `MIN_HEALTH_FACTOR` (1.0).

*   **Liquidation Process:**
    1.  Any user (a "liquidator") can initiate the liquidation of an unsafe position by calling the `liquidate(collateral, user, debtToCover)` function.
    2.  The liquidator specifies the undercollateralized `user`, the `collateral` token they wish to receive, and the amount of DSC debt they want to `debtToCover`.
    3.  The liquidator burns their own DSC to cover the specified debt amount on behalf of the undercollateralized user.
    4.  In return, the liquidator receives a portion of the user's collateral.

*   **Collateral Calculation & Penalty:**
    The liquidator receives the user's collateral equivalent to the debt covered, plus a bonus. This bonus acts as an incentive for liquidators and a penalty for the liquidated user.
    - **Collateral Seized:** `(Token Amount for Debt Covered) + (Liquidation Bonus)`
    - **Liquidation Bonus:** A system parameter (`LIQUIDATION_BONUS` = 10%) applied to the value of the seized collateral. This means the liquidator acquires the collateral at a 10% discount compared to the market price provided by the oracle.

*   **Exception Handling:**
    - The system ensures that a liquidation event must improve the health factor of the liquidated user. If it does not, the transaction reverts.
    - A known limitation is that if the protocol's total collateralization drops too quickly (e.g., below 100%), the liquidation mechanism may not be sufficient to restore solvency, as there would be no bonus to incentivize liquidators.

## 3. Non-Functional Requirements

- **Security:** The system must be protected against reentrancy attacks and other common smart contract vulnerabilities.
- **Reliability:** The system must function correctly and consistently, with high uptime.
- **Performance:** Transactions should be processed efficiently to minimize gas costs.
- **Scalability:** The system should be designed to handle a growing number of users and transactions.

## 4. System Architecture

*For a visual representation of the system architecture, please refer to the Mermaid diagram in `learn/architecture.md`.*

## 5. Data Model

### `DSCEngine.sol` State Variables

- `s_priceFeeds`: `mapping(address => address)` - Maps collateral token addresses to their Chainlink price feed addresses.
- `s_collateralDeposited`: `mapping(address => mapping(address => uint256))` - Maps users to their deposited collateral balances for each token.
- `s_DSCMinted`: `mapping(address => uint256)` - Maps users to the amount of DSC they have minted.
- `s_collateralTokens`: `address[]` - An array of supported collateral token addresses.

### `DecentralizedStableCoin.sol` State Variables

- Inherits standard ERC20 state variables (e.g., `balances`, `allowances`).

## 6. User Flows

*User flows are described in detail in the Technical Analysis section and visualized in the Mermaid diagram.*

## 7. Interface Specifications (API)

### `DSCEngine.sol` Public/External Functions

- `depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)`
- `redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)`
- `redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)`
- `burnDsc(uint256 amount)`
- `liquidate(address collateral, address user, uint256 debtToCover)`
- `mintDsc(uint256 amountDscToMint)`
- `depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)`

### `DecentralizedStableCoin.sol` Public/External Functions

- `mint(address _to, uint256 _amount)`
- `burn(uint256 _amount)`