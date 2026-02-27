// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File LeChat/Wallet_C.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.0;

contract Oracle {
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

    event RequestRate(uint256 id, string url, string symbol);
    event AnswerRate(uint256 id, address oracle, uint256 exchangeRate);
    event UpdateExchangeRate(string symbol, uint256 rate, uint256 time);

    constructor(address _authorizedWallet) {
        authorizedWallet = _authorizedWallet;
    }

    function requestRate(string memory symbol) external returns (uint256) {
        require(msg.sender == authorizedWallet, "Unauthorized");
        require(bytes(symbol).length == 3, "Invalid symbol length");
        require(currencies[symbol], "Currency not supported");

        currentId++;
        requests[currentId].currency = symbol;
        requests[currentId].requestTime = block.timestamp;
        requests[currentId].active = true;

        for (uint256 i = 0; i < oracles[symbol].length; i++) {
            emit RequestRate(currentId, oracles[symbol][i].url, symbol);
        }

        return currentId;
    }

    function answerRequest(uint256 id, uint256 exchangeRate) external {
        require(id > 0 && id <= currentId, "Invalid request ID");
        Request storage request = requests[id];
        require(request.active, "Request not active");
        require(_isAuthorizedOracle(request.currency, msg.sender), "Unauthorized oracle");
        require(!request.answers[msg.sender], "Already answered");

        if (request.requestTime < exchangeRateTime[request.currency]) {
            request.active = false;
            return;
        }

        request.quotation = (request.quotation * request.answersCount + exchangeRate) / (request.answersCount + 1);
        request.answersCount++;
        request.answers[msg.sender] = true;

        if ((request.answersCount * 100) / oracles[request.currency].length >= minimumQuorum) {
            exchangeRates[request.currency] = request.quotation;
            exchangeRateTime[request.currency] = block.timestamp;
            request.active = false;
            emit UpdateExchangeRate(request.currency, request.quotation, block.timestamp);
        }

        emit AnswerRate(id, msg.sender, exchangeRate);
    }

    function readRate(string memory symbol) external view returns (uint256, uint256) {
        require(bytes(symbol).length == 3, "Invalid symbol length");
        require(currencies[symbol], "Currency not supported");
        return (exchangeRates[symbol], exchangeRateTime[symbol]);
    }

    function _addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        oracles[symbol].push(Oracle({
            maintainer: maintainer,
            url: url,
            authorizedAddress: accessAddress
        }));
        currencies[symbol] = true;
    }

    function _removeOracle(string memory symbol, address accessAddress) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        for (uint256 i = 0; i < oracles[symbol].length; i++) {
            if (oracles[symbol][i].authorizedAddress == accessAddress) {
                oracles[symbol][i] = oracles[symbol][oracles[symbol].length - 1];
                oracles[symbol].pop();
                if (oracles[symbol].length == 0) {
                    currencies[symbol] = false;
                }
                return;
            }
        }
    }

    function _changeMinimumQuorum(uint256 newQuorum) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        minimumQuorum = newQuorum;
    }

    function isSupported(string memory symbol) external view returns (bool) {
        return bytes(symbol).length == 3 && currencies[symbol];
    }

    function _isAuthorizedOracle(string memory symbol, address oracleAddress) internal view returns (bool) {
        for (uint256 i = 0; i < oracles[symbol].length; i++) {
            if (oracles[symbol][i].authorizedAddress == oracleAddress) {
                return true;
            }
        }
        return false;
    }
}

