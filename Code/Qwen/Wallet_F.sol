// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File Qwen/Wallet_C.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Oracle Contract
 * @dev Manages exchange rates for various currencies through oracles
 */
contract Oracle {
    /**
     * @dev Struct representing an oracle for a specific currency
     */
    struct OracleInfo {
        string maintainer;
        string url;
        address authorizedAddress;
    }

    /**
     * @dev Struct representing a request for exchange rate
     */
    struct Request {
        string currency;
        uint256 requestTime;
        uint256 quotation;
        mapping(address => bool) answers;
        uint256 answersCount;
        bool active;
    }

    // Only authorized wallet can call certain functions
    address public authorizedWallet;

    // Mapping of currency symbols to their support status
    mapping(string => bool) public currencies;

    // Mapping of currency symbols to array of oracles
    mapping(string => OracleInfo[]) public oracles;

    // Mapping of request IDs to request structs
    mapping(uint256 => Request) public requests;

    // Latest exchange rates for currencies
    mapping(string => uint256) public exchangeRates;

    // Timestamps of last updates for exchange rates
    mapping(string => uint256) public exchangeRateTime;

    // Minimum quorum percentage for finalizing exchange rates
    uint256 public minimumQuorum = 70;

    // Current request ID counter
    uint256 internal currentId;

    /**
     * @dev Emitted when a new rate request is made
     */
    event RateRequest(uint256 indexed requestId, string url, string currency);

    /**
     * @dev Constructor to set the authorized wallet address
     * @param _authorizedWallet The address authorized to make calls
     */
    constructor(address _authorizedWallet) {
        authorizedWallet = _authorizedWallet;
    }

    /**
     * @dev Request a rate for a specific currency
     * @param symbol The currency symbol to request rate for
     * @return The request ID
     */
    function requestRate(string memory symbol) external returns (uint256) {
        require(msg.sender == authorizedWallet, "Only authorized wallet can request rates");
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        require(currencies[symbol], "Currency not supported");

        currentId++;
        requests[currentId].currency = symbol;
        requests[currentId].requestTime = block.timestamp;
        requests[currentId].active = true;

        // Emit events for each oracle to provide the rate
        OracleInfo[] storage oracleList = oracles[symbol];
        for (uint256 i = 0; i < oracleList.length; i++) {
            emit RateRequest(currentId, oracleList[i].url, symbol);
        }

        return currentId;
    }

    /**
     * @dev Allow an oracle to answer a request with an exchange rate
     * @param id The request ID
     * @param exchangeRate The exchange rate provided by the oracle
     */
    function answerRequest(uint256 id, uint256 exchangeRate) external {
        require(id > 0 && id <= currentId, "Invalid request ID");
        require(requests[id].active, "Request is not active");
        
        // Check if sender is authorized for this currency
        bool isAuthorized = false;
        OracleInfo[] storage oracleList = oracles[requests[id].currency];
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i].authorizedAddress == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Not authorized to answer this request");
        
        require(!requests[id].answers[msg.sender], "Already answered this request");

        // If the request is outdated compared to the latest exchange rate time
        if (requests[id].requestTime < exchangeRateTime[requests[id].currency]) {
            requests[id].active = false;
            return;
        }

        // Update the running average
        uint256 oldQuotation = requests[id].quotation;
        uint256 oldAnswersCount = requests[id].answersCount;
        
        if (oldAnswersCount == 0) {
            requests[id].quotation = exchangeRate;
        } else {
            // Calculate new average: (oldAvg * oldCount + newRate) / (oldCount + 1)
            requests[id].quotation = (oldQuotation * oldAnswersCount + exchangeRate) / (oldAnswersCount + 1);
        }
        
        requests[id].answersCount++;
        requests[id].answers[msg.sender] = true;

        // Check if we've reached the minimum quorum
        uint256 totalOracles = oracleList.length;
        if (totalOracles > 0 && (requests[id].answersCount * 100) / totalOracles >= minimumQuorum) {
            exchangeRates[requests[id].currency] = requests[id].quotation;
            exchangeRateTime[requests[id].currency] = block.timestamp;
            requests[id].active = false;
        }
    }

    /**
     * @dev Read the current exchange rate for a currency
     * @param symbol The currency symbol
     * @return The exchange rate and timestamp of last update
     */
    function readRate(string memory symbol) external view returns (uint256, uint256) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        require(currencies[symbol], "Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }

    /**
     * @dev Add a new oracle for a currency (internal function, called by authorized wallet)
     * @param symbol The currency symbol
     * @param maintainer The oracle maintainer name
     * @param url The oracle URL
     * @param accessAddress The authorized address for this oracle
     */
    function _addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can add oracles");
        
        oracles[symbol].push(OracleInfo(maintainer, url, accessAddress));
        
        // If this is the first oracle for this currency, mark it as supported
        if (!currencies[symbol]) {
            currencies[symbol] = true;
        }
    }

    /**
     * @dev Remove an oracle for a currency (internal function, called by authorized wallet)
     * @param symbol The currency symbol
     * @param accessAddress The authorized address to remove
     */
    function _removeOracle(string memory symbol, address accessAddress) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can remove oracles");
        
        OracleInfo[] storage oracleList = oracles[symbol];
        uint256 length = oracleList.length;
        
        for (uint256 i = 0; i < length; i++) {
            if (oracleList[i].authorizedAddress == accessAddress) {
                // Move the last element to this position to avoid gaps
                oracleList[i] = oracleList[length - 1];
                oracleList.pop();
                
                // If no oracles left for this symbol, mark as unsupported
                if (oracleList.length == 0) {
                    delete currencies[symbol];
                }
                break;
            }
        }
    }

    /**
     * @dev Change the minimum quorum percentage (internal function, called by authorized wallet)
     * @param newQuorum The new quorum percentage
     */
    function _changeMinimumQuorum(uint256 newQuorum) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can change quorum");
        require(newQuorum >= 0 && newQuorum <= 100, "Quorum must be between 0 and 100");
        minimumQuorum = newQuorum;
    }

    /**
     * @dev Check if a currency is supported
     * @param symbol The currency symbol
     * @return Whether the currency is supported
     */
    function isSupported(string memory symbol) external view returns (bool) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        return currencies[symbol];
    }
}

