// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File DeepSeek/Consorcio.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FinancialPoolManager
 * @dev A smart contract for managing collaborative financing pools where users
 * can collectively fund purchases through fixed installments. One randomly selected
 * participant receives the funded good's value each cycle while continuing payments.
 */
contract FinancialPoolManager {
    /**
     * @dev Participant information structure
     * @param received Whether the participant has already received the good's value
     * @param canReceive Whether the participant is currently eligible to receive
     * @param payments Number of payments made by the participant
     */
    struct ParticipantInfo {
        bool received;
        bool canReceive;
        uint256 payments;
    }

    /**
     * @dev Pool status enumeration for type safety
     */
    enum PoolStatus {
        AcceptingParticipants,
        Active,
        Canceled,
        Finished
    }

    /**
     * @dev Pool information structure
     * @param owner Address of the pool creator/owner
     * @param targetGood Description of the good being purchased
     * @param goodValue Total value required for purchase (in wei)
     * @param balance Current balance in the pool (in wei)
     * @param minParticipants Minimum participants needed to activate
     * @param totalParticipants Current number of participants
     * @param participants Array of participant addresses
     * @param participantsInfo Mapping from address to participant info
     * @param winnersCount Number of winners who have received goods
     * @param installments Total number of installment periods
     * @param activationDate Timestamp when pool was activated
     * @param installmentValue Value of each installment payment (in wei)
     * @param status Current status of the pool
     */
    struct Pool {
        address owner;
        string targetGood;
        uint256 goodValue;
        uint256 balance;
        uint256 minParticipants;
        uint256 totalParticipants;
        address[] participants;
        mapping(address => ParticipantInfo) participantsInfo;
        uint256 winnersCount;
        uint256 installments;
        uint256 activationDate;
        uint256 installmentValue;
        PoolStatus status;
    }

    // State variables
    mapping(uint256 => Pool) internal pools;
    uint256 public currentId;

    // Constants
    uint256 private constant SECONDS_IN_MONTH = 30 days;

    // Events
    event PoolCreated(
        uint256 indexed poolId,
        address indexed owner,
        string targetGood,
        uint256 goodValue,
        uint256 minParticipants,
        uint256 installments
    );
    event PoolActivated(uint256 indexed poolId, uint256 activationDate);
    event PoolCanceled(uint256 indexed poolId);
    event ParticipantJoined(uint256 indexed poolId, address indexed participant);
    event ParticipantLeft(uint256 indexed poolId, address indexed participant);
    event InstallmentPaid(
        uint256 indexed poolId,
        address indexed participant,
        uint256 amount
    );
    event WinnerSelected(
        uint256 indexed poolId,
        address indexed winner,
        uint256 amount
    );
    event PoolFinished(uint256 indexed poolId);

    // Modifiers
    modifier poolExists(uint256 poolId) {
        require(poolId > 0 && poolId <= currentId, "Pool does not exist");
        _;
    }

    modifier onlyPoolOwner(uint256 poolId) {
        require(
            pools[poolId].owner == msg.sender,
            "Caller is not the pool owner"
        );
        _;
    }

    modifier poolStatus(uint256 poolId, PoolStatus expectedStatus) {
        require(
            pools[poolId].status == expectedStatus,
            "Pool status does not allow this operation"
        );
        _;
    }

    modifier isParticipant(uint256 poolId) {
        require(
            isAddressInArray(pools[poolId].participants, msg.sender),
            "Caller is not a participant"
        );
        _;
    }

    modifier notParticipant(uint256 poolId) {
        require(
            !isAddressInArray(pools[poolId].participants, msg.sender),
            "Caller is already a participant"
        );
        _;
    }

    /**
     * @dev Creates a new financing pool
     * @param targetGood Description of the good being purchased
     * @param goodValue Total value required for purchase (in wei)
     * @param minParticipants Minimum participants needed to activate
     * @param installments Total number of installment periods
     * @return poolId The ID of the newly created pool
     */
    function createPool(
        string memory targetGood,
        uint256 goodValue,
        uint256 minParticipants,
        uint256 installments
    ) external returns (uint256) {
        require(goodValue > 0, "Good value must be greater than zero");
        require(minParticipants > 0, "Minimum participants must be greater than zero");
        require(installments > 0, "Installments must be greater than zero");
        require(goodValue % installments == 0, "Good value must be divisible by installments");

        currentId++;
        uint256 poolId = currentId;

        Pool storage newPool = pools[poolId];
        newPool.owner = msg.sender;
        newPool.targetGood = targetGood;
        newPool.goodValue = goodValue;
        newPool.minParticipants = minParticipants;
        newPool.installments = installments;
        newPool.installmentValue = goodValue / installments;
        newPool.status = PoolStatus.AcceptingParticipants;

        emit PoolCreated(
            poolId,
            msg.sender,
            targetGood,
            goodValue,
            minParticipants,
            installments
        );

        return poolId;
    }

    /**
     * @dev Activates a pool that has enough participants
     * @param poolId ID of the pool to activate
     */
    function activatePool(uint256 poolId)
        external
        poolExists(poolId)
        onlyPoolOwner(poolId)
        poolStatus(poolId, PoolStatus.AcceptingParticipants)
    {
        Pool storage pool = pools[poolId];

        require(
            pool.totalParticipants >= pool.minParticipants,
            "Not enough participants to activate"
        );

        pool.activationDate = block.timestamp;
        pool.status = PoolStatus.Active;

        emit PoolActivated(poolId, block.timestamp);
    }

    /**
     * @dev Cancels a pool that is still accepting participants
     * @param poolId ID of the pool to cancel
     */
    function deletePool(uint256 poolId)
        external
        poolExists(poolId)
        onlyPoolOwner(poolId)
        poolStatus(poolId, PoolStatus.AcceptingParticipants)
    {
        pools[poolId].status = PoolStatus.Canceled;
        emit PoolCanceled(poolId);
    }

    /**
     * @dev Allows a user to join a pool
     * @param poolId ID of the pool to join
     */
    function participateInPool(uint256 poolId)
        external
        poolExists(poolId)
        poolStatus(poolId, PoolStatus.AcceptingParticipants)
        notParticipant(poolId)
    {
        Pool storage pool = pools[poolId];

        pool.totalParticipants++;
        pool.participants.push(msg.sender);

        // Initialize participant info
        pool.participantsInfo[msg.sender] = ParticipantInfo({
            received: false,
            canReceive: false,
            payments: 0
        });

        emit ParticipantJoined(poolId, msg.sender);
    }

    /**
     * @dev Allows a user to leave a pool
     * @param poolId ID of the pool to leave
     */
    function leavePool(uint256 poolId)
        external
        poolExists(poolId)
        poolStatus(poolId, PoolStatus.AcceptingParticipants)
        isParticipant(poolId)
    {
        Pool storage pool = pools[poolId];

        // Find participant index
        uint256 participantIndex = findAddressIndex(pool.participants, msg.sender);
        
        // Remove participant from mapping
        delete pool.participantsInfo[msg.sender];

        // Remove from array by swapping with last element
        uint256 lastIndex = pool.participants.length - 1;
        if (participantIndex != lastIndex) {
            pool.participants[participantIndex] = pool.participants[lastIndex];
        }
        pool.participants.pop();

        pool.totalParticipants--;

        emit ParticipantLeft(poolId, msg.sender);
    }

    /**
     * @dev Allows a participant to pay their installment
     * @param poolId ID of the pool
     */
    function payInstallment(uint256 poolId)
        external
        payable
        poolExists(poolId)
        poolStatus(poolId, PoolStatus.Active)
        isParticipant(poolId)
    {
        Pool storage pool = pools[poolId];
        
        require(
            msg.value == pool.installmentValue,
            "Incorrect payment amount"
        );
        require(
            pool.activationDate > 0,
            "Pool activation date not set"
        );

        ParticipantInfo storage participant = pool.participantsInfo[msg.sender];
        
        // Calculate due payments
        uint256 duePayments = (block.timestamp - pool.activationDate) / SECONDS_IN_MONTH;
        
        require(
            participant.payments < duePayments,
            "No payment due at this time"
        );

        // Update participant payment count
        participant.payments++;
        
        // Update pool balance
        pool.balance += msg.value;

        // Update eligibility
        if (participant.payments == duePayments && !participant.received) {
            participant.canReceive = true;
        } else {
            participant.canReceive = false;
        }

        emit InstallmentPaid(poolId, msg.sender, msg.value);

        // Check if we can select a winner
        if (pool.balance >= pool.goodValue) {
            _selectWinner(poolId);
        }
    }

    /**
     * @dev Selects a winner for the pool if conditions are met
     * @param poolId ID of the pool
     */
    function _selectWinner(uint256 poolId) internal {
        Pool storage pool = pools[poolId];

        // Collect eligible participants
        address[] memory eligibleParticipants = new address[](pool.totalParticipants);
        uint256 eligibleCount = 0;

        for (uint256 i = 0; i < pool.totalParticipants; i++) {
            address participant = pool.participants[i];
            ParticipantInfo storage info = pool.participantsInfo[participant];
            
            if (info.canReceive && !info.received) {
                eligibleParticipants[eligibleCount] = participant;
                eligibleCount++;
            }
        }

        // If no eligible participants, exit
        if (eligibleCount == 0) {
            return;
        }

        // Generate pseudo-random index (not cryptographically secure - for demonstration only)
        // In production, use a secure random number generator like Chainlink VRF
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    poolId,
                    pool.winnersCount,
                    eligibleCount
                )
            )
        ) % eligibleCount;

        address winner = eligibleParticipants[randomIndex];
        ParticipantInfo storage winnerInfo = pool.participantsInfo[winner];

        // Update pool balance
        pool.balance -= pool.goodValue;

        // Transfer funds to winner
        (bool success, ) = payable(winner).call{value: pool.goodValue}("");
        require(success, "Transfer failed");

        // Update winner info
        winnerInfo.received = true;
        winnerInfo.canReceive = false;
        pool.winnersCount++;

        emit WinnerSelected(poolId, winner, pool.goodValue);

        // Check if pool is finished
        if (pool.winnersCount == pool.totalParticipants) {
            pool.status = PoolStatus.Finished;
            emit PoolFinished(poolId);
        }
    }

    /**
     * @dev Returns pool information
     * @param poolId ID of the pool
     * @return Tuple containing pool details
     */
    function getPool(uint256 poolId)
        external
        view
        poolExists(poolId)
        returns (
            address,
            string memory,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            string memory
        )
    {
        Pool storage pool = pools[poolId];

        return (
            pool.owner,
            pool.targetGood,
            pool.goodValue,
            pool.minParticipants,
            pool.totalParticipants,
            pool.winnersCount,
            pool.installments,
            pool.activationDate,
            pool.installmentValue,
            _statusToString(pool.status)
        );
    }

    /**
     * @dev Helper function to convert PoolStatus enum to string
     * @param status The pool status enum
     * @return String representation of the status
     */
    function _statusToString(PoolStatus status) internal pure returns (string memory) {
        if (status == PoolStatus.AcceptingParticipants) return "accepting_participants";
        if (status == PoolStatus.Active) return "active";
        if (status == PoolStatus.Canceled) return "canceled";
        if (status == PoolStatus.Finished) return "finished";
        return "unknown";
    }

    /**
     * @dev Helper function to find address index in array
     * @param arr Array to search
     * @param addr Address to find
     * @return Index of the address
     */
    function findAddressIndex(address[] storage arr, address addr) internal view returns (uint256) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == addr) {
                return i;
            }
        }
        revert("Address not found in array");
    }

    /**
     * @dev Helper function to check if address is in array
     * @param arr Array to check
     * @param addr Address to find
     * @return True if address is in array
     */
    function isAddressInArray(address[] storage arr, address addr) internal view returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == addr) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get participant count for a pool
     * @param poolId ID of the pool
     * @return Number of participants
     */
    function getParticipantCount(uint256 poolId) external view poolExists(poolId) returns (uint256) {
        return pools[poolId].totalParticipants;
    }

    /**
     * @dev Get participant info for a specific address
     * @param poolId ID of the pool
     * @param participant Address of the participant
     * @return Participant information
     */
    function getParticipantInfo(uint256 poolId, address participant)
        external
        view
        poolExists(poolId)
        returns (ParticipantInfo memory)
    {
        return pools[poolId].participantsInfo[participant];
    }

    /**
     * @dev Get all participants in a pool
     * @param poolId ID of the pool
     * @return Array of participant addresses
     */
    function getAllParticipants(uint256 poolId)
        external
        view
        poolExists(poolId)
        returns (address[] memory)
    {
        return pools[poolId].participants;
    }

    // Prevent direct ETH transfers
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }

    fallback() external payable {
        revert("Direct ETH transfers not allowed");
    }
}
