// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File ChatGPT/Consorcio.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.20;

/// @title FinancialPoolManager
/// @author Senior Solidity Developer
/// @notice Manages multiple financing pools where participants collaboratively fund goods
/// @dev This contract follows Solidity best practices and uses Solidity ^0.8.x safety checks
contract FinancialPoolManager {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct ParticipantInfo {
        bool received;        // Whether the participant already received the good value
        bool canReceive;      // Whether the participant is eligible to receive
        uint256 payments;     // Number of installments already paid
    }

    struct Pool {
        address owner;                                   // Pool owner
        string targetGood;                               // Description of the good
        uint256 goodValue;                               // Total value of the good (wei)
        uint256 balance;                                 // Pool balance (wei)
        uint256 minParticipants;                         // Minimum participants to activate
        uint256 totalParticipants;                       // Current number of participants
        address[] participants;                          // List of participants
        mapping(address => ParticipantInfo) participantsInfo;
        mapping(address => bool) isParticipant;          // Fast membership check
        uint256 winnersCount;                            // Number of winners selected
        uint256 installments;                            // Total installments (months)
        uint256 activationDate;                          // Pool activation timestamp
        uint256 installmentValue;                        // Value per installment (wei)
        string status;                                   // Pool status
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => Pool) internal pools;
    uint256 public currentId;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier validPool(uint256 poolId) {
        require(poolId > 0 && poolId <= currentId, "Invalid poolId");
        _;
    }

    modifier onlyOwner(uint256 poolId) {
        require(msg.sender == pools[poolId].owner, "Not pool owner");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            POOL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new financing pool
    function createPool(
        string memory targetGood,
        uint256 goodValue,
        uint256 minParticipants,
        uint256 installments
    ) external returns (uint256) {
        require(goodValue > 0, "Invalid good value");
        require(minParticipants > 0, "Invalid min participants");
        require(installments > 0, "Invalid installments");

        currentId++;

        Pool storage p = pools[currentId];
        p.owner = msg.sender;
        p.targetGood = targetGood;
        p.goodValue = goodValue;
        p.minParticipants = minParticipants;
        p.installments = installments;
        p.installmentValue = goodValue / installments;
        p.status = "accepting_participants";

        return currentId;
    }

    /// @notice Activates a pool once minimum participants are met
    function activatePool(uint256 poolId)
        external
        validPool(poolId)
        onlyOwner(poolId)
    {
        Pool storage p = pools[poolId];
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("accepting_participants")),
            "Invalid pool status"
        );
        require(
            p.totalParticipants >= p.minParticipants,
            "Not enough participants"
        );

        p.activationDate = block.timestamp;
        p.status = "active";
    }

    /// @notice Cancels a pool before activation
    function deletePool(uint256 poolId)
        external
        validPool(poolId)
        onlyOwner(poolId)
    {
        Pool storage p = pools[poolId];
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("accepting_participants")),
            "Pool cannot be canceled"
        );

        p.status = "canceled";
    }

    /*//////////////////////////////////////////////////////////////
                        PARTICIPATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Join a pool before activation
    function participateInPool(uint256 poolId) external validPool(poolId) {
        Pool storage p = pools[poolId];
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("accepting_participants")),
            "Pool not accepting participants"
        );
        require(!p.isParticipant[msg.sender], "Already participating");

        p.participants.push(msg.sender);
        p.isParticipant[msg.sender] = true;
        p.totalParticipants++;
    }

    /// @notice Leave a pool before activation
    function leavePool(uint256 poolId) external validPool(poolId) {
        Pool storage p = pools[poolId];
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("accepting_participants")),
            "Cannot leave pool"
        );
        require(p.isParticipant[msg.sender], "Not a participant");

        uint256 length = p.participants.length;
        for (uint256 i = 0; i < length; i++) {
            if (p.participants[i] == msg.sender) {
                p.participants[i] = p.participants[length - 1];
                p.participants.pop();
                break;
            }
        }

        p.isParticipant[msg.sender] = false;
        p.totalParticipants--;
    }

    /*//////////////////////////////////////////////////////////////
                        PAYMENT & SELECTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Pay one installment to an active pool
    function payInstallment(uint256 poolId)
        external
        payable
        validPool(poolId)
    {
        Pool storage p = pools[poolId];
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("active")),
            "Pool not active"
        );
        require(p.isParticipant[msg.sender], "Not a participant");
        require(msg.value == p.installmentValue, "Incorrect installment value");

        uint256 duePayments = (block.timestamp - p.activationDate) /
            30 days;

        ParticipantInfo storage info = p.participantsInfo[msg.sender];
        require(info.payments < duePayments, "No payment due");

        info.payments += 1;
        p.balance += msg.value;

        if (info.payments == duePayments && !info.received) {
            info.canReceive = true;
        } else {
            info.canReceive = false;
        }

        if (p.balance >= p.goodValue) {
            _selectWinner(poolId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _selectWinner(uint256 poolId) internal {
        Pool storage p = pools[poolId];

        uint256 eligibleCount = 0;
        for (uint256 i = 0; i < p.participants.length; i++) {
            ParticipantInfo storage info = p.participantsInfo[
                p.participants[i]
            ];
            if (info.canReceive && !info.received) {
                eligibleCount++;
            }
        }

        if (eligibleCount == 0) {
            return;
        }

        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    p.balance
                )
            )
        ) % eligibleCount;

        uint256 index;
        uint256 counter;
        for (uint256 i = 0; i < p.participants.length; i++) {
            ParticipantInfo storage info = p.participantsInfo[
                p.participants[i]
            ];
            if (info.canReceive && !info.received) {
                if (counter == rand) {
                    index = i;
                    break;
                }
                counter++;
            }
        }

        address winner = p.participants[index];

        p.balance -= p.goodValue;
        p.winnersCount++;

        ParticipantInfo storage winInfo = p.participantsInfo[winner];
        winInfo.received = true;
        winInfo.canReceive = false;

        (bool success, ) = winner.call{value: p.goodValue}("");
        require(success, "Transfer failed");

        if (p.winnersCount == p.totalParticipants) {
            p.status = "finished";
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns pool public data
    function getPool(uint256 poolId)
        external
        view
        validPool(poolId)
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
        Pool storage p = pools[poolId];
        return (
            p.owner,
            p.targetGood,
            p.goodValue,
            p.minParticipants,
            p.totalParticipants,
            p.winnersCount,
            p.installments,
            p.activationDate,
            p.installmentValue,
            p.status
        );
    }
}