/**
 * @title Exchange Contract
 * @dev Handles currency exchanges using oracle data
 */
contract Exchange {
    // Only authorized wallet can call certain functions
    address authorizedWallet;
    
    // Address of the oracle contract
    address oracleContract;
    
    // Supported currencies
    mapping(string => bool) public currencies;
    
    // URL of the off-chain bridge
    string public bridgeURL;

    /**
     * @dev Emitted when an exchange is initiated
     */
    event ExchangeInitiated(
        address indexed transactor,
        string targetCurrency,
        uint256 exchangeValue,
        uint256 exchangeRate,
        uint256 timestamp
    );

    /**
     * @dev Constructor to set authorized wallet and oracle contract
     * @param _authorizedWallet The address authorized to make calls
     * @param _oracleContract The address of the oracle contract
     */
    constructor(address _authorizedWallet, address _oracleContract) {
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }

    /**
     * @dev Perform an exchange operation
     * @param transactor The address initiating the exchange
     * @param targetCurrency The currency to exchange to
     * @param targetAddress The address to receive the exchanged currency
     * @param maximumRateDelay Maximum allowed delay for exchange rate
     */
    function exchange(
        address transactor,
        string memory targetCurrency,
        address targetAddress,
        uint256 maximumRateDelay
    ) external payable {
        require(msg.sender == authorizedWallet, "Only authorized wallet can initiate exchanges");
        require(bytes(targetCurrency).length == 3, "Target currency must be 3 characters");
        require(currencies[targetCurrency], "Target currency not supported");
        require(targetAddress != address(0), "Target address cannot be zero");
        
        // Check if oracle supports this currency
        (bool success, bytes memory data) = address(oracleContract).staticcall(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success, "Failed to call oracle contract");
        bool oracleSupported = abi.decode(data, (bool));
        require(oracleSupported, "Oracle does not support this currency");
        
        require(msg.value > 0, "Value must be greater than 0");

        // Get the current exchange rate
        (success, data) = address(oracleContract).staticcall(
            abi.encodeWithSignature("readRate(string)", targetCurrency)
        );
        require(success, "Failed to call oracle contract");
        (uint256 exchangeRate, uint256 exchangeRateTime) = abi.decode(data, (uint256, uint256));

        // Check if the rate is too old
        if (block.timestamp - exchangeRateTime > maximumRateDelay) {
            revert("Rate is outdated, please request a new rate");
        }

        // Emit event for off-chain processing
        emit ExchangeInitiated(
            transactor,
            targetCurrency,
            msg.value,
            exchangeRate,
            block.timestamp
        );
    }

    /**
     * @dev Update the bridge URL (internal function, called by authorized wallet)
     * @param newBridgeURL The new bridge URL
     */
    function _updateBridge(string memory newBridgeURL) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can update bridge");
        bridgeURL = newBridgeURL;
    }

    /**
     * @dev Add a supported currency (internal function, called by authorized wallet)
     * @param symbol The currency symbol
     */
    function _addCurrency(string memory symbol) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can add currencies");
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        currencies[symbol] = true;
    }

    /**
     * @dev Remove a supported currency (internal function, called by authorized wallet)
     * @param symbol The currency symbol
     */
    function _removeCurrency(string memory symbol) external {
        require(msg.sender == authorizedWallet, "Only authorized wallet can remove currencies");
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        delete currencies[symbol];
    }

    /**
     * @dev Check if a currency is supported
     * @param symbol The currency symbol
     * @return Whether the currency is supported
     */
    function isSupported(string memory symbol) external view returns (bool) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        return currencies[symbol];
    }
}

