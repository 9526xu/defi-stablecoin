# 产品需求文档 (PRD):去中心化稳定币 (DSC)

## 1. 项目概述

### 1.1. 简介

本文档概述了去中心化稳定币 (DSC) 的产品需求，这是一种与美元挂钩的加密抵押稳定币。该系统旨在实现最小化、去中心化和算法稳定，确保所有抵押品的价值始终超过所有流通中的DSC的价值。

### 1.2. 目标与目的

- **稳定性:** 与美元保持1:1的挂钩。
- **去中心化:** 在没有中央管理机构的情况下运作。
- **安全性:** 确保系统能够抵御经济攻击和智能合约漏洞。
- **透明度:** 所有操作和系统健康指标都应在区块链上公开可验证。

## 2. 功能需求

### 2.1. 核心模块

- **`DecentralizedStableCoin.sol` (DSC代币):** 代表稳定币的ERC20代币合约。
- **`DSCEngine.sol` (核心逻辑):** 管理抵押品、铸造、销毁和清算的主要合约。

### 2.2. 用户故事

- **作为用户，我希望存入抵押品并铸造DSC，以便利用我的加密资产。**
- **作为用户，我希望通过销毁DSC来赎回我的抵押品，以便退出我的头寸。**
- **作为清算人，我希望清算抵押不足的头寸以赚取奖金，并帮助维持系统稳定。**

### 2.3. 详细功能

#### 2.3.1. `DSCEngine.sol`

- **抵押品管理:**
    - `depositCollateral(token, amount)`: 允许用户存入支持的ERC20代币作为抵押品。
    - `redeemCollateral(token, amount)`: 允许用户提取其抵押品。
- **铸造和销毁:**
    - `mintDsc(amount)`: 为用户铸造指定数量的DSC。
    - `burnDsc(amount)`: 从用户余额中销毁指定数量的DSC。
- **组合操作:**
    - `depositCollateralAndMintDsc(token, collateralAmount, dscAmount)`: 在单笔交易中存入抵押品和铸造DSC的便捷功能。
    - `redeemCollateralForDsc(token, collateralAmount, dscAmount)`: 在单笔交易中销毁DSC和赎回抵押品的便捷功能。
- **清算:**
    - `liquidate(collateral, user, debtToCover)`: 允许清算人偿还用户的债务并以折扣价索取其抵押品。

#### 2.3.2. `DecentralizedStableCoin.sol`

- **`mint(to, amount)`:** 铸造新的DSC代币。仅限`DSCEngine`调用。
- **`burn(amount)`:** 销毁DSC代币。仅限`DSCEngine`调用。

### 2.4. 核心概念

#### 2.4.1. 健康因子

健康因子是代表用户头寸安全性的关键指标（即他们存入的抵押品与其铸造的DSC债务的对比）。健康因子低于1.0表示头寸抵押不足，有资格被清算。

*   **计算公式:**
    健康因子计算如下：
    ```
    健康因子 = (总抵押品价值（美元） * 清算阈值) / 总DSC铸造价值
    ```
    - `总抵押品价值（美元）`: 用户存入的所有抵押品的美元价值总和，由Chainlink价格预言机确定。
    - `清算阈值`: 一个全系统参数（在合约中设置为50%），用于确定抵押率。例如，50%的阈值意味着抵押品价值必须至少是债务价值的200%才被认为是安全的。
    - `总DSC铸造价值`: 用户铸造的DSC总额。

*   **风险等级:**
    - **安全 (健康因子 >= 1.5):** 头寸抵押充足。
    - **中等 (1.0 < 健康因子 < 1.5):** 头寸正在接近清算阈值。用户应考虑增加更多抵押品或销毁DSC。
    - **不安全 (健康因子 <= 1.0):** 头寸抵押不足，面临很高的清算风险。`MIN_HEALTH_FACTOR` 设置为 `1e18` (即1.0)，任何会导致健康因子降至此值以下的操作都将被回滚。

