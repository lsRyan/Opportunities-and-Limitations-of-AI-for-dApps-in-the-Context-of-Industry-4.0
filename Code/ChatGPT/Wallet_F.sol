// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File ChatGPT/Wallet.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title OracleContract
 * @notice Handles exchange rate requests and aggregation from registered oracles.
 *         Only the Wallet contract is authorized to manage and interact with it.
 */
contract OracleContract {
    struct Oracle {
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

    address public authorizedWallet;
    mapping(string => bool) public currencies;
    mapping(string => Oracle[]) public oracles;
    mapping(uint256 => Request) public requests;
    mapping(string => uint256) public exchangeRates;
    mapping(string => uint256) public exchangeRateTime;

    uint256 public minimumQuorum = 70;
    uint256 internal currentId;

    event RateRequested(uint256 indexed id, string oracleURL, string currency);

    modifier onlyWallet() {
        require(msg.sender == authorizedWallet, "Not authorized wallet");
        _;
    }

    constructor(address _authorizedWallet) {
        require(_authorizedWallet != address(0), "Invalid wallet");
        authorizedWallet = _authorizedWallet;
    }

    function _validSymbol(string memory symbol) internal pure returns (bool) {
        return bytes(symbol).length == 3;
    }

    function requestRate(string memory symbol) external onlyWallet returns (uint256) {
        require(_validSymbol(symbol), "Invalid symbol");
        require(currencies[symbol], "Currency not supported");

        currentId++;
        Request storage r = requests[currentId];
        r.currency = symbol;
        r.requestTime = block.timestamp;
        r.active = true;

        Oracle[] storage list = oracles[symbol];
        for (uint256 i = 0; i < list.length; i++) {
            emit RateRequested(currentId, list[i].url, symbol);
        }

        return currentId;
    }

    function answerRequest(uint256 id, uint256 exchangeRate) external {
        Request storage r = requests[id];
        require(r.active, "Request inactive");
        require(bytes(r.currency).length != 0, "Invalid request");

        Oracle[] storage list = oracles[r.currency];
        bool authorized = false;
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].authorizedAddress == msg.sender) {
                authorized = true;
                break;
            }
        }
        require(authorized, "Not an oracle");
        require(!r.answers[msg.sender], "Already answered");

        if (r.requestTime < exchangeRateTime[r.currency]) {
            r.active = false;
            return;
        }

        r.quotation =
            (r.quotation * r.answersCount + exchangeRate) /
            (r.answersCount + 1);

        r.answers[msg.sender] = true;
        r.answersCount++;

        uint256 quorum =
            (r.answersCount * 100) / list.length;

        if (quorum >= minimumQuorum) {
            exchangeRates[r.currency] = r.quotation;
            exchangeRateTime[r.currency] = block.timestamp;
            r.active = false;
        }
    }

    function readRate(string memory symbol)
        external
        view
        returns (uint256, uint256)
    {
        require(_validSymbol(symbol), "Invalid symbol");
        require(currencies[symbol], "Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }

    function _addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyWallet {
        require(_validSymbol(symbol), "Invalid symbol");
        require(accessAddress != address(0), "Invalid address");

        oracles[symbol].push(
            Oracle({
                maintainer: maintainer,
                url: url,
                authorizedAddress: accessAddress
            })
        );

        currencies[symbol] = true;
    }

    function _removeOracle(string memory symbol, address accessAddress)
        external
        onlyWallet
    {
        Oracle[] storage list = oracles[symbol];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].authorizedAddress == accessAddress) {
                list[i] = list[list.length - 1];
                list.pop();
                break;
            }
        }

        if (list.length == 0) {
            currencies[symbol] = false;
        }
    }

    function _changeMinimumQuorum(uint256 newQuorum) external onlyWallet {
        require(newQuorum <= 100, "Invalid quorum");
        minimumQuorum = newQuorum;
    }

    function isSupported(string memory symbol) external view returns (bool) {
        require(_validSymbol(symbol), "Invalid symbol");
        return currencies[symbol];
    }
}

/**
 * @title ExchangeContract
 * @notice Emits exchange events based on oracle rates.
 *         Only callable through the Wallet contract.
 */
