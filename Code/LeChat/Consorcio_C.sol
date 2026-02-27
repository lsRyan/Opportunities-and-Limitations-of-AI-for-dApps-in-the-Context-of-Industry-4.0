// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FinancialPoolManager {
    struct ParticipantInfo {
        bool received;
        bool canReceive;
        uint256 payments;
    }

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
        string status; // "accepting_participants", "active", "canceled", "finished"
    }

    mapping(uint256 => Pool) internal pools;
    uint256 public currentId;

    event PoolCreated(uint256 poolId, address owner, string targetGood);
    event PoolActivated(uint256 poolId);
    event PoolDeleted(uint256 poolId);
    event ParticipantJoined(uint256 poolId, address participant);
    event ParticipantLeft(uint256 poolId, address participant);
    event InstallmentPaid(uint256 poolId, address participant, uint256 amount);
    event WinnerSelected(uint256 poolId, address winner, uint256 amount);
    event PoolFinished(uint256 poolId);

    function createPool(
        string memory targetGood,
        uint256 goodValue,
        uint256 minParticipants,
        uint256 installments
    ) external returns (uint256) {
        require(minParticipants > 0, "Minimum participants must be greater than 0");
        require(goodValue > 0, "Good value must be greater than 0");
        require(installments > 0, "Installments must be greater than 0");

        currentId++;
        pools[currentId].owner = msg.sender;
        pools[currentId].targetGood = targetGood;
        pools[currentId].goodValue = goodValue;
        pools[currentId].minParticipants = minParticipants;
        pools[currentId].installments = installments;
        pools[currentId].installmentValue = goodValue / installments;
        pools[currentId].status = "accepting_participants";

        emit PoolCreated(currentId, msg.sender, targetGood);
        return currentId;
    }

    function activatePool(uint256 poolId) external {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        require(msg.sender == pool.owner, "Only the owner can activate the pool");
        require(keccak256(abi.encodePacked(pool.status)) == keccak256(abi.encodePacked("accepting_participants")), "Pool is not in accepting_participants status");
        require(pool.totalParticipants >= pool.minParticipants, "Not enough participants");

        pool.activationDate = block.timestamp;
        pool.status = "active";

        emit PoolActivated(poolId);
    }

    function deletePool(uint256 poolId) external {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        require(msg.sender == pool.owner, "Only the owner can delete the pool");
        require(keccak256(abi.encodePacked(pool.status)) == keccak256(abi.encodePacked("accepting_participants")), "Pool is not in accepting_participants status");

        pool.status = "canceled";

        emit PoolDeleted(poolId);
    }

    function participateInPool(uint256 poolId) external {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        require(keccak256(abi.encodePacked(pool.status)) == keccak256(abi.encodePacked("accepting_participants")), "Pool is not accepting participants");

        // Check if the participant is already in the pool
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                revert("Participant already joined");
            }
        }

        pool.participants.push(msg.sender);
        pool.totalParticipants++;
        pool.participantsInfo[msg.sender] = ParticipantInfo({
            received: false,
            canReceive: false,
            payments: 0
        });

        emit ParticipantJoined(poolId, msg.sender);
    }

    function leavePool(uint256 poolId) external {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        require(keccak256(abi.encodePacked(pool.status)) == keccak256(abi.encodePacked("accepting_participants")), "Pool is not accepting participants");

        uint256 index;
        bool found = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                index = i;
                found = true;
                break;
            }
        }
        require(found, "Participant not found");

        // Swap with the last participant and pop
        if (index != pool.participants.length - 1) {
            pool.participants[index] = pool.participants[pool.participants.length - 1];
        }
        pool.participants.pop();
        pool.totalParticipants--;

        // Remove participant info
        delete pool.participantsInfo[msg.sender];

        emit ParticipantLeft(poolId, msg.sender);
    }

    function payInstallment(uint256 poolId) external payable {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");
        require(keccak256(abi.encodePacked(pool.status)) == keccak256(abi.encodePacked("active")), "Pool is not active");

        // Check if the participant is in the pool
        bool found = false;
        for (uint256 i = 0; i < pool.participants.length; i++) {
            if (pool.participants[i] == msg.sender) {
                found = true;
                break;
            }
        }
        require(found, "Participant not found");
        require(msg.value == pool.installmentValue, "Incorrect payment amount");

        uint256 duePayments = (block.timestamp - pool.activationDate) / 30 days;

        // Update participant's payment info
        pool.participantsInfo[msg.sender].payments++;
        pool.balance += msg.value;

        // Check if the participant is eligible to receive the good
        if (pool.participantsInfo[msg.sender].payments >= duePayments && !pool.participantsInfo[msg.sender].received) {
            pool.participantsInfo[msg.sender].canReceive = true;
        } else {
            pool.participantsInfo[msg.sender].canReceive = false;
        }

        // Check if the pool has enough balance to release the good value
        if (pool.balance >= pool.goodValue) {
            address[] memory eligibleParticipants = new address[](pool.participants.length);
            uint256 eligibleCount = 0;
            for (uint256 i = 0; i < pool.participants.length; i++) {
                address participant = pool.participants[i];
                if (pool.participantsInfo[participant].canReceive && !pool.participantsInfo[participant].received) {
                    eligibleParticipants[eligibleCount] = participant;
                    eligibleCount++;
                }
            }

            if (eligibleCount > 0) {
                // Select a random winner (note: this is not secure in production)
                uint256 randomIndex = uint256(keccak256(abi.encodePacked(block.timestamp, poolId))) % eligibleCount;
                address winner = eligibleParticipants[randomIndex];

                pool.balance -= pool.goodValue;
                pool.winnersCount++;
                pool.participantsInfo[winner].received = true;
                pool.participantsInfo[winner].canReceive = false;

                // Transfer the good value to the winner
                payable(winner).transfer(pool.goodValue);

                emit WinnerSelected(poolId, winner, pool.goodValue);

                // Check if all participants have received the good
                if (pool.winnersCount == pool.totalParticipants) {
                    pool.status = "finished";
                    emit PoolFinished(poolId);
                }
            }
        }

        emit InstallmentPaid(poolId, msg.sender, msg.value);
    }

    function getPool(uint256 poolId) external view returns (
        address,
        string memory,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256,
        string memory
    ) {
        Pool storage pool = pools[poolId];
        require(poolId <= currentId && poolId > 0, "Invalid pool ID");

        return (
            pool.owner,
            pool.targetGood,
            pool.goodValue,
            pool.minParticipants,
            pool.totalParticipants,
            pool.winnersCount,
            pool.installments,
            pool.activationDate,
            pool.status
        );
    }
}
