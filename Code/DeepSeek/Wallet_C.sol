// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Oracle Contract
 * @notice Manages exchange rate oracles and rate requests
 * @dev Only accessible through authorized wallet contract
 */
contract Oracle {
    // Struct Definitions
    struct OracleInfo {
        string maintainer;
        string url;
        address authorizedAddress;
    }

    struct RateRequest {
        string currency;
        uint256 requestTime;
        uint256 quotation;
        mapping(address => bool) answers;
        uint256 answersCount;
        bool active;
    }

    // Events
    event RateRequested(
        uint256 indexed requestId,
        string url,
        string symbol
    );

    event RateUpdated(
        string indexed symbol,
        uint256 rate,
        uint256 timestamp
    );

    event OracleAdded(
        string indexed symbol,
        address indexed oracleAddress,
        string maintainer,
        string url
    );

    event OracleRemoved(
        string indexed symbol,
        address indexed oracleAddress
    );

    event MinimumQuorumChanged(
        uint256 oldQuorum,
        uint256 newQuorum
    );

    // State Variables
    address public authorizedWallet;
    mapping(string => bool) public currencies;
    mapping(string => OracleInfo[]) public oracles;
    mapping(uint256 => RateRequest) public requests;
    mapping(string => uint256) public exchangeRates;
    mapping(string => uint256) public exchangeRateTime;
    
    uint256 public minimumQuorum = 70;
    uint256 private currentId;

    // Modifiers
    modifier onlyAuthorized() {
        require(msg.sender == authorizedWallet, "Oracle: Caller not authorized");
        _;
    }

    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Oracle: Symbol must be 3 characters");
        _;
    }

    /**
     * @notice Constructor sets the authorized wallet address
     * @param _authorizedWallet Address of the wallet contract
     */
    constructor(address _authorizedWallet) {
        authorizedWallet = _authorizedWallet;
    }

    /**
     * @notice Request exchange rate for a currency
     * @param symbol Currency symbol (3 letters)
     * @return requestId The ID of the created request
     */
    function requestRate(string memory symbol) 
        external 
        onlyAuthorized 
        validSymbol(symbol) 
        returns (uint256) 
    {
        require(currencies[symbol], "Oracle: Currency not supported");
        
        currentId++;
        RateRequest storage newRequest = requests[currentId];
        newRequest.currency = symbol;
        newRequest.requestTime = block.timestamp;
        newRequest.quotation = 0;
        newRequest.answersCount = 0;
        newRequest.active = true;

        // Emit events for each oracle
        OracleInfo[] storage oracleList = oracles[symbol];
        for (uint256 i = 0; i < oracleList.length; i++) {
            emit RateRequested(currentId, oracleList[i].url, symbol);
        }

        return currentId;
    }

    /**
     * @notice Submit answer to a rate request
     * @param id Request ID
     * @param exchangeRate Provided exchange rate
     */
    function answerRequest(uint256 id, uint256 exchangeRate) external {
        require(id <= currentId && id > 0, "Oracle: Invalid request ID");
        require(requests[id].active, "Oracle: Request not active");
        
        string memory symbol = requests[id].currency;
        bool isOracle = false;
        OracleInfo[] storage oracleList = oracles[symbol];
        
        // Check if sender is authorized oracle
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i].authorizedAddress == msg.sender) {
                isOracle = true;
                break;
            }
        }
        require(isOracle, "Oracle: Unauthorized oracle");
        require(!requests[id].answers[msg.sender], "Oracle: Already answered");

        // Check if request is outdated
        if (requests[id].requestTime < exchangeRateTime[symbol]) {
            requests[id].active = false;
            return;
        }

        // Update running average
        uint256 currentCount = requests[id].answersCount;
        requests[id].quotation = (requests[id].quotation * currentCount + exchangeRate) / (currentCount + 1);
        requests[id].answersCount++;
        requests[id].answers[msg.sender] = true;

        // Check if quorum is reached
        if ((requests[id].answersCount * 100) / oracleList.length >= minimumQuorum) {
            exchangeRates[symbol] = requests[id].quotation;
            exchangeRateTime[symbol] = block.timestamp;
            requests[id].active = false;
            
            emit RateUpdated(symbol, requests[id].quotation, block.timestamp);
        }
    }

    /**
     * @notice Read current exchange rate and timestamp
     * @param symbol Currency symbol
     * @return rate Current exchange rate
     * @return timestamp Last update timestamp
     */
    function readRate(string memory symbol) 
        external 
        view 
        validSymbol(symbol) 
        returns (uint256, uint256) 
    {
        require(currencies[symbol], "Oracle: Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }

    /**
     * @notice Add a new oracle for a currency
     * @param symbol Currency symbol
     * @param maintainer Oracle maintainer
     * @param url Oracle URL
     * @param accessAddress Oracle authorized address
     */
    function _addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyAuthorized {
        oracles[symbol].push(OracleInfo(maintainer, url, accessAddress));
        
        if (!currencies[symbol]) {
            currencies[symbol] = true;
        }
        
        emit OracleAdded(symbol, accessAddress, maintainer, url);
    }

    /**
     * @notice Remove an oracle for a currency
     * @param symbol Currency symbol
     * @param accessAddress Oracle address to remove
     */
    function _removeOracle(
        string memory symbol, 
        address accessAddress
    ) external onlyAuthorized {
        OracleInfo[] storage oracleList = oracles[symbol];
        
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i].authorizedAddress == accessAddress) {
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
                break;
            }
        }
        
        if (oracleList.length == 0) {
            currencies[symbol] = false;
        }
        
        emit OracleRemoved(symbol, accessAddress);
    }

    /**
     * @notice Change minimum quorum percentage
     * @param newQuorum New quorum percentage (0-100)
     */
    function _changeMinimumQuorum(uint256 newQuorum) external onlyAuthorized {
        require(newQuorum <= 100, "Oracle: Quorum must be <= 100");
        uint256 oldQuorum = minimumQuorum;
        minimumQuorum = newQuorum;
        
        emit MinimumQuorumChanged(oldQuorum, newQuorum);
    }

    /**
     * @notice Check if currency is supported
     * @param symbol Currency symbol
     * @return True if currency is supported
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
 * @title Exchange Contract
 * @notice Handles cryptocurrency exchanges using oracle rates
 * @dev Only accessible through authorized wallet contract
 */
