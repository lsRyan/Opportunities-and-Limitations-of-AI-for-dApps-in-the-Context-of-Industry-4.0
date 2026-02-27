# Role

You are a senior Ethereum smart contract developer responsible for implementing secure, efficient, well-documented Solidity contracts based on detailed specifications. Your work should follow industry-standard practices for structure, safety, and readability.

# Context

Your task is to develop a fully functional, well-commented, and secure Solidity-based decentralized application that implements a wallet and cryptocurrency exchange as described below. The code must:
* Be secure, avoiding vulnerabilities such as reentrancy, integer overflow/underflow, access control issues, and all known vulnerabilities that could affect the contract's functionalities.
* Be readable, using clear naming conventions, structured logic, and inline documentation (Solidity comments).
* Follow best practices for gas efficiency and modularity.
* Implement the proposed services in three different contracts, with every service only accessible through the wallet contract.
* Use the latest Solidity compiler version you are familiar with.

# Objective

Your task is to develop a fully functional and thoroughly commented smart contract that adheres to standard best practices in software engineering. The code must be well-documented, readable, and secure. Use the latest Solidity compiler version you are familiar with to ensure the implementation meets the application’s requirements.

# Application

## Overview

The smart contract must implement a complete wallet and exchange decentralized application within the Ethereum blockchain. Upon this application, users should be able to add currency to their balance, transfer funds to other accounts, and exchange their Ethers for other cryptocurrencies. Such decentralized applications will encompass three contracts: one that implements the wallet itself, an oracle contract that reads exchange rates between Ether and other currencies, and an exchange contract that effectively implements the cryptocurrency exchange. Currencies will be represented by symbols, which are three letters, such as "BTC" for "bitcoin". The oracle and exchange contracts will only be accessible by the wallet main contract. That is, users will not be able to access the functions in the other contracts directly, only through the main wallet contract.

## Contracts

### Oracle

#### Variables

* `struct oracle`: A struct containing:
  * `string maintainer`: The responsible company or institution.
  * `string url`: The URL associated with the oracle.
  * `address authorizedAddress`: The authorized address that can vote on exchange rates for this currency.
* `struct request`: A struct containing:
  * `string currency`: The requested currency symbol (e.g., "BTC").
  * `uint256 requestTime`: The timestamp when the request was created, stored as `block.timestamp`.
  * `uint256 quotation`: A running average of oracle answers for this request.
  * `mapping(address -> bool) answers`: A mapping from oracle addresses to booleans indicating whether a given oracle has already answered this request.
  * `uint256 answersCount`: The number of oracles that have answered the current request.
  * `bool active`: A boolean indicating whether the request is still active and requires further responses.
* `address public authorizedWallet`: The only authorized caller (contract address with administrative privileges).
* `mapping(string => bool) public currencies`: Maps currency symbols to its support status, either supported (`true`) or not (`false`).
* `mapping(string => oracle[]) public oracles`: Maps currency symbols to a list of oracles which support this currency.
* `mapping(uint256 => request) public requests`: Maps ids to their respective `request`.
* `mapping(string => uint256) public exchangeRates`: Maps currency symbols to their latest consolidated average exchange rate (ETH to currency).
* `mapping(string => uint256) public exchangeRateTime`: Maps currency symbols to the timestamp of the last update for their respective `exchangeRates`.
* `uint256 public minimumQuorum`: A percentage threshold that represents the minimum fraction of registered oracles required to finalize a reliable exchange rate. Default value is 70%.
* `uint256 internal currentId`: A counter tracking the latest request ID.

#### Functions

* `constructor(address _authorizedWallet)`
  * Set `authorizedWallet` as `_authorizedWallet`.

* `requestRate(string memory symbol) external returns (uint256)`
  * Check if:
    * `msg.sender` is `authorizedWallet`.
    * `symbol` is exactly three characters long.
    * `currencies[symbol]` is `true`.
  * Increment `currentId`.
  * Initialize `requests[currentId]` with:
    *  `requests[currentId].currency` as `symbol`.
    *  `requests[currentId].requestTime` as `block.timestamp`.
  * For each oracle in `oracles[symbol]`, emit an event containing:
    * `currentId`.
    * Oracle `url`.
    * Requested currency `symbol`.

