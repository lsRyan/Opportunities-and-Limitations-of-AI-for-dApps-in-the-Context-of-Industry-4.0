// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FinancialPoolManager
 * @dev A contract for managing collaborative financing pools where users contribute installments
 * to collectively purchase goods. Winners are randomly selected once sufficient funds are pooled.
 * @notice This contract allows multiple concurrent pools with different configurations
 */
contract FinancialPoolManager {
    
    /// @dev Information about a participant in a pool
    struct ParticipantInfo {
        bool received;      // Whether the participant has already received the good's value
        bool canReceive;    // Whether the participant is currently eligible to receive
        uint256 payments;   // Number of payments made by the participant
    }
    
    /// @dev Information about a financial pool
    struct Pool {
        address owner;                                    // Pool creator and administrator
        string targetGood;                                // Description of the good being purchased
        uint256 goodValue;                                // Total value required for purchase (wei)
        uint256 balance;                                  // Current balance under pool administration
        uint256 minParticipants;                          // Minimum participants needed to activate
        uint256 totalParticipants;                        // Current number of participants
        address[] participants;                           // List of all participants
        mapping(address => ParticipantInfo) participantsInfo; // Participant details
        uint256 winnersCount;                             // Number of winners selected so far
        uint256 installments;                             // Total number of installment periods
        uint256 activationDate;                           // Timestamp when pool was activated
        uint256 installmentValue;                         // Value per installment (wei)
        string status;                                    // Pool status
    }
    
    /// @dev Maps pool ID to Pool struct
    mapping(uint256 => Pool) internal pools;
    
    /// @dev Tracks the latest pool ID
    uint256 public currentId;
    
    /// @dev Events for tracking pool lifecycle
    event PoolCreated(uint256 indexed poolId, address indexed owner, string targetGood, uint256 goodValue);
    event PoolActivated(uint256 indexed poolId, uint256 activationDate);
    event PoolCanceled(uint256 indexed poolId);
    event ParticipantJoined(uint256 indexed poolId, address indexed participant);
    event ParticipantLeft(uint256 indexed poolId, address indexed participant);
    event InstallmentPaid(uint256 indexed poolId, address indexed participant, uint256 amount);
    event WinnerSelected(uint256 indexed poolId, address indexed winner, uint256 amount);
    event PoolFinished(uint256 indexed poolId);
    
    /**
     * @dev Creates a new financing pool
     * @param targetGood Description of the good being purchased
     * @param goodValue Total value required for the purchase in wei
     * @param minParticipants Minimum number of participants needed to activate
     * @param installments Total number of installment periods
     * @return The ID of the newly created pool
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
        require(bytes(targetGood).length > 0, "Target good description cannot be empty");
        
        currentId++;
        
        Pool storage newPool = pools[currentId];
        newPool.owner = msg.sender;
        newPool.targetGood = targetGood;
        newPool.goodValue = goodValue;
        newPool.minParticipants = minParticipants;
        newPool.installments = installments;
        newPool.installmentValue = goodValue / installments;
        newPool.status = "accepting_participants";
        newPool.balance = 0;
        newPool.totalParticipants = 0;
        newPool.winnersCount = 0;
        newPool.activationDate = 0;
        
        emit PoolCreated(currentId, msg.sender, targetGood, goodValue);
        
        return currentId;
    }
    
    /**
     * @dev Activates a pool once minimum participants requirement is met
     * @param poolId The ID of the pool to activate
     */
    function activatePool(uint256 poolId) external {
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        
        require(msg.sender == pool.owner, "Only pool owner can activate");
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not accepting participants"
        );
        require(
            pool.totalParticipants >= pool.minParticipants,
            "Minimum participants requirement not met"
        );
        
        pool.activationDate = block.timestamp;
        pool.status = "active";
        
        emit PoolActivated(poolId, block.timestamp);
    }
    
    /**
     * @dev Cancels a pool before activation
     * @param poolId The ID of the pool to cancel
     */
    function deletePool(uint256 poolId) external {
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        
        require(msg.sender == pool.owner, "Only pool owner can delete");
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Can only delete pools accepting participants"
        );
        
        pool.status = "canceled";
        
        emit PoolCanceled(poolId);
    }
    
    /**
     * @dev Allows a user to join a pool
     * @param poolId The ID of the pool to join
     */
    function participateInPool(uint256 poolId) external {
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not accepting participants"
        );
        
        // Check if participant is already in the pool
        bool alreadyParticipant = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                alreadyParticipant = true;
                break;
            }
        }
        require(!alreadyParticipant, "Already a participant");
        
        pool.totalParticipants++;
        pool.participants.push(msg.sender);
        
        emit ParticipantJoined(poolId, msg.sender);
    }
    
    /**
     * @dev Allows a user to leave a pool before activation
     * @param poolId The ID of the pool to leave
     */
    function leavePool(uint256 poolId) external {
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Can only leave pools accepting participants"
        );
        
        // Find participant index
        uint256 index;
        bool found = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                index = i;
                found = true;
                break;
            }
        }
        require(found, "Not a participant");
        
        pool.totalParticipants--;
        
        // Remove participant by swapping with last element and popping
        delete pool.participantsInfo[msg.sender];
        pool.participants[index] = pool.participants[pool.participants.length - 1];
        pool.participants.pop();
        
        emit ParticipantLeft(poolId, msg.sender);
    }
    
    /**
     * @dev Allows a participant to pay an installment
     * @param poolId The ID of the pool to pay into
     */
    function payInstallment(uint256 poolId) external payable {
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("active")),
            "Pool is not active"
        );
        
        // Verify participant exists
        bool isParticipant = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "Not a participant");
        require(msg.value == pool.installmentValue, "Incorrect installment value");
        
        // Calculate due payments based on time elapsed
        uint256 duePayments = (block.timestamp - pool.activationDate) / 30 days;
        
        ParticipantInfo storage participantInfo = pool.participantsInfo[msg.sender];
        require(participantInfo.payments < duePayments, "No payment due yet");
        
        // Record payment
        participantInfo.payments++;
        pool.balance += msg.value;
        
        emit InstallmentPaid(poolId, msg.sender, msg.value);
        
        // Update eligibility
        if (participantInfo.payments == duePayments && !participantInfo.received) {
            participantInfo.canReceive = true;
        } else {
            participantInfo.canReceive = false;
        }
        
        // Check if we can distribute the good value
        if (pool.balance >= pool.goodValue) {
            _selectAndPayWinner(poolId);
        }
    }
    
    /**
     * @dev Internal function to select a random eligible winner and transfer funds
     * @param poolId The ID of the pool
     */
    function _selectAndPayWinner(uint256 poolId) internal {
        Pool storage pool = pools[poolId];
        
        // Collect eligible participants
        address[] memory eligible = new address[](pool.participants.length);
        uint256 eligibleCount = 0;
        
        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participant = pool.participants[i];
            ParticipantInfo storage info = pool.participantsInfo[participant];
            
            if (info.canReceive && !info.received) {
                eligible[eligibleCount] = participant;
                eligibleCount++;
            }
        }
        
        // No eligible participants
        if (eligibleCount == 0) {
            return;
        }
        
        // Select random winner from eligible participants
        uint256 randomIndex = _generateRandom(eligibleCount, poolId);
        address winner = eligible[randomIndex];
        
        // Update pool state
        pool.balance -= pool.goodValue;
        pool.winnersCount++;
        
        // Update winner's info
        ParticipantInfo storage winnerInfo = pool.participantsInfo[winner];
        winnerInfo.received = true;
        winnerInfo.canReceive = false;
        
        // Transfer funds to winner
        (bool success, ) = payable(winner).call{value: pool.goodValue}("");
        require(success, "Transfer to winner failed");
        
        emit WinnerSelected(poolId, winner, pool.goodValue);
        
        // Check if pool is finished
        if (pool.winnersCount == pool.totalParticipants) {
            pool.status = "finished";
            emit PoolFinished(poolId);
        }
    }
    
    /**
     * @dev Generates a pseudo-random number for winner selection
     * @param max The upper bound for the random number
     * @param poolId The pool ID for additional entropy
     * @return A pseudo-random number between 0 and max-1
     */
    function _generateRandom(uint256 max, uint256 poolId) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    msg.sender,
                    poolId,
                    pools[poolId].winnersCount
                )
            )
        ) % max;
    }
    
    /**
     * @dev Retrieves pool information
     * @param poolId The ID of the pool to query
     * @return owner Pool owner address
     * @return targetGood Description of the target good
     * @return goodValue Total value of the good
     * @return minParticipants Minimum participants required
     * @return totalParticipants Current number of participants
     * @return winnersCount Number of winners selected
     * @return installments Total number of installments
     * @return activationDate Timestamp of activation
     * @return installmentValue Value per installment
     * @return status Current pool status
     */
    function getPool(uint256 poolId) 
        external 
        view 
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
        require(poolId > 0 && poolId <= currentId, "Invalid pool ID");
        
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
            pool.status
        );
    }
}