// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IOracle
 * @dev Interface for the Oracle contract to allow interaction from Wallet and Exchange.
 */
interface IOracle {
    function requestRate(string memory symbol) external returns (uint256);
    function readRate(string memory symbol) external view returns (uint256, uint256);
    function isSupported(string memory symbol) external view returns (bool);
    function _addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external;
    function _removeOracle(string memory symbol, address accessAddress) external;
    function _changeMinimumQuorum(uint256 newQuorum) external;
}

/**
 * @title IExchange
 * @dev Interface for the Exchange contract to allow interaction from Wallet.
 */
interface IExchange {
    function exchange(address transactor, string memory targetCurrency, address targetAddress, uint256 maximumRateDelay) external payable;
    function isSupported(string memory symbol) external view returns (bool);
    function _updateBridge(string memory newBridgeURL) external;
    function _addCurrency(string memory symbol) external;
    function _removeCurrency(string memory symbol) external;
}

/**
 * @title Oracle
 * @dev Manages exchange rates between Ether and other currencies using a consensus mechanism.
 * Only accessible via the authorized Wallet contract.
 */
contract Oracle {
    // --- Structs ---

    struct OracleInfo {
        string maintainer;
        string url;
        address authorizedAddress;
    }

    struct Request {
        string currency;
        uint256 requestTime;
        uint256 quotation;
        mapping(address => bool) answers;
        uint256 answersCount;
        bool active;
    }

    // --- State Variables ---

    address public authorizedWallet;
    uint256 public minimumQuorum; // Percentage (0-100)
    uint256 internal currentId;

    // Mappings
    mapping(string => bool) public currencies;
    mapping(string => OracleInfo[]) public oracles;
    mapping(uint256 => Request) public requests;
    mapping(string => uint256) public exchangeRates;
    mapping(string => uint256) public exchangeRateTime;

    // --- Events ---

    event RateRequested(uint256 indexed id, string url, string symbol);
    event RateUpdated(string symbol, uint256 rate, uint256 timestamp);

    // --- Modifiers ---

    modifier onlyAuthorizedWallet() {
        require(msg.sender == authorizedWallet, "Caller is not the authorized wallet");
        _;
    }

    // --- Constructor ---

    /**
     * @param _authorizedWallet The address of the main Wallet contract.
     */
    constructor(address _authorizedWallet) {
        authorizedWallet = _authorizedWallet;
        minimumQuorum = 70; // Default 70%
    }

    // --- External Functions ---

    /**
     * @dev Initiates a request for an exchange rate.
     * @param symbol The currency symbol (must be 3 chars).
     * @return The ID of the created request.
     */
    function requestRate(string memory symbol) external onlyAuthorizedWallet returns (uint256) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        require(currencies[symbol], "Currency not supported");

        currentId++;
        
        // Initialize request
        Request storage newRequest = requests[currentId];
        newRequest.currency = symbol;
        newRequest.requestTime = block.timestamp;
        newRequest.active = true;
        // answersCount defaults to 0, quotation defaults to 0

        // Emit event for each registered oracle
        OracleInfo[] memory oracleList = oracles[symbol];
        for (uint256 i = 0; i < oracleList.length; i++) {
            emit RateRequested(currentId, oracleList[i].url, symbol);
        }

        return currentId;
    }

    /**
     * @dev Called by registered oracles to submit exchange rates.
     * @param id The request ID.
     * @param exchangeRate The submitted rate.
     */
    function answerRequest(uint256 id, uint256 exchangeRate) external {
        Request storage req = requests[id];
        
        require(id > 0 && id <= currentId, "Invalid ID");
        require(req.active, "Request not active");
        require(!req.answers[msg.sender], "Oracle already answered");

        // Check if sender is an authorized oracle for this currency
        bool isAuthorized = false;
        OracleInfo[] memory oracleList = oracles[req.currency];
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i].authorizedAddress == msg.sender) {
                isAuthorized = true;
                break;
            }
        }
        require(isAuthorized, "Caller is not an authorized oracle");

        // Check if request is outdated
        if (req.requestTime < exchangeRateTime[req.currency]) {
            req.active = false;
            return;
        }

        // Update running average
        // Formula: (current * count + new) / (count + 1)
        req.quotation = ((req.quotation * req.answersCount) + exchangeRate) / (req.answersCount + 1);
        
        req.answersCount++;
        req.answers[msg.sender] = true;

        // Check Quorum
        uint256 totalOracles = oracles[req.currency].length;
        if (totalOracles > 0 && (req.answersCount * 100) / totalOracles >= minimumQuorum) {
            exchangeRates[req.currency] = req.quotation;
            exchangeRateTime[req.currency] = block.timestamp;
            req.active = false; // Fulfilled
            
            emit RateUpdated(req.currency, req.quotation, block.timestamp);
        }
    }

    /**
     * @dev Reads the latest consolidated exchange rate.
     * @param symbol The currency symbol.
     * @return rate The exchange rate.
     * @return timestamp The time of the last update.
     */
    function readRate(string memory symbol) external view returns (uint256 rate, uint256 timestamp) {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        require(currencies[symbol], "Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }

    /**
     * @dev Checks if a symbol is supported.
     */
    function isSupported(string memory symbol) external view returns (bool) {
        if (bytes(symbol).length != 3) {
            return false;
        }
        return currencies[symbol];
    }

    // --- Admin Functions (Restricted to Authorized Wallet) ---

    function _addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyAuthorizedWallet {
        OracleInfo memory newOracle = OracleInfo({
            maintainer: maintainer,
            url: url,
            authorizedAddress: accessAddress
        });
        
        oracles[symbol].push(newOracle);

        if (!currencies[symbol]) {
            currencies[symbol] = true;
        }
    }

    function _removeOracle(string memory symbol, address accessAddress) external onlyAuthorizedWallet {
        OracleInfo[] storage oracleList = oracles[symbol];
        
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i].authorizedAddress == accessAddress) {
                // Remove by swapping with last element and popping
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
                break;
            }
        }

        if (oracleList.length == 0) {
            currencies[symbol] = false;
        }
    }

    function _changeMinimumQuorum(uint256 newQuorum) external onlyAuthorizedWallet {
        require(newQuorum <= 100, "Invalid quorum percentage");
        minimumQuorum = newQuorum;
    }
}