* `answerRequest(uint256 id, uint256 exchangeRate) external`
  * Check if:
    * The provided `id` is valid.
    * `requests[id].active` is `true`.
    * `msg.sender` is in `oracles[requests[id].currency][index].authorizedAddress`, for `index` from 0 to `oracles[requests[id].currency].length`.
    * `requests[id].answers[msg.sender]` is `false`.
  * If `requests[id].requestTime` is smaller than `exchangeRateTime[requests[id].currency]`:
    * Set `requests[id].active` to `false` (the request is outdated).
  * Else:
    * Update the running average quotation using the formula: `requests[id].quotation` = (`requests[id].quotation` * `requests[id].answersCount` + `exchangeRate`) / (`requests[id].answersCount` + 1)
    * Increment `answersCount`.
    * Set `requests[id].answers[msg.sender]` to `true`.
    * If (`requests[id].answersCount` * `100`) / `oracles[requests[id].currency].length` is greater or equal than `minimumQuorum`:
      * Set `exchangeRates[requests[id].currency]` to `requests[id].quotation`
      * Set `exchangeRateTime[requests[id].currency]` to `block.timestamp`
      * Set `requests[id].active` to `false` (the request was fullfil).

* `readRate(string memory symbol) external view returns (uint256, uint256)`
  * Check if:
    * `symbol` is exactly three characters long.
    * `currencies[symbol]` is `true`.
  * Return values of `exchangeRates[symbol]` and `exchangeRateTime[symbol]`.

* `_addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external`
  * Check if:
    * `msg.sender` is `authorizedWallet`.
  * Add a new oracle entry to `oracles[symbol]` with the provided details (`maintainer`, `url`, and `accessAddress`).
  * If this is the first oracle for the symbol, that is, `currencies[symbol]` == `false`:
    * Set `currencies[symbol]` = `true`.

* `_removeOracle(string memory symbol, address accessAddress) external`
  * Check if:
    * `msg.sender` is `authorizedWallet`.
  * Remove the oracle entry matching `accessAddress` from `oracles[symbol]`.
  * If, after removal, no oracles for this `symbol` remain, that is, `oracles[symbol]`.length == 0:
    *  Set `currencies[symbol]` = `false`.

* `_changeMinimumQuorum(uint256 newQuorum) external`
  * Check if:
    * `msg.sender` is `authorizedWallet`.
  * Set `minimumQuorum` = `newQuorum`.

* `isSupported(string memory symbol) external view returns (bool)`
  * Check if:
    * The input `symbol` is exactly three characters long.
  * Return `currencies[symbol]`.

### Exchange

#### Variables

* `address authorizedWallet`: The only authorized caller (contract address with administrative privileges).
* `address oracleContract`: Address of the oracle address.
* `mapping(string => bool) public currencies`: Maps currency symbols to whether they are supported (`true`) or not (`false`).
* `string memory bridgeURL`: The url of the off-chain bridge.

#### Functions

* `constructor(address _authorizedWallet, address _oracleContract)`
  * Set `authorizedWallet` as `_authorizedWallet`.
  * Set `oracleContract` as `_oracleContract`. 

* `exchange(address transactor, string memory targetCurrency, address targetAddress, uint256 maximumRateDelay) external payable`
  * Check if:
    * `msg.sender` is `authorizedWallet`.
    * `targetCurrency` is exactly three characters long.
    * `currencies[targetCurrency]` is `true`.
    * `targetAddress` is not address(0x0).
    * The value returned from calling `isSupported(targetCurrency)` from `oracleContract` is `true`.
    * `msg.value` is greater than 0.

  * Set `exchangeRate` and `exchangeRateTime` as the return values from the call to `readRate(targetCurrency)` from `oracleContract`.
  * If `block.timestamp` minus `exchangeRateTime` is greater than the `maximumRateDelay`:
    * Inform the user that he needs to request a new rate for his target currency and try again.
    * Revert transaction.
  * Else:
    * Emit an event with:
      * The transactor (`transactor`)
      * The target currency (`targetCurrency`)
      * The exchange value (`msg.value`)
      * The exchange rate (`exchangeRate`)
      * Current time (`block.timestamp`)
      * Bridge call (`string.concat(bridgeURL, targetCurrency)`)