contract Exchange {
    address public authorizedWallet;
    address public oracleContract;
    mapping(string => bool) public currencies;
    string public bridgeURL;

    event Exchange(address transactor, string targetCurrency, uint256 amount, uint256 exchangeRate, uint256 timestamp, string bridgeCall);

    constructor(address _authorizedWallet, address _oracleContract) {
        authorizedWallet = _authorizedWallet;
        oracleContract = _oracleContract;
    }

    function exchange(address transactor, string memory targetCurrency, address targetAddress, uint256 maximumRateDelay) external payable {
        require(msg.sender == authorizedWallet, "Unauthorized");
        require(bytes(targetCurrency).length == 3, "Invalid symbol length");
        require(currencies[targetCurrency], "Currency not supported");
        require(targetAddress != address(0), "Invalid target address");
        require(msg.value > 0, "Amount must be greater than 0");

        (uint256 exchangeRate, uint256 exchangeRateTime) = IOracle(oracleContract).readRate(targetCurrency);
        require(block.timestamp - exchangeRateTime <= maximumRateDelay, "Exchange rate outdated");

        emit Exchange(transactor, targetCurrency, msg.value, exchangeRate, block.timestamp, string(abi.encodePacked(bridgeURL, targetCurrency)));
    }

    function _updateBridge(string memory newBridgeURL) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        bridgeURL = newBridgeURL;
    }

    function _addCurrency(string memory symbol) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        require(bytes(symbol).length == 3, "Invalid symbol length");
        currencies[symbol] = true;
    }

    function _removeCurrency(string memory symbol) external {
        require(msg.sender == authorizedWallet, "Unauthorized");
        require(bytes(symbol).length == 3, "Invalid symbol length");
        currencies[symbol] = false;
    }

    function isSupported(string memory symbol) external view returns (bool) {
        return bytes(symbol).length == 3 && currencies[symbol];
    }
}

interface IOracle {
    function readRate(string memory symbol) external view returns (uint256, uint256);
    function isSupported(string memory symbol) external view returns (bool);
    function requestRate(string memory symbol) external returns (uint256);
    function _addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external;
    function _removeOracle(string memory symbol, address accessAddress) external;
    function _changeMinimumQuorum(uint256 newQuorum) external;
}

interface IExchange {
    function exchange(address transactor, string memory targetCurrency, address targetAddress, uint256 maximumRateDelay) external payable;
    function isSupported(string memory symbol) external view returns (bool);
    function _updateBridge(string memory newBridgeURL) external;
    function _addCurrency(string memory symbol) external;
    function _removeCurrency(string memory symbol) external;
}