contract ExchangeContract {
    address public authorizedWallet;
    address public oracleContract;

    mapping(string => bool) public currencies;
    string public bridgeURL;

    event Exchanged(
        address indexed transactor,
        string currency,
        uint256 value,
        uint256 rate,
        uint256 timestamp,
        string bridgeCall
    );

    modifier onlyWallet() {
        require(msg.sender == authorizedWallet, "Not authorized wallet");
        _;
    }

    constructor(address _authorizedWallet, address _oracleContract) {
        require(_authorizedWallet != address(0), "Invalid wallet");
        require(_oracleContract != address(0), "Invalid oracle");
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }

    function _validSymbol(string memory symbol) internal pure returns (bool) {
        return bytes(symbol).length == 3;
    }

    function exchange(
        address transactor,
        string memory targetCurrency,
        address targetAddress,
        uint256 maximumRateDelay
    ) external payable onlyWallet {
        require(_validSymbol(targetCurrency), "Invalid symbol");
        require(currencies[targetCurrency], "Currency not supported");
        require(targetAddress != address(0), "Invalid address");
        require(msg.value > 0, "No value");

        require(
            OracleContract(oracleContract).isSupported(targetCurrency),
            "Oracle unsupported"
        );

        (uint256 rate, uint256 rateTime) =
            OracleContract(oracleContract).readRate(targetCurrency);

        require(
            block.timestamp - rateTime <= maximumRateDelay,
            "Outdated rate"
        );

        emit Exchanged(
            transactor,
            targetCurrency,
            msg.value,
            rate,
            block.timestamp,
            string.concat(bridgeURL, targetCurrency)
        );
    }

    function _updateBridge(string memory newBridgeURL) external onlyWallet {
        bridgeURL = newBridgeURL;
    }

    function _addCurrency(string memory symbol) external onlyWallet {
        require(_validSymbol(symbol), "Invalid symbol");
        currencies[symbol] = true;
    }

    function _removeCurrency(string memory symbol) external onlyWallet {
        require(_validSymbol(symbol), "Invalid symbol");
        currencies[symbol] = false;
    }

    function isSupported(string memory symbol) external view returns (bool) {
        require(_validSymbol(symbol), "Invalid symbol");
        return currencies[symbol];
    }
}

/**
 * @title Wallet
 * @notice Main entry point for users. Handles balances, authorizations,
 *         and routes all oracle and exchange interactions.
 */
contract Wallet {
    address public owner;
    address public oracleContract;
    address public exchangeContract;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => string)) private authorizedAccounts;

    uint256 public maximumRateDelay;
    uint256 public exchangeFee;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        exchangeFee = _exchangeFee;
    }

    receive() external payable {
        balances[msg.sender] += msg.value;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
    }

    function externalTransfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(to).transfer(amount);
    }

    function exchange(
        string memory targetCurrency,
        address targetAddress,
        uint256 amount
    ) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(
            ExchangeContract(exchangeContract).isSupported(targetCurrency),
            "Currency unsupported"
        );

        balances[msg.sender] -= amount;

        uint256 fee = (amount * exchangeFee) / 100;
        balances[owner] += fee;

        ExchangeContract(exchangeContract).exchange{value: amount - fee}(
            msg.sender,
            targetCurrency,
            targetAddress,
            maximumRateDelay
        );
    }

    function withdrawn(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function authorize(address authorized, string memory tier) external {
        require(
            keccak256(bytes(tier)) == keccak256("basic") ||
                keccak256(bytes(tier)) == keccak256("onchain") ||
                keccak256(bytes(tier)) == keccak256("all"),
            "Invalid tier"
        );
        authorizedAccounts[msg.sender][authorized] = tier;
    }

    function revoke(address unauthorize) external {
        authorizedAccounts[msg.sender][unauthorize] = "";
    }

    function getExchangeAvailability(string memory symbol)
        external
        view
        returns (bool)
    {
        return ExchangeContract(exchangeContract).isSupported(symbol);
    }

    function getOracleAvailability(string memory symbol)
        external
        view
        returns (bool)
    {
        return OracleContract(oracleContract).isSupported(symbol);
    }

    function getExchangeRate(string memory symbol)
        external
        view
        returns (uint256, uint256)
    {
        return OracleContract(oracleContract).readRate(symbol);
    }

    function requestExchangeRate(string memory symbol) external {
        OracleContract(oracleContract).requestRate(symbol);
    }

    function addOracle(
        string memory symbol,
        string memory maintainer,
        string memory url,
        address accessAddress
    ) external onlyOwner {
        OracleContract(oracleContract)._addOracle(
            symbol,
            maintainer,
            url,
            accessAddress
        );
    }

    function removeOracle(string memory symbol, address accessAddress)
        external
        onlyOwner
    {
        OracleContract(oracleContract)._removeOracle(symbol, accessAddress);
    }

    function changeMinimumQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Invalid quorum");
        OracleContract(oracleContract)._changeMinimumQuorum(newQuorum);
    }

    function updateBridge(string memory newBridgeURL) external onlyOwner {
        ExchangeContract(exchangeContract)._updateBridge(newBridgeURL);
    }

    function addCurrency(string memory symbol) external onlyOwner {
        ExchangeContract(exchangeContract)._addCurrency(symbol);
    }

    function removeCurrency(string memory symbol) external onlyOwner {
        ExchangeContract(exchangeContract)._removeCurrency(symbol);
    }

    function updateOracleAddress(address newOracle) external onlyOwner {
        oracleContract = newOracle;
    }

    function updateExchangeAddress(address newExchange) external onlyOwner {
        exchangeContract = newExchange;
    }

    function updateMaximumRateDelay(uint256 newMaximumRateDelay)
        external
        onlyOwner
    {
        maximumRateDelay = newMaximumRateDelay;
    }

    function updateExchangeFee(uint256 newExchangeFee) external onlyOwner {
        require(newExchangeFee <= 100, "Invalid fee");
        exchangeFee = newExchangeFee;
    }

    function changeOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