/**
 * @title Exchange
 * @dev Handles cryptocurrency exchanges via an off-chain bridge integration.
 * Only accessible via the authorized Wallet contract.
 */
contract Exchange {
    // --- State Variables ---

    address public authorizedWallet;
    address public oracleContract;
    string public bridgeURL;
    mapping(string => bool) public currencies;

    // --- Events ---

    event ExchangeTriggered(
        address indexed transactor,
        string targetCurrency,
        uint256 exchangeValue,
        uint256 exchangeRate,
        uint256 timestamp,
        string bridgeCall
    );

    // --- Modifiers ---

    modifier onlyAuthorizedWallet() {
        require(msg.sender == authorizedWallet, "Caller is not the authorized wallet");
        _;
    }

    // --- Constructor ---

    constructor(address _authorizedWallet, address _oracleContract) {
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }

    // --- External Functions ---

    /**
     * @dev Executes an exchange request.
     */
    function exchange(
        address transactor,
        string memory targetCurrency,
        address targetAddress,
        uint256 maximumRateDelay
    ) external payable onlyAuthorizedWallet {
        require(bytes(targetCurrency).length == 3, "Symbol must be 3 characters");
        require(currencies[targetCurrency], "Currency not supported by exchange");
        require(targetAddress != address(0), "Invalid target address");
        require(IOracle(oracleContract).isSupported(targetCurrency), "Currency not supported by oracle");
        require(msg.value > 0, "Value must be greater than 0");

        (uint256 rate, uint256 rateTime) = IOracle(oracleContract).readRate(targetCurrency);

        if ((block.timestamp - rateTime) > maximumRateDelay) {
            // Revert with explicit message as requested
            revert("Rate outdated. Request new rate.");
        } else {
            string memory finalUrl = string.concat(bridgeURL, targetCurrency);
            
            emit ExchangeTriggered(
                transactor,
                targetCurrency,
                msg.value,
                rate,
                block.timestamp,
                finalUrl
            );
        }
    }

    function isSupported(string memory symbol) external view returns (bool) {
        if (bytes(symbol).length != 3) {
            return false;
        }
        return currencies[symbol];
    }

    // --- Admin Functions (Restricted to Authorized Wallet) ---

    function _updateBridge(string memory newBridgeURL) external onlyAuthorizedWallet {
        bridgeURL = newBridgeURL;
    }

    function _addCurrency(string memory symbol) external onlyAuthorizedWallet {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        currencies[symbol] = true;
    }

    function _removeCurrency(string memory symbol) external onlyAuthorizedWallet {
        require(bytes(symbol).length == 3, "Symbol must be 3 characters");
        currencies[symbol] = false;
    }
}