* `_updateBridge(string memory newBridgeURL) external`:
  * Check if:
    * `msg.sender` is `authorizedWallet`.
  * Set `bridgeURL` to `newBridgeURL`.

* `_addCurrency(string memory symbol) external`
  * Check if:
    * `msg.sender` is `authorizedWallet`
    * `symbol` is exactly three characters long.
  * Set `currencies[symbol]` to `true`.

* `_removeCurrency(string memory symbol) external`
  * Check if:
    * `msg.sender` is `authorizedWallet`
    * `symbol` is exactly three characters long.
  * Set `currencies[symbol]` to `false`.

* `isSupported(string memory symbol) external view returns (bool)`
  * Check if:
    * `symbol` is exactly three characters long.
  * Return `currencies[symbol]`.

### Wallet

#### Variables

* `address public owner`: Contract owner address.
* `address public oracleContract`: Oracle contract address.
* `address public exchangeContract`: Exchange contract address.
* `mapping(address => uint256) private balances`: A mapping of users and their current balances.
* `mapping(address => mapping(address => string)) private authorizedAccounts`: Maps users to other accounts' their authorization levels, which can be:
  * "": No authorization (default).
  * "basic": Can only withdraw funds.
  * "onchain": "basic" privileges plus the ability to send funds to other accounts.
  * "all": "onchain" privileges plus the ability exchange currency.
* `uint256 public maximumRateDelay`: The maximum acceptable delay for an oracle exchange rate to be considered up to date.
* `uint256 public exchangeFee`: The fee to use the contract's currency exchange service.

#### Functions

* `constructor(uint256 _maximumRateDelay, uint256 _exchangeFee)`
  * Set `owner` as `msg.sender`.
  * Set `maximumRateDelay` as `_maximumRateDelay`.
  * Set `exchangeFee` as `_exchangeFee`.

* `deposit() external payable`
  * Add `msg.value` to `balances[msg.sender]`.

* `transfer(uint256 amount, address to) external`
  * Check if:
    * `balances[msg.sender]` is greater or equal than `amount`.
  * Decrement `balances[msg.sender]` by `amount`.
  * Increment `balances[to]` by `amount`.

* `externalTransfer(uint256 amount, address to) external payable`
  * Check if:
    * `balances[msg.sender]` is greater or equal than `amount`.
  * Decrement `balances[msg.sender]` by `amount`.
  * Transfer `amount` to `to`.

* `exchange(string memory targetCurrency, address targetAddress, uint256 amount) external payable`
  * Check if:
    * `balances[msg.sender]` is greater or equal than `amount`.
    * The call to `isSupported(targetCurrency)` from `exchangeContract` returns `true`.
  * Decrement `balances[msg.sender]` by `amount`.
  * Calculate  `fee` as `amount` * `exchangeFee` / 100.
  * Increment `balances[owner]` by `fee`.
  * Call `exchange(msg.sender, targetCurrency, targetAddress, maximumRateDelay)` with a value of (`amount` - `fee`) from `exchangeContract`.

* `withdrawn(uint256 amount) external payable`
  * Check if:
    * `balances[msg.sender]` is greater or equal than `amount`.
  * Decrement `balances[msg.sender]` by `amount`.
  * Send `amount` to `msg.sender`.

* `transferAUTH(uint256 amount, address from, address to) external`
  * Check if:
    * `authorizedAccounts[from][msg.sender]` is `onchain` or `all`.
    * `balances[from]` is greater or equal than `amount`.
  * Send funds to the target address' balance. That is:
    * Decrement `balances[from]` by `amount`.
    * Increment `balances[to]` by `amount`.

