// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FinancialPoolManager
 * @dev A contract that manages multiple financing pools where users can collectively fund purchases.
 * Users contribute fixed installments over time, and once the total amount is reached,
 * a randomly selected eligible participant receives the funded good's value.
 */
contract FinancialPoolManager {
    /**
     * @notice Information about a participant in a pool
     * @param received Specifies if the participant has already been selected to receive the good's value
     * @param canReceive Specifies if the participant is eligible for receiving the good's value
     * @param payments The number of payments that the user already did
     */
    struct ParticipantInfo {
        bool received;
        bool canReceive;
        uint256 payments;
    }

    /**
     * @notice Information about a financial pool
     * @param owner Pool owner
     * @param targetGood Name or description of the good being purchased
     * @param goodValue The total value required for the purchase in wei
     * @param balance The total value under the pool's administration
     * @param minParticipants Minimum number of participants needed to activate the pool
     * @param totalParticipants The number of participants in the pool
     * @param participants List of participants
     * @param participantsInfo Maps participants to their ParticipantInfo
     * @param winnersCount Count the number of winners
     * @param installments Total number of installments (duration in months)
     * @param activationDate The block.timestamp of the date when the pool was activated
     * @param installmentValue The value which should be paid for each installment
     * @param status The current state of the pool ("accepting_participants", "active", "canceled", "finished")
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
        string status;
    }

    // Mapping from pool ID to Pool struct
    mapping(uint256 => Pool) internal pools;

    // The value of the latest ID
    uint256 public currentId;

    /**
     * @dev Creates a new financing pool
     * @param targetGood Name or description of the good being purchased
     * @param goodValue The total value required for the purchase in wei
     * @param minParticipants Minimum number of participants needed to activate the pool
     * @param installments Total number of installments (duration in months)
     * @return The assigned pool ID
     */
    function createPool(
        string memory targetGood,
        uint256 goodValue,
        uint256 minParticipants,
        uint256 installments
    ) external returns (uint256) {
        require(goodValue > 0, "Good value must be greater than 0");
        require(minParticipants > 0, "Minimum participants must be greater than 0");
        require(installments > 0, "Installments must be greater than 0");

        currentId++;

        Pool storage newPool = pools[currentId];
        newPool.owner = msg.sender;
        newPool.targetGood = targetGood;
        newPool.goodValue = goodValue;
        newPool.minParticipants = minParticipants;
        newPool.installments = installments;
        newPool.installmentValue = goodValue / installments;
        newPool.status = "accepting_participants";

        return currentId;
    }

    /**
     * @dev Activates a pool if it meets the minimum participant requirement
     * @param poolId The ID of the pool to activate
     */
    function activatePool(uint256 poolId) external {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        require(msg.sender == pool.owner, "Only pool owner can activate");
        require(
            pool.totalParticipants >= pool.minParticipants,
            "Not enough participants to activate"
        );
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not accepting participants"
        );

        pool.activationDate = block.timestamp;
        pool.status = "active";
    }

    /**
     * @dev Cancels a pool if it hasn't been activated yet
     * @param poolId The ID of the pool to cancel
     */
    function deletePool(uint256 poolId) external {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        require(msg.sender == pool.owner, "Only pool owner can delete");
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not in accepting participants status"
        );

        pool.status = "canceled";
    }

    /**
     * @dev Allows a user to join an active pool
     * @param poolId The ID of the pool to participate in
     */
    function participateInPool(uint256 poolId) external {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not accepting participants"
        );

        // Check if the user is already a participant
        bool alreadyParticipant = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                alreadyParticipant = true;
                break;
            }
        }
        require(!alreadyParticipant, "User is already a participant");

        pool.totalParticipants++;
        pool.participants.push(msg.sender);
        
        // Initialize participant info
        pool.participantsInfo[msg.sender].received = false;
        pool.participantsInfo[msg.sender].canReceive = false;
        pool.participantsInfo[msg.sender].payments = 0;
    }

    /**
     * @dev Allows a user to leave an unactivated pool
     * @param poolId The ID of the pool to leave
     */
    function leavePool(uint256 poolId) external {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("accepting_participants")),
            "Pool is not accepting participants"
        );

        uint256 index = type(uint256).max;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                index = i;
                break;
            }
        }
        require(index != type(uint256).max, "User is not a participant");

        pool.totalParticipants--;
        
        // Move the last element to the removed position
        if (index != pool.participants.length - 1) {
            pool.participants[index] = pool.participants[pool.participants.length - 1];
        }
        pool.participants.pop();
    }

    /**
     * @dev Pays an installment for a participant in an active pool
     * @param poolId The ID of the pool to pay for
     */
    function payInstallment(uint256 poolId) external payable {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        Pool storage pool = pools[poolId];
        require(
            keccak256(bytes(pool.status)) == keccak256(bytes("active")),
            "Pool is not active"
        );

        // Check if the sender is a participant
        bool isParticipant = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                isParticipant = true;
                break;
            }
        }
        require(isParticipant, "User is not a participant");

        require(msg.value == pool.installmentValue, "Incorrect installment value");

        // Calculate due payments based on time passed since activation
        uint256 duePayments = 0;
        if (block.timestamp > pool.activationDate) {
            duePayments = (block.timestamp - pool.activationDate) / 30 days;
            // Cap due payments to the total installments
            if (duePayments > pool.installments) {
                duePayments = pool.installments;
            }
        }

        ParticipantInfo storage participant = pool.participantsInfo[msg.sender];
        require(participant.payments < duePayments + 1, "Too many payments made");
        require(participant.payments < pool.installments, "All installments already paid");

        participant.payments++;

        // Update the pool's balance
        pool.balance += msg.value;

        // Update eligibility for receiving
        if (participant.payments == duePayments && !participant.received) {
            participant.canReceive = true;
        } else {
            participant.canReceive = false;
        }

        // Check if we have enough balance to award someone
        if (pool.balance >= pool.goodValue) {
            address winner = selectWinner(poolId);

            if (winner != address(0)) {
                // Transfer the good value to the winner
                (bool success, ) = winner.call{value: pool.goodValue}("");
                require(success, "Transfer failed");

                // Update pool balance
                pool.balance -= pool.goodValue;

                // Update winner's status
                pool.winnersCount++;
                pool.participantsInfo[winner].received = true;
                pool.participantsInfo[winner].canReceive = false;

                // Check if all participants have won
                if (pool.winnersCount == pool.totalParticipants) {
                    pool.status = "finished";
                }
            }
        }
    }

    /**
     * @dev Selects a winner from eligible participants
     * @param poolId The ID of the pool
     * @return The address of the winner or address(0) if no eligible participants
     */
    function selectWinner(uint256 poolId) private returns (address) {
        Pool storage pool = pools[poolId];
        
        // Find all eligible participants
        address[] memory eligibleParticipants = new address[](pool.totalParticipants);
        uint256 count = 0;
        
        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participantAddr = pool.participants[i];
            ParticipantInfo storage pInfo = pool.participantsInfo[participantAddr];
            
            if (pInfo.canReceive && !pInfo.received) {
                eligibleParticipants[count] = participantAddr;
                count++;
            }
        }
        
        if (count == 0) {
            return address(0); // No eligible participants
        }
        
        // Use block hash and timestamp for pseudo-random selection
        uint256 randomIndex = (uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    msg.sender
                )
            )
        ) % count);
        
        return eligibleParticipants[randomIndex];
    }

    /**
     * @dev Retrieves information about a specific pool
     * @param poolId The ID of the pool to retrieve
     * @return owner, targetGood, goodValue, minParticipants, totalParticipants, 
     *         winnersCount, installments, activationDate, installmentValue, status
     */
    function getPool(
        uint256 poolId
    ) external view returns (
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
    ) {
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
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