*   **监控与警报:**
    虽然智能合约本身不实现链下警报，但应在协议之上构建一个强大的监控系统。该系统将跟踪所有用户头寸的健康因子，并在用户的健康因子降至“中等”或“不安全”等级时触发警报（例如，电子邮件、推送通知）。

*   **改善健康因子:**
    用户可以通过以下方式改善其健康因子：
    1.  **存入更多抵押品:** 调用 `depositCollateral()` 以增加 `总抵押品价值（美元）`。
    2.  **销毁DSC:** 调用 `burnDsc()` 以减少 `总DSC铸造价值`。

#### 2.4.2. 清算机制

清算是指出售抵押不足用户的抵押品以偿还其债务的过程，从而确保整个系统的偿付能力。

*   **触发条件:**
    当头寸的健康因子降至 `MIN_HEALTH_FACTOR` (1.0) 以下时，该头寸即有资格被清算。

*   **清算流程:**
    1.  任何用户（“清算人”）都可以通过调用 `liquidate(collateral, user, debtToCover)` 函数来启动对不安全头寸的清算。
    2.  清算人指定抵押不足的 `user`、他们希望收到的 `collateral` 代币以及他们想要 `debtToCover` 的DSC债务金额。
    3.  清算人销毁自己的DSC，以代表抵押不足的用户偿还指定的债务金额。
    4.  作为回报，清算人将获得用户的一部分抵押品。

*   **抵押品计算与罚金:**
    清算人收到与所偿还债务等值的用户抵押品，外加一笔奖金。这笔奖金既是给清算人的激励，也是对被清算用户的惩罚。
    - **没收的抵押品:** `(偿还债务的代币数量) + (清算奖金)`
    - **清算奖金:** 一个系统参数 (`LIQUIDATION_BONUS` = 10%)，适用于被没收抵押品的价值。这意味着清算人以比预言机提供的市场价格低10%的折扣获得抵押品。

*   **异常处理:**
    - 系统确保清算事件必须改善被清算用户的健康因子。如果不能，则交易回滚。
    - 一个已知的局限是，如果协议的总抵押率下降过快（例如，低于100%），清算机制可能不足以恢复偿付能力，因为将没有奖金来激励清算人。

## 3. 非功能性需求

- **安全性:** 系统必须能够抵御重入攻击和其他常见的智能合约漏洞。
- **可靠性:** 系统必须正确、一致地运行，并具有高正常运行时间。
- **性能:** 交易应高效处理，以最大限度地降低Gas成本。
- **可扩展性:** 系统设计应能处理不断增长的用户和交易数量。

## 4. 系统架构

*有关系统架构的可视化表示，请参阅 `learn/architecture.md` 中的Mermaid图。*

## 5. 数据模型

### `DSCEngine.sol` 状态变量

- `s_priceFeeds`: `mapping(address => address)` - 将抵押品代币地址映射到其Chainlink价格预言机地址。
- `s_collateralDeposited`: `mapping(address => mapping(address => uint256))` - 将用户映射到他们为每个代币存入的抵押品余额。
- `s_DSCMinted`: `mapping(address => uint256)` - 将用户映射到他们已铸造的DSC数量。
- `s_collateralTokens`: `address[]` - 支持的抵押品代币地址数组。

### `DecentralizedStableCoin.sol` 状态变量

- 继承标准的ERC20状态变量 (例如, `balances`, `allowances`)。

## 6. 用户流程

*用户流程在技术分析部分有详细描述，并在Mermaid图中有可视化展示。*

## 7. 接口规范 (API)

### `DSCEngine.sol` 公共/外部函数

- `depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)`
- `redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)`
- `redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)`
- `burnDsc(uint256 amount)`
- `liquidate(address collateral, address user, uint256 debtToCover)`
- `mintDsc(uint256 amountDscToMint)`
- `depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)`

### `DecentralizedStableCoin.sol` 公共/外部函数

- `mint(address _to, uint256 _amount)`
- `burn(uint256 _amount)`