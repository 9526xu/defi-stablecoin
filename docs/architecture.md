```mermaid
graph TD
    subgraph User
        A[User Wallet]
    end

    subgraph DSC_Stablecoin_System
        B(DSCEngine)
        C(DecentralizedStableCoin - DSC)
        D{Price Oracle <br> (Chainlink)}
    end

    subgraph External_Contracts
        E[Collateral ERC20 <br> (e.g., WETH, WBTC)]
    end

    A -- 1. depositCollateralAndMintDsc(token, amount, dscToMint) --> B
    B -- 2. transferFrom(user, DSCEngine, amount) --> E
    B -- 3. staleCheckLatestRoundData() --> D
    B -- 4. mint(user, dscToMint) --> C
    C -- 5. _mint(user, dscToMint) --> A

    A -- 1. redeemCollateralForDsc(token, amount, dscToBurn) --> B
    B -- 2. transferFrom(user, DSCEngine, dscToBurn) --> C
    C -- 3. burn(dscToBurn) --> B
    B -- 4. transfer(user, amount) --> E

    subgraph Liquidation
        F[Liquidator Wallet]
    end

    F -- 1. liquidate(collateral, user, debtToCover) --> B
    B -- 2. _redeemCollateral(collateral, amount, user, liquidator) --> E
    B -- 3. _burnDsc(debtToCover, user, liquidator) --> C
```