* `externalTransferAUTH(uint256 amount, address from, address to) external payable`
  * Check if:
    * `authorizedAccounts[from][msg.sender]` is `onchain` or `all`.
    * `balances[from]` is greater or equal than `amount`.
  * Send funds directly to the target address. That is:
    * Decrement `balances[from]` by `amount`.
    * Transfer `amount` to `to`.

* `exchangeAUTH(string memory targetCurrency, address from, address targetAddress, uint256 amount) external payable`
  * Check if:
    * `authorizedAccounts[from][msg.sender]` is `all`.
    * `balances[from]` is greater or equal than `amount`.
    * The selected currency is available for exchange. To verify that call `isSupported(targetCurrency)` in the exchange contract (`exchangeContract`).
  * Decrement `balances[from]` by `amount`.
  * Set  `fee` as `amount` * `exchangeFee` / 100.
  * Increment `balances[owner]` by `fee`.
  * Call `exchange(from, targetCurrency, targetAddress, maximumRateDelay)` with a value of (`amount` - `fee`) from `exchangeContract`.

* `withdrawnAUTH(address from, uint256 amount) external payable`
  * Check if:
    * `authorizedAccounts[from][msg.sender]` is `basic`, `onchain` or `all`.
    * `balances[from]` is greater or equal than `amount`.
  * Decrement `balances[from]` by `amount`.
  * Send funds to the `msg.sender` address.

* `authorize(address authorized, string memory tier) external`
  * Check if:
    * The selected `tier` is valid.
  * Set `authorizedAccounts[msg.sender][authorized]` to `tier`.
  
* `revoke(address unauthorize) external`
  * Set`authorizedAccounts[msg.sender][unauthorize]` = `""`.

* `getExchangeAvailability(string memory symbol) external view returns (bool)`
  * Return the call to `isSupported(symbol)` from `exchangeContract`.

* `getOracleAvailability(string memory symbol) external view returns (bool)`
  * Return the call to `isSupported(symbol)` from `oracleContract`.

* `getExchangeRate(string memory symbol) external view returns (uint256, uint256)`
  * Return the call to `readRate(symbol)` from `oracleContract`.

* `requestExchangeRate(string memory symbol) external`
  * Call `requestRate(symbol)` from `oracleContract`.

* `addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Call `_addOracle(symbol, maintainer, url, accessAddress)` from `oracleContract`.

* `removeOracle(string memory symbol, address accessAddress) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Call `_removeOracle(string memory symbol, address accessAddress)` =from `oracleContract`.

* `changeMinimumQuorum(uint256 newQuorum) external`
  * Check if:
    * `msg.sender` is `owner`.
  * If `newQuorum` >= 0 and `newQuorum` <= 100 and  (i.e., the percentage threshold is valid).
    * Call `_changeMinimumQuorum(uint256 newQuorum)` from `oracleContract`.

* `updateBridge(string memory newBridgeURL) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Call `_updateBridge(string memory newBridgeURL)` from `exchangeContract`.

* `addCurrency(string memory symbol) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Call `_addCurrency(string memory symbol)` from `exchangeContract`.

* `removeCurrency(string memory symbol) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Call `_removeCurrency(string memory symbol)` from `exchangeContract`.

* `updateOracleAddress(address newOracle) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Set `oracleContract` to `newOracle`.
  
* `updateExchangeAddress(address newExchange) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Set `exchangeContract` to `newExchange`.
  
* `updateMaximumRateDelay(uint256 newMaximumRateDelay) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Set `maximumRateDelay` to `newMaximumRateDelay`.

* `updateExchangeFee(uint256 newExchangeFee) external`
  * Check if:
    * `msg.sender` is `owner`.
  * If `newExchangeFee` >= 0 and `newExchangeFee` <= 100 and  (i.e., the percentage threshold is valid).
    * Set `exchangeFee` to `newExchangeFee`.

* `changeOwnership(address newOwner) external`
  * Check if:
    * `msg.sender` is `owner`.
  * Set `owner` to `newOwner`.

# Response Format

Your response should be a fully implemented Solidity contract that includes all the functionalities described above. Remember that your implementation must be complete, secure, well-documented, and structured with best practices in mind. No additional text or explanation is required — just the code.