contract Exchange {
    // Events
    event ExchangeExecuted(
        address indexed transactor,
        string targetCurrency,
        uint256 value,
        uint256 exchangeRate,
        uint256 timestamp,
        string bridgeCall
    );

    event BridgeUpdated(string newBridgeURL);
    event CurrencyAdded(string symbol);
    event CurrencyRemoved(string symbol);

    // State Variables
    address public authorizedWallet;
    address public oracleContract;
    mapping(string => bool) public currencies;
    string public bridgeURL;

    // Modifiers
    modifier onlyAuthorized() {
        require(msg.sender == authorizedWallet, "Exchange: Caller not authorized");
        _;
    }

    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Exchange: Symbol must be 3 characters");
        _;
    }

    /**
     * @notice Constructor sets authorized wallet and oracle contract
     * @param _authorizedWallet Wallet contract address
     * @param _oracleContract Oracle contract address
     */
    constructor(address _authorizedWallet, address _oracleContract) {
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }

    /**
     * @notice Execute currency exchange
     * @param transactor User initiating exchange
     * @param targetCurrency Target currency symbol
     * @param targetAddress Recipient address
     * @param maximumRateDelay Maximum allowed rate age
     */
    function exchange(
        address transactor,
        string memory targetCurrency,
        address targetAddress,
        uint256 maximumRateDelay
    ) external payable onlyAuthorized validSymbol(targetCurrency) {
        require(currencies[targetCurrency], "Exchange: Currency not supported");
        require(targetAddress != address(0), "Exchange: Invalid target address");
        require(msg.value > 0, "Exchange: No value sent");
        
        // Check oracle support
        Oracle oracle = Oracle(oracleContract);
        require(oracle.isSupported(targetCurrency), "Exchange: Currency not supported by oracle");
        
        // Get current rate
        (uint256 exchangeRate, uint256 exchangeRateTime) = oracle.readRate(targetCurrency);
        
        require(
            block.timestamp - exchangeRateTime <= maximumRateDelay,
            "Exchange: Rate too old, request new rate"
        );
        
        // Emit exchange event
        string memory bridgeCall = string.concat(bridgeURL, targetCurrency);
        emit ExchangeExecuted(
            transactor,
            targetCurrency,
            msg.value,
            exchangeRate,
            block.timestamp,
            bridgeCall
        );
    }

    /**
     * @notice Update bridge URL
     * @param newBridgeURL New bridge URL
     */
    function _updateBridge(string memory newBridgeURL) external onlyAuthorized {
        bridgeURL = newBridgeURL;
        emit BridgeUpdated(newBridgeURL);
    }

    /**
     * @notice Add supported currency
     * @param symbol Currency symbol
     */
    function _addCurrency(string memory symbol) external onlyAuthorized validSymbol(symbol) {
        currencies[symbol] = true;
        emit CurrencyAdded(symbol);
    }

    /**
     * @notice Remove supported currency
     * @param symbol Currency symbol
     */
    function _removeCurrency(string memory symbol) external onlyAuthorized validSymbol(symbol) {
        currencies[symbol] = false;
        emit CurrencyRemoved(symbol);
    }

    /**
     * @notice Check if currency is supported
     * @param symbol Currency symbol
     * @return True if currency is supported
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
 * @title Wallet Contract
 * @notice Main wallet contract with exchange functionality
 * @dev Users interact only with this contract
 */