contract Wallet {
    address public owner;
    address public oracleContract;
    address public exchangeContract;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => string)) private authorizedAccounts;
    uint256 public maximumRateDelay;
    uint256 public exchangeFee;

    event Deposit(address indexed user, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event ExternalTransfer(address indexed from, address indexed to, uint256 amount);
    event Exchange(address indexed user, string targetCurrency, address targetAddress, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Authorize(address indexed owner, address indexed authorized, string tier);
    event Revoke(address indexed owner, address indexed unauthorize);

    constructor(uint256 _maximumRateDelay, uint256 _exchangeFee) {
        owner = msg.sender;
        maximumRateDelay = _maximumRateDelay;
        exchangeFee = _exchangeFee;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function transfer(uint256 amount, address to) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
    }

    function externalTransfer(uint256 amount, address to) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(to).transfer(amount);
        emit ExternalTransfer(msg.sender, to, amount);
    }

    function exchange(string memory targetCurrency, address targetAddress, uint256 amount) external payable {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        require(IExchange(exchangeContract).isSupported(targetCurrency), "Currency not supported");

        uint256 fee = (amount * exchangeFee) / 100;
        balances[msg.sender] -= amount;
        balances[owner] += fee;

        IExchange(exchangeContract).exchange{value: amount - fee}(msg.sender, targetCurrency, targetAddress, maximumRateDelay);
        emit Exchange(msg.sender, targetCurrency, targetAddress, amount - fee);
    }

    function withdrawn(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function transferAUTH(uint256 amount, address from, address to) external {
        require(keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("onchain")) || keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == "all", "Unauthorized");
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function externalTransferAUTH(uint256 amount, address from, address to) external {
        require(keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("onchain")) || keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("all")), "Unauthorized");
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        payable(to).transfer(amount);
        emit ExternalTransfer(from, to, amount);
    }

    function exchangeAUTH(string memory targetCurrency, address from, address targetAddress, uint256 amount) external payable {
        require(keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("all")), "Unauthorized");
        require(balances[from] >= amount, "Insufficient balance");
        require(IExchange(exchangeContract).isSupported(targetCurrency), "Currency not supported");

        uint256 fee = (amount * exchangeFee) / 100;
        balances[from] -= amount;
        balances[owner] += fee;

        IExchange(exchangeContract).exchange{value: amount - fee}(from, targetCurrency, targetAddress, maximumRateDelay);
        emit Exchange(from, targetCurrency, targetAddress, amount - fee);
    }

    function withdrawnAUTH(address from, uint256 amount) external {
        require(keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("basic")) || keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("onchain")) || keccak256(abi.encodePacked(authorizedAccounts[from][msg.sender])) == keccak256(abi.encodePacked("all")), "Unauthorized");
        require(balances[from] >= amount, "Insufficient balance");
        balances[from] -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdrawn(from, amount);
    }

    function authorize(address authorized, string memory tier) external {
        require(keccak256(abi.encodePacked(tier)) == keccak256(abi.encodePacked("basic")) || keccak256(abi.encodePacked(tier)) == keccak256(abi.encodePacked("onchain")) || keccak256(abi.encodePacked(tier)) == keccak256(abi.encodePacked("all")), "Invalid tier");
        authorizedAccounts[msg.sender][authorized] = tier;
        emit Authorize(msg.sender, authorized, tier);
    }

    function revoke(address unauthorize) external {
        authorizedAccounts[msg.sender][unauthorize] = "";
        emit Revoke(msg.sender, unauthorize);
    }

    function getExchangeAvailability(string memory symbol) external view returns (bool) {
        return IExchange(exchangeContract).isSupported(symbol);
    }

    function getOracleAvailability(string memory symbol) external view returns (bool) {
        return IOracle(oracleContract).isSupported(symbol);
    }

    function getExchangeRate(string memory symbol) external view returns (uint256, uint256) {
        return IOracle(oracleContract).readRate(symbol);
    }

    function requestExchangeRate(string memory symbol) external {
        IOracle(oracleContract).requestRate(symbol);
    }

    function addOracle(string memory symbol, string memory maintainer, string memory url, address accessAddress) external {
        require(msg.sender == owner, "Unauthorized");
        IOracle(oracleContract)._addOracle(symbol, maintainer, url, accessAddress);
    }

    function removeOracle(string memory symbol, address accessAddress) external {
        require(msg.sender == owner, "Unauthorized");
        IOracle(oracleContract)._removeOracle(symbol, accessAddress);
    }

    function changeMinimumQuorum(uint256 newQuorum) external {
        require(msg.sender == owner, "Unauthorized");
        require(newQuorum >= 0 && newQuorum <= 100, "Invalid quorum");
        IOracle(oracleContract)._changeMinimumQuorum(newQuorum);
    }

    function updateBridge(string memory newBridgeURL) external {
        require(msg.sender == owner, "Unauthorized");
        IExchange(exchangeContract)._updateBridge(newBridgeURL);
    }

    function addCurrency(string memory symbol) external {
        require(msg.sender == owner, "Unauthorized");
        IExchange(exchangeContract)._addCurrency(symbol);
    }

    function removeCurrency(string memory symbol) external {
        require(msg.sender == owner, "Unauthorized");
        IExchange(exchangeContract)._removeCurrency(symbol);
    }

    function updateOracleAddress(address newOracle) external {
        require(msg.sender == owner, "Unauthorized");
        oracleContract = newOracle;
    }

    function updateExchangeAddress(address newExchange) external {
        require(msg.sender == owner, "Unauthorized");
        exchangeContract = newExchange;
    }

    function updateMaximumRateDelay(uint256 newMaximumRateDelay) external {
        require(msg.sender == owner, "Unauthorized");
        maximumRateDelay = newMaximumRateDelay;
    }

    function updateExchangeFee(uint256 newExchangeFee) external {
        require(msg.sender == owner, "Unauthorized");
        require(newExchangeFee >= 0 && newExchangeFee <= 100, "Invalid fee");
        exchangeFee = newExchangeFee;
    }

    function changeOwnership(address newOwner) external {
        require(msg.sender == owner, "Unauthorized");
        owner = newOwner;
    }
}