/**
 * @title Wallet
 * @dev Main user interface for the DApp. Manages balances, access control, and interactions with Oracle/Exchange.
 * Implements ReentrancyGuard for security.
 */
contract Wallet {
    // --- State Variables ---

    address public owner;
    address public oracleContract;
    address public exchangeContract;
    
    // Mapping: User -> Balance
    mapping(address => uint256) private balances;
    
    // Mapping: User -> Authorized Delegate -> Tier ("" | "basic" | "onchain" | "all")
    mapping(address => mapping(address => string)) private authorizedAccounts;
    
    uint256 public maximumRateDelay;
    uint256 public exchangeFee; // Percentage (0-100)

    // Security: Reentrancy Guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    // --- Modifiers ---

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    // --- Constructor ---

    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        exchangeFee = _exchangeFee;
        _status = _NOT_ENTERED;
    }

    // --- Helper Functions ---
    
    /**
     * @dev Internal helper to compare strings for auth tiers.
     */
    function _compareStrings(string memory a, string memory b) private pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    // --- Core Wallet Functions ---

    /**
     * @dev Deposits Ether into the user's wallet balance.
     */
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /**
     * @dev Internal transfer between accounts within the wallet.
     */
    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient");

        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    /**
     * @dev Transfer funds from internal balance to an external blockchain address.
     */
    function externalTransfer(uint256 amount, address to) external payable nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient");

        balances[msg.sender] -= amount;
        
        (bool success, ) = to.call{value: amount}("");
        require(success, "External transfer failed");
    }

    /**
     * @dev Exchange internal balance for other currencies via the Exchange contract.
     */
    function exchange(string memory targetCurrency, address targetAddress, uint256 amount) external payable nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(IExchange(exchangeContract).isSupported(targetCurrency), "Currency not supported");

        balances[msg.sender] -= amount;
        
        uint256 fee = (amount * exchangeFee) / 100;
        uint256 amountAfterFee = amount - fee;

        balances[owner] += fee;

        // Call Exchange contract
        IExchange(exchangeContract).exchange{value: amountAfterFee}(
            msg.sender,
            targetCurrency,
            targetAddress,
            maximumRateDelay
        );
    }

    /**
     * @dev Withdraw internal balance to the sender's external address.
     */
    function withdrawn(uint256 amount) external payable nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient balance");

        balances[msg.sender] -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    // --- Authorized Account Functions ---

    /**
     * @dev Transfer internal funds on behalf of another user. Requires "onchain" or "all" tier.
     */
    function transferAUTH(uint256 amount, address from, address to) external {
        string memory tier = authorizedAccounts[from][msg.sender];
        require(
            _compareStrings(tier, "onchain") || _compareStrings(tier, "all"),
            "Unauthorized access"
        );
        require(balances[from] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient");

        balances[from] -= amount;
        balances[to] += amount;
    }

    /**
     * @dev Transfer funds externally on behalf of another user. Requires "onchain" or "all" tier.
     */
    function externalTransferAUTH(uint256 amount, address from, address to) external payable nonReentrant {
        string memory tier = authorizedAccounts[from][msg.sender];
        require(
            _compareStrings(tier, "onchain") || _compareStrings(tier, "all"),
            "Unauthorized access"
        );
        require(balances[from] >= amount, "Insufficient balance");
        require(to != address(0), "Invalid recipient");

        balances[from] -= amount;

        (bool success, ) = to.call{value: amount}("");
        require(success, "External transfer failed");
    }

    /**
     * @dev Exchange funds on behalf of another user. Requires "all" tier.
     */
    function exchangeAUTH(string memory targetCurrency, address from, address targetAddress, uint256 amount) external payable nonReentrant {
        string memory tier = authorizedAccounts[from][msg.sender];
        require(_compareStrings(tier, "all"), "Unauthorized access");
        require(balances[from] >= amount, "Insufficient balance");
        require(IExchange(exchangeContract).isSupported(targetCurrency), "Currency not supported");

        balances[from] -= amount;

        uint256 fee = (amount * exchangeFee) / 100;
        uint256 amountAfterFee = amount - fee;

        balances[owner] += fee;

        IExchange(exchangeContract).exchange{value: amountAfterFee}(
            from,
            targetCurrency,
            targetAddress,
            maximumRateDelay
        );
    }

    /**
     * @dev Withdraw funds to the delegate (msg.sender) on behalf of user. Requires "basic", "onchain", or "all".
     */
    function withdrawnAUTH(address from, uint256 amount) external payable nonReentrant {
        string memory tier = authorizedAccounts[from][msg.sender];
        require(
            _compareStrings(tier, "basic") || 
            _compareStrings(tier, "onchain") || 
            _compareStrings(tier, "all"),
            "Unauthorized access"
        );
        require(balances[from] >= amount, "Insufficient balance");

        balances[from] -= amount;

        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Authorize a delegate address with a specific tier.
     */
    function authorize(address authorized, string memory tier) external {
        require(
            _compareStrings(tier, "basic") || 
            _compareStrings(tier, "onchain") || 
            _compareStrings(tier, "all"),
            "Invalid tier"
        );
        authorizedAccounts[msg.sender][authorized] = tier;
    }

    /**
     * @dev Revoke authorization from a delegate.
     */
    function revoke(address unauthorize) external {
        authorizedAccounts[msg.sender][unauthorize] = "";
    }

    // --- Read Functions (Proxies) ---

    function getExchangeAvailability(string memory symbol) external view returns (bool) {
        return IExchange(exchangeContract).isSupported(symbol);
    }

    function getOracleAvailability(string memory symbol) external view returns (bool) {
        return IOracle(oracleContract).isSupported(symbol);
    }

    function getExchangeRate(string memory symbol) external view returns (uint256, uint256) {
        return IOracle(oracleContract).readRate(symbol);
    }
    
    // --- Oracle Interaction ---

    function requestExchangeRate(string memory symbol) external {
        IOracle(oracleContract).requestRate(symbol);
    }

    // --- Admin Functions (Proxies & Wallet Management) ---

    function addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external onlyOwner {
        IOracle(oracleContract)._addOracle(symbol, maintainer, url, accessAddress);
    }

    function removeOracle(string memory symbol, address accessAddress) external onlyOwner {
        IOracle(oracleContract)._removeOracle(symbol, accessAddress);
    }

    function changeMinimumQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum >= 0 && newQuorum <= 100, "Invalid quorum");
        IOracle(oracleContract)._changeMinimumQuorum(newQuorum);
    }

    function updateBridge(string memory newBridgeURL) external onlyOwner {
        IExchange(exchangeContract)._updateBridge(newBridgeURL);
    }

    function addCurrency(string memory symbol) external onlyOwner {
        IExchange(exchangeContract)._addCurrency(symbol);
    }

    function removeCurrency(string memory symbol) external onlyOwner {
        IExchange(exchangeContract)._removeCurrency(symbol);
    }

    function updateOracleAddress(address newOracle) external onlyOwner {
        require(newOracle != address(0), "Invalid address");
        oracleContract = newOracle;
    }

    function updateExchangeAddress(address newExchange) external onlyOwner {
        require(newExchange != address(0), "Invalid address");
        exchangeContract = newExchange;
    }

    function updateMaximumRateDelay(uint256 newMaximumRateDelay) external onlyOwner {
        maximumRateDelay = newMaximumRateDelay;
    }

    function updateExchangeFee(uint256 newExchangeFee) external onlyOwner {
        require(newExchangeFee >= 0 && newExchangeFee <= 100, "Invalid fee");
        exchangeFee = newExchangeFee;
    }

    function changeOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    // Allow the contract to receive ETH (required for deposit logic where ETH isn't coming from a payable function execution)
    receive() external payable {
        balances[msg.sender] += msg.value;
    }
}