contract Wallet {
    // Events
    event Deposited(address indexed user, uint256 amount);
    event Transferred(address indexed from, address indexed to, uint256 amount);
    event Exchanged(address indexed from, string currency, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Authorized(address indexed user, address indexed authorized, string tier);
    event AuthorizationRevoked(address indexed user, address indexed revoked);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event ContractAddressUpdated(string contractType, address newAddress);

    // State Variables
    address public owner;
    address public oracleContract;
    address public exchangeContract;
    
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => string)) private authorizedAccounts;
    
    uint256 public maximumRateDelay;
    uint256 public exchangeFee; // Percentage (0-100)

    // Constants for authorization tiers
    string private constant NO_AUTH = "";
    string private constant BASIC_AUTH = "basic";
    string private constant ONCHAIN_AUTH = "onchain";
    string private constant ALL_AUTH = "all";

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Wallet: Caller not owner");
        _;
    }

    modifier validSymbol(string memory symbol) {
        require(bytes(symbol).length == 3, "Wallet: Symbol must be 3 characters");
        _;
    }

    /**
     * @notice Constructor sets owner and initial parameters
     * @param _maximumRateDelay Maximum allowed oracle rate delay
     * @param _exchangeFee Exchange fee percentage (0-100)
     */
    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        require(_exchangeFee <= 100, "Wallet: Fee must be <= 100");
        exchangeFee = _exchangeFee;
    }

    // Core Wallet Functions

    /**
     * @notice Deposit ETH into wallet
     */
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Transfer between internal balances
     * @param amount Amount to transfer
     * @param to Recipient address
     */
    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Wallet: Insufficient balance");
        
        balances[msg.sender] -= amount;
        balances[to] += amount;
        
        emit Transferred(msg.sender, to, amount);
    }

    /**
     * @notice Transfer from internal balance to external address
     * @param amount Amount to transfer
     * @param to External recipient address
     */
    function externalTransfer(uint256 amount, address to) external payable {
        require(balances[msg.sender] >= amount, "Wallet: Insufficient balance");
        
        balances[msg.sender] -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "Wallet: Transfer failed");
        
        emit Transferred(msg.sender, to, amount);
    }

    // Exchange Functions

    /**
     * @notice Exchange ETH for another currency
     * @param targetCurrency Target currency symbol
     * @param targetAddress Recipient address
     * @param amount Amount to exchange
     */
    function exchange(
        string memory targetCurrency,
        address targetAddress,
        uint256 amount
    ) external payable validSymbol(targetCurrency) {
        require(balances[msg.sender] >= amount, "Wallet: Insufficient balance");
        
        // Check exchange support
        Exchange exchange = Exchange(exchangeContract);
        require(exchange.isSupported(targetCurrency), "Wallet: Currency not supported");
        
        // Calculate fee
        uint256 fee = (amount * exchangeFee) / 100;
        uint256 exchangeAmount = amount - fee;
        
        balances[msg.sender] -= amount;
        balances[owner] += fee;
        
        // Execute exchange
        exchange.exchange{value: exchangeAmount}(
            msg.sender,
            targetCurrency,
            targetAddress,
            maximumRateDelay
        );
        
        emit Exchanged(msg.sender, targetCurrency, amount);
    }

    /**
     * @notice Withdraw from internal balance
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external payable {
        require(balances[msg.sender] >= amount, "Wallet: Insufficient balance");
        
        balances[msg.sender] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Wallet: Withdrawal failed");
        
        emit Withdrawn(msg.sender, amount);
    }

    // Authorization Functions

    /**
     * @notice Transfer with authorization
     * @param amount Amount to transfer
     * @param from Source address
     * @param to Recipient address
     */
    function transferAUTH(uint256 amount, address from, address to) external {
        string memory auth = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(auth)) == keccak256(bytes(ONCHAIN_AUTH)) ||
            keccak256(bytes(auth)) == keccak256(bytes(ALL_AUTH)),
            "Wallet: Insufficient authorization"
        );
        require(balances[from] >= amount, "Wallet: Insufficient balance");
        
        balances[from] -= amount;
        balances[to] += amount;
        
        emit Transferred(from, to, amount);
    }

    /**
     * @notice External transfer with authorization
     * @param amount Amount to transfer
     * @param from Source address
     * @param to External recipient address
     */
    function externalTransferAUTH(uint256 amount, address from, address to) external payable {
        string memory auth = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(auth)) == keccak256(bytes(ONCHAIN_AUTH)) ||
            keccak256(bytes(auth)) == keccak256(bytes(ALL_AUTH)),
            "Wallet: Insufficient authorization"
        );
        require(balances[from] >= amount, "Wallet: Insufficient balance");
        
        balances[from] -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "Wallet: Transfer failed");
        
        emit Transferred(from, to, amount);
    }

    /**
     * @notice Exchange with authorization
     * @param targetCurrency Target currency symbol
     * @param from Source address
     * @param targetAddress Recipient address
     * @param amount Amount to exchange
     */
    function exchangeAUTH(
        string memory targetCurrency,
        address from,
        address targetAddress,
        uint256 amount
    ) external payable validSymbol(targetCurrency) {
        require(
            keccak256(bytes(authorizedAccounts[from][msg.sender])) == keccak256(bytes(ALL_AUTH)),
            "Wallet: Requires 'all' authorization"
        );
        require(balances[from] >= amount, "Wallet: Insufficient balance");
        
        // Check exchange support
        Exchange exchange = Exchange(exchangeContract);
        require(exchange.isSupported(targetCurrency), "Wallet: Currency not supported");
        
        // Calculate fee
        uint256 fee = (amount * exchangeFee) / 100;
        uint256 exchangeAmount = amount - fee;
        
        balances[from] -= amount;
        balances[owner] += fee;
        
        // Execute exchange
        exchange.exchange{value: exchangeAmount}(
            from,
            targetCurrency,
            targetAddress,
            maximumRateDelay
        );
        
        emit Exchanged(from, targetCurrency, amount);
    }

    /**
     * @notice Withdraw with authorization
     * @param from Source address
     * @param amount Amount to withdraw
     */
    function withdrawAUTH(address from, uint256 amount) external payable {
        string memory auth = authorizedAccounts[from][msg.sender];
        require(
            keccak256(bytes(auth)) == keccak256(bytes(BASIC_AUTH)) ||
            keccak256(bytes(auth)) == keccak256(bytes(ONCHAIN_AUTH)) ||
            keccak256(bytes(auth)) == keccak256(bytes(ALL_AUTH)),
            "Wallet: Insufficient authorization"
        );
        require(balances[from] >= amount, "Wallet: Insufficient balance");
        
        balances[from] -= amount;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Wallet: Withdrawal failed");
        
        emit Withdrawn(from, amount);
    }

    /**
     * @notice Authorize another address
     * @param authorized Address to authorize
     * @param tier Authorization tier
     */
    function authorize(address authorized, string memory tier) external {
        require(
            keccak256(bytes(tier)) == keccak256(bytes(BASIC_AUTH)) ||
            keccak256(bytes(tier)) == keccak256(bytes(ONCHAIN_AUTH)) ||
            keccak256(bytes(tier)) == keccak256(bytes(ALL_AUTH)),
            "Wallet: Invalid authorization tier"
        );
        
        authorizedAccounts[msg.sender][authorized] = tier;
        emit Authorized(msg.sender, authorized, tier);
    }

    /**
     * @notice Revoke authorization
     * @param unauthorize Address to revoke
     */
    function revoke(address unauthorize) external {
        authorizedAccounts[msg.sender][unauthorize] = NO_AUTH;
        emit AuthorizationRevoked(msg.sender, unauthorize);
    }

    // View Functions

    /**
     * @notice Get user balance
     * @param user User address
     * @return Current balance
     */
    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }

    /**
     * @notice Get authorization level
     * @param from Source address
     * @param authorized Authorized address
     * @return Authorization tier
     */
    function getAuthorization(address from, address authorized) external view returns (string memory) {
        return authorizedAccounts[from][authorized];
    }

    /**
     * @notice Check exchange availability
     * @param symbol Currency symbol
     * @return True if currency is available for exchange
     */
    function getExchangeAvailability(string memory symbol) external view returns (bool) {
        Exchange exchange = Exchange(exchangeContract);
        return exchange.isSupported(symbol);
    }

    /**
     * @notice Check oracle availability
     * @param symbol Currency symbol
     * @return True if currency is supported by oracle
     */
    function getOracleAvailability(string memory symbol) external view returns (bool) {
        Oracle oracle = Oracle(oracleContract);
        return oracle.isSupported(symbol);
    }

    /**
     * @notice Get current exchange rate
     * @param symbol Currency symbol
     * @return rate Current exchange rate
     * @return timestamp Last update timestamp
     */
    function getExchangeRate(string memory symbol) external view returns (uint256, uint256) {
        Oracle oracle = Oracle(oracleContract);
        return oracle.readRate(symbol);
    }

    // Oracle Management Functions

    /**
     * @notice Request new exchange rate from oracle
     * @param symbol Currency symbol
     */
    function requestExchangeRate(string memory symbol) external validSymbol(symbol) {
        Oracle oracle = Oracle(oracleContract);
        oracle.requestRate(symbol);
    }

    /**
     * @notice Add oracle
     * @param symbol Currency symbol
     * @param maintainer Oracle maintainer
     * @param url Oracle URL
     * @param accessAddress Oracle authorized address
     */
    function addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyOwner validSymbol(symbol) {
        Oracle oracle = Oracle(oracleContract);
        oracle._addOracle(symbol, maintainer, url, accessAddress);
    }

    /**
     * @notice Remove oracle
     * @param symbol Currency symbol
     * @param accessAddress Oracle address to remove
     */
    function removeOracle(string memory symbol, address accessAddress) external onlyOwner validSymbol(symbol) {
        Oracle oracle = Oracle(oracleContract);
        oracle._removeOracle(symbol, accessAddress);
    }

    /**
     * @notice Change minimum quorum
     * @param newQuorum New quorum percentage (0-100)
     */
    function changeMinimumQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Wallet: Quorum must be <= 100");
        Oracle oracle = Oracle(oracleContract);
        oracle._changeMinimumQuorum(newQuorum);
    }

    // Exchange Management Functions

    /**
     * @notice Update bridge URL
     * @param newBridgeURL New bridge URL
     */
    function updateBridge(string memory newBridgeURL) external onlyOwner {
        Exchange exchange = Exchange(exchangeContract);
        exchange._updateBridge(newBridgeURL);
    }

    /**
     * @notice Add supported currency
     * @param symbol Currency symbol
     */
    function addCurrency(string memory symbol) external onlyOwner validSymbol(symbol) {
        Exchange exchange = Exchange(exchangeContract);
        exchange._addCurrency(symbol);
    }

    /**
     * @notice Remove supported currency
     * @param symbol Currency symbol
     */
    function removeCurrency(string memory symbol) external onlyOwner validSymbol(symbol) {
        Exchange exchange = Exchange(exchangeContract);
        exchange._removeCurrency(symbol);
    }

    // Administrative Functions

    /**
     * @notice Update oracle contract address
     * @param newOracle New oracle contract address
     */
    function updateOracleAddress(address newOracle) external onlyOwner {
        oracleContract = newOracle;
        emit ContractAddressUpdated("Oracle", newOracle);
    }

    /**
     * @notice Update exchange contract address
     * @param newExchange New exchange contract address
     */
    function updateExchangeAddress(address newExchange) external onlyOwner {
        exchangeContract = newExchange;
        emit ContractAddressUpdated("Exchange", newExchange);
    }

    /**
     * @notice Update maximum rate delay
     * @param newMaximumRateDelay New maximum delay
     */
    function updateMaximumRateDelay(uint256 newMaximumRateDelay) external onlyOwner {
        maximumRateDelay = newMaximumRateDelay;
    }

    /**
     * @notice Update exchange fee
     * @param newExchangeFee New fee percentage (0-100)
     */
    function updateExchangeFee(uint256 newExchangeFee) external onlyOwner {
        require(newExchangeFee <= 100, "Wallet: Fee must be <= 100");
        exchangeFee = newExchangeFee;
    }

    /**
     * @notice Transfer ownership
     * @param newOwner New owner address
     */
    function changeOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Wallet: Invalid new owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // Fallback function to receive ETH
    receive() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}