// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File Claude/Wallet.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Oracle
 * @notice Oracle contract for managing exchange rate requests and responses
 * @dev Only accessible by the authorized wallet contract
 */
contract Oracle {
    
    /// @notice Struct representing an oracle provider
    struct OracleData {
        string maintainer;           // Responsible company or institution
        string url;                  // Oracle URL
        address authorizedAddress;   // Authorized address for voting
    }
    
    /// @notice Struct representing a rate request
    struct Request {
        string currency;                      // Currency symbol (e.g., "BTC")
        uint256 requestTime;                  // Request timestamp
        uint256 quotation;                    // Running average of oracle answers
        mapping(address => bool) answers;     // Track oracle responses
        uint256 answersCount;                 // Number of responses received
        bool active;                          // Request status
    }
    
    /// @notice Authorized wallet contract address
    address public authorizedWallet;
    
    /// @notice Mapping of supported currencies
    mapping(string => bool) public currencies;
    
    /// @notice Mapping of currency symbols to oracle providers
    mapping(string => OracleData[]) public oracles;
    
    /// @notice Mapping of request IDs to requests
    mapping(uint256 => Request) public requests;
    
    /// @notice Mapping of currency symbols to latest exchange rates
    mapping(string => uint256) public exchangeRates;
    
    /// @notice Mapping of currency symbols to rate update timestamps
    mapping(string => uint256) public exchangeRateTime;
    
    /// @notice Minimum quorum percentage (default 70%)
    uint256 public minimumQuorum = 70;
    
    /// @notice Current request ID counter
    uint256 internal currentId;
    
    /// @notice Event emitted when a rate request is created
    event RateRequested(uint256 indexed requestId, string url, string currency);
    
    /// @notice Event emitted when an oracle answers a request
    event RateAnswered(uint256 indexed requestId, address indexed oracle, uint256 rate);
    
    /// @notice Event emitted when a rate is finalized
    event RateFinalized(string indexed currency, uint256 rate, uint256 timestamp);
    
    /**
     * @notice Contract constructor
     * @param _authorizedWallet Address of the authorized wallet contract
     */
    constructor(address _authorizedWallet) {
        require(_authorizedWallet != address(0), "Invalid wallet address");
        authorizedWallet = _authorizedWallet;
    }
    
    /// @notice Modifier to restrict access to authorized wallet only
    modifier onlyAuthorizedWallet() {
        require(msg.sender == authorizedWallet, "Unauthorized caller");
        _;
    }
    
    /// @notice Modifier to validate currency symbol length
    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        _;
    }
    
    /**
     * @notice Request exchange rate for a currency
     * @param symbol Currency symbol (must be 3 characters)
     * @return requestId The ID of the created request
     */
    function requestRate(string memory symbol) 
        external 
        onlyAuthorizedWallet 
        validSymbol(symbol) 
        returns (uint256) 
    {
        require(currencies[symbol], "Currency not supported");
        
        currentId++;
        
        // Initialize request
        Request storage req = requests[currentId];
        req.currency = symbol;
        req.requestTime = block.timestamp;
        req.active = true;
        req.quotation = 0;
        req.answersCount = 0;
        
        // Emit events for each oracle
        OracleData[] storage currencyOracles = oracles[symbol];
        for (uint256 i = 0; i < currencyOracles.length; i++) {
            emit RateRequested(currentId, currencyOracles[i].url, symbol);
        }
        
        return currentId;
    }
    
    /**
     * @notice Answer a rate request (called by oracle providers)
     * @param id Request ID
     * @param exchangeRate Proposed exchange rate
     */
    function answerRequest(uint256 id, uint256 exchangeRate) external {
        require(id > 0 && id <= currentId, "Invalid request ID");
        
        Request storage req = requests[id];
        require(req.active, "Request not active");
        
        // Verify sender is an authorized oracle for this currency
        bool isAuthorized = false;
        OracleData[] storage currencyOracles = oracles[req.currency];
        for (uint256 i = 0; i < currencyOracles.length; i++) {
            if (currencyOracles[i].authorizedAddress == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Not an authorized oracle");
        require(!req.answers[msg.sender], "Already answered");
        
        // Check if request is outdated
        if (req.requestTime < exchangeRateTime[req.currency]) {
            req.active = false;
            return;
        }
        
        // Update running average
        req.quotation = (req.quotation * req.answersCount + exchangeRate) / (req.answersCount + 1);
        req.answersCount++;
        req.answers[msg.sender] = true;
        
        emit RateAnswered(id, msg.sender, exchangeRate);
        
        // Check if quorum reached
        uint256 responsePercentage = (req.answersCount * 100) / currencyOracles.length;
        if (responsePercentage >= minimumQuorum) {
            exchangeRates[req.currency] = req.quotation;
            exchangeRateTime[req.currency] = block.timestamp;
            req.active = false;
            
            emit RateFinalized(req.currency, req.quotation, block.timestamp);
        }
    }
    
    /**
     * @notice Read the latest exchange rate for a currency
     * @param symbol Currency symbol
     * @return rate The exchange rate
     * @return timestamp When the rate was last updated
     */
    function readRate(string memory symbol) 
        external 
        view 
        validSymbol(symbol) 
        returns (uint256 rate, uint256 timestamp) 
    {
        require(currencies[symbol], "Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }
    
    /**
     * @notice Add a new oracle provider for a currency
     * @param symbol Currency symbol
     * @param maintainer Oracle maintainer name
     * @param url Oracle URL
     * @param accessAddress Authorized address for this oracle
     */
    function _addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyAuthorizedWallet {
        require(accessAddress != address(0), "Invalid oracle address");
        
        oracles[symbol].push(OracleData({
            maintainer: maintainer,
            url: url,
            authorizedAddress: accessAddress
        }));
        
        // Mark currency as supported if first oracle
        if (!currencies[symbol]) {
            currencies[symbol] = true;
        }
    }
    
    /**
     * @notice Remove an oracle provider for a currency
     * @param symbol Currency symbol
     * @param accessAddress Oracle address to remove
     */
    function _removeOracle(string memory symbol, address accessAddress) 
        external 
        onlyAuthorizedWallet 
    {
        OracleData[] storage currencyOracles = oracles[symbol];
        
        for (uint256 i = 0; i < currencyOracles.length; i++) {
            if (currencyOracles[i].authorizedAddress == accessAddress) {
                // Move last element to current position and pop
                currencyOracles[i] = currencyOracles[currencyOracles.length - 1];
                currencyOracles.pop();
                break;
            }
        }
        
        // Mark currency as unsupported if no oracles remain
        if (currencyOracles.length == 0) {
            currencies[symbol] = false;
        }
    }
    
    /**
     * @notice Update the minimum quorum percentage
     * @param newQuorum New quorum percentage (0-100)
     */
    function _changeMinimumQuorum(uint256 newQuorum) 
        external 
        onlyAuthorizedWallet 
    {
        require(newQuorum <= 100, "Invalid quorum percentage");
        minimumQuorum = newQuorum;
    }
    
    /**
     * @notice Check if a currency is supported
     * @param symbol Currency symbol
     * @return bool True if supported
     */
    function isSupported(string memory symbol) 
        external 
        view 
        validSymbol(symbol) 
        returns (bool) 
    {
        return currencies[symbol];
    }
}

/**
 * @title Exchange
 * @notice Exchange contract for handling cryptocurrency exchanges
 * @dev Only accessible by the authorized wallet contract
 */
contract Exchange {
    
    /// @notice Authorized wallet contract address
    address public authorizedWallet;
    
    /// @notice Oracle contract address
    address public oracleContract;
    
    /// @notice Mapping of supported currencies
    mapping(string => bool) public currencies;
    
    /// @notice Bridge URL for off-chain exchanges
    string public bridgeURL;
    
    /// @notice Event emitted when an exchange is requested
    event ExchangeRequested(
        address indexed transactor,
        string targetCurrency,
        uint256 amount,
        uint256 exchangeRate,
        uint256 timestamp,
        string bridgeCall
    );
    
    /**
     * @notice Contract constructor
     * @param _authorizedWallet Address of the authorized wallet contract
     * @param _oracleContract Address of the oracle contract
     */
    constructor(address _authorizedWallet, address _oracleContract) {
        require(_authorizedWallet != address(0), "Invalid wallet address");
        require(_oracleContract != address(0), "Invalid oracle address");
        
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }
    
    /// @notice Modifier to restrict access to authorized wallet only
    modifier onlyAuthorizedWallet() {
        require(msg.sender == authorizedWallet, "Unauthorized caller");
        _;
    }
    
    /// @notice Modifier to validate currency symbol length
    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        _;
    }
    
    /**
     * @notice Execute a currency exchange
     * @param transactor Address initiating the exchange
     * @param targetCurrency Target currency symbol
     * @param targetAddress Recipient address for exchanged currency
     * @param maximumRateDelay Maximum acceptable rate age in seconds
     */
    function exchange(
        address transactor,
        string memory targetCurrency,
        address targetAddress,
        uint256 maximumRateDelay
    ) external payable onlyAuthorizedWallet validSymbol(targetCurrency) {
        require(currencies[targetCurrency], "Currency not supported");
        require(targetAddress != address(0), "Invalid target address");
        require(msg.value > 0, "Amount must be greater than 0");
        
        // Verify currency is supported by oracle
        (bool success, bytes memory data) = oracleContract.call(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success && abi.decode(data, (bool)), "Oracle does not support currency");
        
        // Get exchange rate from oracle
        (success, data) = oracleContract.call(
            abi.encodeWithSignature("readRate(string)", targetCurrency)
        );
        require(success, "Failed to read exchange rate");
        (uint256 exchangeRate, uint256 exchangeRateTimestamp) = abi.decode(data, (uint256, uint256));
        
        // Verify rate is not too old
        require(
            block.timestamp - exchangeRateTimestamp <= maximumRateDelay,
            "Exchange rate too old, request new rate"
        );
        
        // Emit exchange event for off-chain bridge
        emit ExchangeRequested(
            transactor,
            targetCurrency,
            msg.value,
            exchangeRate,
            block.timestamp,
            string.concat(bridgeURL, targetCurrency)
        );
    }
    
    /**
     * @notice Update the bridge URL
     * @param newBridgeURL New bridge URL
     */
    function _updateBridge(string memory newBridgeURL) 
        external 
        onlyAuthorizedWallet 
    {
        bridgeURL = newBridgeURL;
    }
    
    /**
     * @notice Add a supported currency
     * @param symbol Currency symbol
     */
    function _addCurrency(string memory symbol) 
        external 
        onlyAuthorizedWallet 
        validSymbol(symbol) 
    {
        currencies[symbol] = true;
    }
    
    /**
     * @notice Remove a supported currency
     * @param symbol Currency symbol
     */
    function _removeCurrency(string memory symbol) 
        external 
        onlyAuthorizedWallet 
        validSymbol(symbol) 
    {
        currencies[symbol] = false;
    }
    
    /**
     * @notice Check if a currency is supported
     * @param symbol Currency symbol
     * @return bool True if supported
     */
    function isSupported(string memory symbol) 
        external 
        view 
        validSymbol(symbol) 
        returns (bool) 
    {
        return currencies[symbol];
    }
}

/**
 * @title Wallet
 * @notice Main wallet contract for managing balances, transfers, and exchanges
 * @dev Serves as the gateway to Oracle and Exchange contracts
 */
contract Wallet {
    
    /// @notice Contract owner address
    address public owner;
    
    /// @notice Oracle contract address
    address public oracleContract;
    
    /// @notice Exchange contract address
    address public exchangeContract;
    
    /// @notice User balances
    mapping(address => uint256) private balances;
    
    /// @notice Authorization levels for delegated access
    mapping(address => mapping(address => string)) private authorizedAccounts;
    
    /// @notice Maximum acceptable age for exchange rates (in seconds)
    uint256 public maximumRateDelay;
    
    /// @notice Exchange fee percentage (0-100)
    uint256 public exchangeFee;
    
    /// @notice Event emitted on deposits
    event Deposit(address indexed user, uint256 amount);
    
    /// @notice Event emitted on transfers
    event Transfer(address indexed from, address indexed to, uint256 amount);
    
    /// @notice Event emitted on withdrawals
    event Withdrawal(address indexed user, uint256 amount);
    
    /// @notice Event emitted on authorization changes
    event Authorization(address indexed owner, address indexed authorized, string tier);
    
    /**
     * @notice Contract constructor
     * @param _maximumRateDelay Maximum acceptable rate age
     * @param _exchangeFee Exchange fee percentage
     */
    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        require(_exchangeFee <= 100, "Invalid exchange fee");
        
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        exchangeFee = _exchangeFee;
    }
    
    /// @notice Modifier to restrict access to owner only
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }
    
    /// @notice Modifier to validate currency symbol length
    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        _;
    }
    
    /**
     * @notice Deposit Ether to user's balance
     */
    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
    
    /**
     * @notice Transfer funds to another user's balance within the wallet
     * @param amount Amount to transfer
     * @param to Recipient address
     */
    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient address");
        
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        emit Transfer(msg.sender, to, amount);
    }
    
    /**
     * @notice Transfer funds directly to an external address
     * @param amount Amount to transfer
     * @param to Recipient address
     */
    function externalTransfer(uint256 amount, address to) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient address");
        
        balances[msg.sender] -= amount;
        
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Transfer(msg.sender, to, amount);
    }
    
    /**
     * @notice Exchange Ether for another cryptocurrency
     * @param targetCurrency Target currency symbol
     * @param targetAddress Recipient address for exchanged currency
     * @param amount Amount to exchange
     */
    function exchange(
        string memory targetCurrency,
        address targetAddress,
        uint256 amount
    ) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(exchangeContract != address(0), "Exchange contract not set");
        
        // Verify currency is supported
        (bool success, bytes memory data) = exchangeContract.call(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success && abi.decode(data, (bool)), "Currency not supported");
        
        balances[msg.sender] -= amount;
        
        // Calculate and collect fee
        uint256 fee = (amount * exchangeFee) / 100;
        balances[owner] += fee;
        
        // Call exchange contract
        uint256 exchangeAmount = amount - fee;
        (success, ) = exchangeContract.call{value: exchangeAmount}(
            abi.encodeWithSignature(
                "exchange(address,string,address,uint256)",
                msg.sender,
                targetCurrency,
                targetAddress,
                maximumRateDelay
            )
        );
        require(success, "Exchange failed");
    }
    
    /**
     * @notice Withdraw Ether from wallet balance
     * @param amount Amount to withdraw
     */
    function withdrawn(uint256 amount) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        
        balances[msg.sender] -= amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit Withdrawal(msg.sender, amount);
    }
    
    /**
     * @notice Transfer funds on behalf of another user (with authorization)
     * @param amount Amount to transfer
     * @param from Source address
     * @param to Recipient address
     */
    function transferAUTH(uint256 amount, address from, address to) external {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization"
        );
        require(balances[from] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient address");
        
        balances[from] -= amount;
        balances[to] += amount;
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @notice External transfer on behalf of another user (with authorization)
     * @param amount Amount to transfer
     * @param from Source address
     * @param to Recipient address
     */
    function externalTransferAUTH(uint256 amount, address from, address to) external payable {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization"
        );
        require(balances[from] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient address");
        
        balances[from] -= amount;
        
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");
        
        emit Transfer(from, to, amount);
    }
    
    /**
     * @notice Exchange on behalf of another user (with authorization)
     * @param targetCurrency Target currency symbol
     * @param from Source address
     * @param targetAddress Recipient address for exchanged currency
     * @param amount Amount to exchange
     */
    function exchangeAUTH(
        string memory targetCurrency,
        address from,
        address targetAddress,
        uint256 amount
    ) external payable {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization"
        );
        require(balances[from] >= amount, "Insufficient balance");
        require(exchangeContract != address(0), "Exchange contract not set");
        
        // Verify currency is supported
        (bool success, bytes memory data) = exchangeContract.call(
            abi.encodeWithSignature("isSupported(string)", targetCurrency)
        );
        require(success && abi.decode(data, (bool)), "Currency not supported");
        
        balances[from] -= amount;
        
        // Calculate and collect fee
        uint256 fee = (amount * exchangeFee) / 100;
        balances[owner] += fee;
        
        // Call exchange contract
        uint256 exchangeAmount = amount - fee;
        (success, ) = exchangeContract.call{value: exchangeAmount}(
            abi.encodeWithSignature(
                "exchange(address,string,address,uint256)",
                from,
                targetCurrency,
                targetAddress,
                maximumRateDelay
            )
        );
        require(success, "Exchange failed");
    }
    
    /**
     * @notice Withdraw on behalf of another user (with authorization)
     * @param from Source address
     * @param amount Amount to withdraw
     */
    function withdrawnAUTH(address from, uint256 amount) external payable {
        string memory authLevel = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(authLevel)) == keccak256(bytes("basic")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(authLevel)) == keccak256(bytes("all")),
            "Insufficient authorization"
        );
        require(balances[from] >= amount, "Insufficient balance");
        
        balances[from] -= amount;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawal failed");
        
        emit Withdrawal(from, amount);
    }
    
    /**
     * @notice Authorize another address to access your account
     * @param authorized Address to authorize
     * @param tier Authorization level: "basic", "onchain", or "all"
     */
    function authorize(address authorized, string memory tier) external {
        require(
            keccak256(bytes(tier)) == keccak256(bytes("basic")) ||
            keccak256(bytes(tier)) == keccak256(bytes("onchain")) ||
            keccak256(bytes(tier)) == keccak256(bytes("all")),
            "Invalid authorization tier"
        );
        require(authorized != address(0), "Invalid address");
        
        authorizedAccounts[msg.sender][authorized] = tier;
        emit Authorization(msg.sender, authorized, tier);
    }
    
    /**
     * @notice Revoke authorization for an address
     * @param unauthorize Address to revoke
     */
    function revoke(address unauthorize) external {
        authorizedAccounts[msg.sender][unauthorize] = "";
        emit Authorization(msg.sender, unauthorize, "");
    }
    
    /**
     * @notice Check if currency is supported by exchange
     * @param symbol Currency symbol
     * @return bool True if supported
     */
    function getExchangeAvailability(string memory symbol) 
        external 
        view 
        returns (bool) 
    {
        if (exchangeContract == address(0)) return false;
        
        (bool success, bytes memory data) = exchangeContract.staticcall(
            abi.encodeWithSignature("isSupported(string)", symbol)
        );
        return success && abi.decode(data, (bool));
    }
    
    /**
     * @notice Check if currency is supported by oracle
     * @param symbol Currency symbol
     * @return bool True if supported
     */
    function getOracleAvailability(string memory symbol) 
        external 
        view 
        returns (bool) 
    {
        if (oracleContract == address(0)) return false;
        
        (bool success, bytes memory data) = oracleContract.staticcall(
            abi.encodeWithSignature("isSupported(string)", symbol)
        );
        return success && abi.decode(data, (bool));
    }
    
    /**
     * @notice Get exchange rate for a currency
     * @param symbol Currency symbol
     * @return rate Exchange rate
     * @return timestamp Last update timestamp
     */
    function getExchangeRate(string memory symbol) 
        external 
        view 
        returns (uint256 rate, uint256 timestamp) 
    {
        require(oracleContract != address(0), "Oracle contract not set");
        
        (bool success, bytes memory data) = oracleContract.staticcall(
            abi.encodeWithSignature("readRate(string)", symbol)
        );
        require(success, "Failed to read rate");
        
        return abi.decode(data, (uint256, uint256));
    }
    
    /**
     * @notice Request new exchange rate for a currency
     * @param symbol Currency symbol
     */
    function requestExchangeRate(string memory symbol) external {
        require(oracleContract != address(0), "Oracle contract not set");
        
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("requestRate(string)", symbol)
        );
        require(success, "Request failed");
    }
    
    /**
     * @notice Add oracle provider (owner only)
     * @param symbol Currency symbol
     * @param maintainer Oracle maintainer
     * @param url Oracle URL
     * @param accessAddress Authorized oracle address
     */
    function addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyOwner {
        require(oracleContract != address(0), "Oracle contract not set");
        
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature(
                "_addOracle(string,string,string,address)",
                symbol,
                maintainer,
                url,
                accessAddress
            )
        );
        require(success, "Add oracle failed");
    }
    
    /**
     * @notice Remove oracle provider (owner only)
     * @param symbol Currency symbol
     * @param accessAddress Oracle address to remove
     */
    function removeOracle(string memory symbol, address accessAddress) 
        external 
        onlyOwner 
    {
        require(oracleContract != address(0), "Oracle contract not set");
        
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature(
                "_removeOracle(string,address)",
                symbol,
                accessAddress
            )
        );
        require(success, "Remove oracle failed");
    }
    
    /**
     * @notice Change minimum quorum percentage (owner only)
     * @param newQuorum New quorum percentage (0-100)
     */
    function changeMinimumQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum >= 0 && newQuorum <= 100, "Invalid quorum");
        require(oracleContract != address(0), "Oracle contract not set");
        
        (bool success, ) = oracleContract.call(
            abi.encodeWithSignature("_changeMinimumQuorum(uint256)", newQuorum)
        );
        require(success, "Change quorum failed");
    }
    
    /**
     * @notice Update bridge URL (owner only)
     * @param newBridgeURL New bridge URL
     */
    function updateBridge(string memory newBridgeURL) external onlyOwner {
        require(exchangeContract != address(0), "Exchange contract not set");
        
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_updateBridge(string)", newBridgeURL)
        );
        require(success, "Update bridge failed");
    }
    
    /**
     * @notice Add supported currency to exchange (owner only)
     * @param symbol Currency symbol
     */
    function addCurrency(string memory symbol) external onlyOwner {
        require(exchangeContract != address(0), "Exchange contract not set");
        
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_addCurrency(string)", symbol)
        );
        require(success, "Add currency failed");
    }
    
    /**
     * @notice Remove supported currency from exchange (owner only)
     * @param symbol Currency symbol
     */
    function removeCurrency(string memory symbol) external onlyOwner {
        require(exchangeContract != address(0), "Exchange contract not set");
        
        (bool success, ) = exchangeContract.call(
            abi.encodeWithSignature("_removeCurrency(string)", symbol)
        );
        require(success, "Remove currency failed");
    }
    
    /**
     * @notice Update oracle contract address (owner only)
     * @param newOracle New oracle contract address
     */
    function updateOracleAddress(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid address");
        oracleContract = newOracle;
    }
    
    /**
     * @notice Update exchange contract address (owner only)
     * @param newExchange New exchange contract address
     */
    function updateExchangeAddress(address newExchange) external onlyOwner {
        require(newExchange != address(0), "Invalid address");
        exchangeContract = newExchange;
    }
    
    /**
     * @notice Update maximum rate delay (owner only)
     * @param newMaximumRateDelay New maximum rate delay in seconds
     */
    function updateMaximumRateDelay(uint256 newMaximumRateDelay) 
        external 
        onlyOwner 
    {
        maximumRateDelay = newMaximumRateDelay;
    }
    
    /**
     * @notice Update exchange fee percentage (owner only)
     * @param newExchangeFee New fee percentage (0-100)
     */
    function updateExchangeFee(uint256 newExchangeFee) external onlyOwner {
        require(newExchangeFee >= 0 && newExchangeFee <= 100, "Invalid fee");
        exchangeFee = newExchangeFee;
    }
    
    /**
     * @notice Transfer ownership (owner only)
     * @param newOwner New owner address
     */
    function changeOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    /**
     * @notice Get user balance
     * @param user User address
     * @return uint256 User's balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
    
    /**
     * @notice Receive function to accept Ether
     */
    receive() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }
}