/**
 * @title Wallet Contract
 * @dev Main wallet contract that interacts with Oracle and Exchange contracts
 */
contract Wallet {
    // Contract owner
    address public owner;
    
    // Oracle and Exchange contract addresses
    address public oracleContract;
    address public exchangeContract;
    
    // User balances
    mapping(address => uint256) private balances;
    
    // Authorization levels for accounts
    mapping(address => mapping(address => string)) private authorizedAccounts;
    
    // Maximum delay allowed for exchange rates
    uint256 public maximumRateDelay;
    
    // Fee percentage for exchanges
    uint256 public exchangeFee;

    /**
     * @dev Emitted when deposit is made
     */
    event Deposit(address indexed user, uint256 amount);

    /**
     * @dev Emitted when transfer is made
     */
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @dev Emitted when external transfer is made
     */
    event ExternalTransfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @dev Emitted when withdrawal is made
     */
    event Withdrawal(address indexed user, uint256 amount);

    /**
     * @dev Constructor to initialize wallet parameters
     * @param _maximumRateDelay Max delay for exchange rates
     * @param _exchangeFee Fee percentage for exchanges
     */
    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        exchangeFee = _exchangeFee;
    }

    /**
     * @dev Deposit ETH into the wallet
     */
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Transfer tokens within the wallet
     * @param amount Amount to transfer
     * @param to Recipient address
     */
    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    /**
     * @dev Transfer tokens externally (send ETH to external address)
     * @param amount Amount to transfer
     * @param to Recipient address
     */
    function externalTransfer(uint256 amount, address to) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "Transfer failed");
        emit ExternalTransfer(msg.sender, to, amount);
    }

    /**
     * @dev Exchange ETH for another currency
     * @param targetCurrency Target currency symbol
     * @param targetAddress Address to receive the exchanged currency
     * @param amount Amount to exchange
     */
    function exchange(string memory targetCurrency, address targetAddress, uint256 amount) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        
        // Check if exchange supports the currency
        // Get the current exchange rate
        (bool success, bytes memory data) = address(exchangeContract).staticcall(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success, "Failed to call exchange contract");
        bool exchangeSupported = abi.decode(data, (bool));
        require(exchangeSupported, "Exchange does not support this currency");

        balances[msg.sender] -= amount;
        
        // Calculate and collect fee
        uint256 fee = (amount * exchangeFee) / 100;
        balances[owner] += fee;
        
        // Call exchange contract with remaining amount
        (success, ) = exchangeContract.call{value: amount - fee}(
            abi.encodeWithSignature(
                "exchange(address,string,address,uint256)",
                msg.sender,
                targetCurrency,
                targetAddress,
                maximumRateDelay
            )
        );
        require(success, "Exchange call failed");
    }

    /**
     * @dev Withdraw ETH from wallet
     * @param amount Amount to withdraw
     */
    function withdrawn(uint256 amount) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @dev Transfer on behalf of another account (with authorization)
     * @param amount Amount to transfer
     * @param from Source address
     * @param to Destination address
     */
    function transferAUTH(uint256 amount, address from, address to) external {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) || 
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization level"
        );
        require(balances[from] >= amount, "Insufficient balance");
        
        balances[from] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    /**
     * @dev External transfer on behalf of another account (with authorization)
     * @param amount Amount to transfer
     * @param from Source address
     * @param to Destination address
     */
    function externalTransferAUTH(uint256 amount, address from, address to) external payable {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) || 
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization level"
        );
        require(balances[from] >= amount, "Insufficient balance");
        
        balances[from] -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "External transfer failed");
        emit ExternalTransfer(from, to, amount);
    }

    /**
     * @dev Exchange on behalf of another account (with authorization)
     * @param targetCurrency Target currency symbol
     * @param from Source address
     * @param targetAddress Address to receive the exchanged currency
     * @param amount Amount to exchange
     */
    function exchangeAUTH(string memory targetCurrency, address from, address targetAddress, uint256 amount) external payable {
        require(
            keccak256(bytes(authorizedAccounts[from][msg.sender])) == keccak256(bytes("all")),
            "Insufficient authorization level"
        );
        require(balances[from] >= amount, "Insufficient balance");
        
        // Check if exchange supports the currency
        (bool success, bytes memory data) = address(exchangeContract).staticcall(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success, "Failed to call exchange contract");
        bool exchangeSupported = abi.decode(data, (bool));
        require(exchangeSupported, "Exchange does not support this currency");

        balances[from] -= amount;
        
        // Calculate and collect fee
        uint256 fee = (amount * exchangeFee) / 100;
        balances[owner] += fee;
        
        // Call exchange contract with remaining amount
        (success, ) = exchangeContract.call{value: amount - fee}(
            abi.encodeWithSignature(
                "exchange(address,string,address,uint256)",
                from,
                targetCurrency,
                targetAddress,
                maximumRateDelay
            )
        );
        require(success, "Exchange call failed");
    }

    /**
     * @dev Withdraw on behalf of another account (with authorization)
     * @param from Source address
     * @param amount Amount to withdraw
     */
    function withdrawnAUTH(address from, uint256 amount) external payable {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("basic")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "No authorization"
        );
        require(
            keccak256(bytes(authLevel)) != keccak256(bytes("")),
            "Insufficient authorization level"
        );
        require(balances[from] >= amount, "Insufficient balance");
        
        balances[from] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
        emit Withdrawal(from, amount);
    }

    /**
     * @dev Authorize an account with a specific tier
     * @param authorized Account to authorize
     * @param tier Authorization tier ("", "basic", "onchain", "all")
     */
    function authorize(address authorized, string memory tier) external {
        require(
            keccak256(bytes(tier)) == keccak256(bytes("")) ||
            keccak256(bytes(tier)) == keccak256(bytes("basic")) ||
            keccak256(bytes(tier)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(tier)) == keccak256(bytes("all")),
            "Invalid tier"
        );
        authorizedAccounts[msg.sender][authorized] = tier;
    }

    /**
     * @dev Revoke authorization for an account
     * @param unauthorize Account to revoke authorization from
     */
    function revoke(address unauthorize) external {
        delete authorizedAccounts[msg.sender][unauthorize];
    }

    /**
     * @dev Get exchange availability for a currency
     * @param symbol Currency symbol
     * @return Whether the currency is available for exchange
     */
    function getExchangeAvailability(string memory symbol) external view returns (bool) {
        (bool success, bytes memory data) = address(exchangeContract).staticcall(
            abi.encodeWithSignature("isSupported(string)", symbol)
        );
        require(success, "Failed to call exchange contract");
        bool supported = abi.decode(data, (bool));
        return supported;
    }

    /**
     * @dev Get oracle availability for a currency
     * @param symbol Currency symbol
     * @return Whether the currency is available in oracle
     */
    function getOracleAvailability(string memory symbol) external view returns (bool) {
        (bool success, bytes memory data) = address(oracleContract).staticcall(
            abi.encodeWithSignature("isSupported(string)", symbol)
        );
        require(success, "Failed to call exchange contract");
        bool supported = abi.decode(data, (bool));
        return supported;
    }

    /**
     * @dev Get exchange rate for a currency
     * @param symbol Currency symbol
     * @return Exchange rate and timestamp
     */
    function getExchangeRate(string memory symbol) external view returns (uint256, uint256) {
        (bool success, bytes memory data) = address(oracleContract).staticcall(
            abi.encodeWithSignature("readRate(string)", symbol)
        );
        require(success, "Failed to call oracle contract");
        (uint256 exchangeRate, uint256 exchangeRateTime) = abi.decode(data, (uint256, uint256));
        
        return (exchangeRate, exchangeRateTime);
    }

    /**
     * @dev Request exchange rate for a currency
     * @param symbol Currency symbol
     */
    function requestExchangeRate(string memory symbol) external {
        require(msg.sender == owner, "Only owner can request exchange rates");
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("requestRate(string)", symbol)
        );
        require(success, "Request rate call failed");
    }

    /**
     * @dev Add an oracle (only owner)
     * @param symbol Currency symbol
     * @param maintainer Oracle maintainer
     * @param url Oracle URL
     * @param accessAddress Oracle access address
     */
    function addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external {
        require(msg.sender == owner, "Only owner can add oracles");
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("_addOracle(string,string,string,address)", symbol, maintainer, url, accessAddress)
        );
        require(success, "Add oracle call failed");
    }

    /**
     * @dev Remove an oracle (only owner)
     * @param symbol Currency symbol
     * @param accessAddress Oracle access address to remove
     */
    function removeOracle(string memory symbol, address accessAddress) external {
        require(msg.sender == owner, "Only owner can remove oracles");
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("_removeOracle(string,address)", symbol, accessAddress)
        );
        require(success, "Remove oracle call failed");
    }

    /**
     * @dev Change minimum quorum (only owner)
     * @param newQuorum New quorum percentage
     */
    function changeMinimumQuorum(uint256 newQuorum) external {
        require(msg.sender == owner, "Only owner can change quorum");
        require(newQuorum >= 0 && newQuorum <= 100, "Quorum must be between 0 and 100");
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("_changeMinimumQuorum(uint256)", newQuorum)
        );
        require(success, "Change quorum call failed");
    }

    /**
     * @dev Update bridge URL (only owner)
     * @param newBridgeURL New bridge URL
     */
    function updateBridge(string memory newBridgeURL) external {
        require(msg.sender == owner, "Only owner can update bridge");
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_updateBridge(string)", newBridgeURL)
        );
        require(success, "Update bridge call failed");
    }

    /**
     * @dev Add a currency to exchange (only owner)
     * @param symbol Currency symbol
     */
    function addCurrency(string memory symbol) external {
        require(msg.sender == owner, "Only owner can add currencies");
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_addCurrency(string)", symbol)
        );
        require(success, "Add currency call failed");
    }

    /**
     * @dev Remove a currency from exchange (only owner)
     * @param symbol Currency symbol
     */
    function removeCurrency(string memory symbol) external {
        require(msg.sender == owner, "Only owner can remove currencies");
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_removeCurrency(string)", symbol)
        );
        require(success, "Remove currency call failed");
    }

    /**
     * @dev Update oracle contract address (only owner)
     * @param newOracle New oracle contract address
     */
    function updateOracleAddress(address newOracle) external {
        require(msg.sender == owner, "Only owner can update oracle address");
        oracleContract = newOracle;
    }

    /**
     * @dev Update exchange contract address (only owner)
     * @param newExchange New exchange contract address
     */
    function updateExchangeAddress(address newExchange) external {
        require(msg.sender == owner, "Only owner can update exchange address");
        exchangeContract = newExchange;
    }

    /**
     * @dev Update maximum rate delay (only owner)
     * @param newMaximumRateDelay New maximum rate delay
     */
    function updateMaximumRateDelay(uint256 newMaximumRateDelay) external {
        require(msg.sender == owner, "Only owner can update rate delay");
        maximumRateDelay = newMaximumRateDelay;
    }

    /**
     * @dev Update exchange fee (only owner)
     * @param newExchangeFee New exchange fee percentage
     */
    function updateExchangeFee(uint256 newExchangeFee) external {
        require(msg.sender == owner, "Only owner can update exchange fee");
        require(newExchangeFee >= 0 && newExchangeFee <= 100, "Fee must be between 0 and 100");
        exchangeFee = newExchangeFee;
    }

    /**
     * @dev Transfer ownership (only current owner)
     * @param newOwner New owner address
     */
    function changeOwnership(address newOwner) external {
        require(msg.sender == owner, "Only owner can change ownership");
        owner = newOwner;
    }

    /**
     * @dev Get balance of an account
     * @param account Account address
     * @return Balance of the account
     */
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Get authorization level of an account
     * @param user User address
     * @param authorized Authorized account address
     * @return Authorization level
     */
    function getAuthorizationLevel(address user, address authorized) external view returns (string memory) {
        return authorizedAccounts[user][authorized];
    }
}
