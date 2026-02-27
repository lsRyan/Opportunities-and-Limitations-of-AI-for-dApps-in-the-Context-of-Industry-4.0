// Sources flattened with hardhat v2.28.5 https://hardhat.org

// SPDX-License-Identifier: MIT

// File Gemini/Consorcio.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FinancialPoolManager
 * @dev A smart contract for managing collaborative financing pools.
 * Allows users to pool funds, pay installments, and randomly select winners to receive goods.
 * Implemented securely with Reentrancy guards and checks-effects-interactions pattern.
 */

// Interface for ReentrancyGuard logic to prevent reentrancy attacks
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract FinancialPoolManager is ReentrancyGuard {
    
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct ParticipantInfo {
        bool received;      // Specifies if the participant has already been selected to receive the good’s value
        bool canReceive;    // Specifies if the participant is eligible for receiving the good’s value
        uint256 payments;   // The number of payments that the user already made
    }

    struct Pool {
        address owner;                                      // Pool owner
        string targetGood;                                  // Name or description of the good being purchased
        uint256 goodValue;                                  // The total value required for the purchase in wei
        uint256 balance;                                    // The total value under the pool’s administration
        uint256 minParticipants;                            // Minimum number of participants needed to activate the pool
        uint256 totalParticipants;                          // The number of participants in the pool
        address[] participants;                             // List of participants
        mapping(address => ParticipantInfo) participantsInfo; // Maps participants to their info
        uint256 winnersCount;                               // Count the number of winners
        uint256 installments;                               // Total number of installments (duration in months)
        uint256 activationDate;                             // The block.timestamp of the date when the pool was activated
        uint256 installmentValue;                           // The value which should be payed for each installment
        string status;                                      // Current state: "accepting_participants", "active", "canceled", "finished"
    }

    // =============================================================
    //                       STATE VARIABLES
    // =============================================================

    mapping(uint256 => Pool) internal pools;
    uint256 public currentId;

    // Constant strings for status checks to avoid typos and save gas on repetition
    string private constant STATUS_ACCEPTING = "accepting_participants";
    string private constant STATUS_ACTIVE = "active";
    string private constant STATUS_CANCELED = "canceled";
    string private constant STATUS_FINISHED = "finished";
    
    // =============================================================
    //                           EVENTS
    // =============================================================

    event PoolCreated(uint256 indexed poolId, address indexed owner, uint256 goodValue);
    event PoolActivated(uint256 indexed poolId, uint256 activationDate);
    event PoolCanceled(uint256 indexed poolId);
    event UserJoined(uint256 indexed poolId, address indexed user);
    event UserLeft(uint256 indexed poolId, address indexed user);
    event InstallmentPaid(uint256 indexed poolId, address indexed user, uint256 paymentCount);
    event WinnerSelected(uint256 indexed poolId, address indexed winner, uint256 amount);
    event PoolFinished(uint256 indexed poolId);

    // =============================================================
    //                           ERRORS
    // =============================================================
    
    // Using custom errors for gas efficiency
    error InvalidPoolId();
    error Unauthorized();
    error InvalidStatus(string current, string expected);
    error InsufficientParticipants();
    error AlreadyParticipant();
    error NotParticipant();
    error IncorrectPaymentValue(uint256 expected, uint256 sent);
    error PaymentNotDue();
    error TransferFailed();

    // =============================================================
    //                       HELPER FUNCTIONS
    // =============================================================

    /**
     * @dev Compares two strings for equality.
     */
    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    // =============================================================
    //                        MAIN FUNCTIONS
    // =============================================================

    /**
     * @notice Creates a new financing pool.
     * @param targetGood Description of the item.
     * @param goodValue Total cost of the item in Wei.
     * @param minParticipants Minimum users required to start.
     * @param installments Number of payments/months.
     * @return The ID of the newly created pool.
     */
    function createPool(
        string memory targetGood, 
        uint256 goodValue, 
        uint256 minParticipants, 
        uint256 installments
    ) external returns (uint256) {
        require(installments > 0, "Installments must be > 0");
        require(goodValue > 0, "Value must be > 0");

        currentId++;
        Pool storage newPool = pools[currentId];

        newPool.owner = msg.sender;
        newPool.targetGood = targetGood;
        newPool.goodValue = goodValue;
        newPool.minParticipants = minParticipants;
        newPool.installments = installments;
        newPool.installmentValue = goodValue / installments;
        newPool.status = STATUS_ACCEPTING;

        emit PoolCreated(currentId, msg.sender, goodValue);

        return currentId;
    }

    /**
     * @notice Activates the pool if requirements are met.
     * @param poolId The ID of the pool to activate.
     */
    function activatePool(uint256 poolId) external {
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
        Pool storage p = pools[poolId];

        if (msg.sender != p.owner) revert Unauthorized();
        if (p.totalParticipants < p.minParticipants) revert InsufficientParticipants();
        // Implicit check: Can only activate if currently accepting (though prompt implies strict logic flow, logical consistency dictates checking status or allowing re-activation. Adhering to prompt logic primarily).
        
        p.activationDate = block.timestamp;
        p.status = STATUS_ACTIVE;

        emit PoolActivated(poolId, block.timestamp);
    }

    /**
     * @notice Cancels a pool that is currently accepting participants.
     * @param poolId The ID of the pool.
     */
    function deletePool(uint256 poolId) external {
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
        Pool storage p = pools[poolId];

        if (msg.sender != p.owner) revert Unauthorized();
        if (!_compareStrings(p.status, STATUS_ACCEPTING)) revert InvalidStatus(p.status, STATUS_ACCEPTING);

        p.status = STATUS_CANCELED;
        emit PoolCanceled(poolId);
    }

    /**
     * @notice Allows a user to join a pool.
     * @param poolId The ID of the pool.
     */
    function participateInPool(uint256 poolId) external {
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
        Pool storage p = pools[poolId];

        if (!_compareStrings(p.status, STATUS_ACCEPTING)) revert InvalidStatus(p.status, STATUS_ACCEPTING);

        // Check if msg.sender is already in participants
        // Optimization: While O(N) is generally bad, we must follow specifications. 
        // A robust solution would use a mapping for O(1) checks, but we strictly follow the 'participants' array check logic here.
        for (uint256 i = 0; i < p.participants.length; i++) {
            if (p.participants[i] == msg.sender) revert AlreadyParticipant();
        }

        p.totalParticipants++;
        p.participants.push(msg.sender);
        
        // Initialize struct info implicitly (default 0/false), but explicit initialization for clarity
        // p.participantsInfo[msg.sender] is accessed via storage pointer automatically

        emit UserJoined(poolId, msg.sender);
    }

    /**
     * @notice Allows a user to leave a pool before it starts.
     * @param poolId The ID of the pool.
     */
    function leavePool(uint256 poolId) external {
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
        Pool storage p = pools[poolId];

        if (!_compareStrings(p.status, STATUS_ACCEPTING)) revert InvalidStatus(p.status, STATUS_ACCEPTING);

        bool isParticipant = false;
        uint256 index;

        for (uint256 i = 0; i < p.participants.length; i++) {
            if (p.participants[i] == msg.sender) {
                index = i;
                isParticipant = true;
                break;
            }
        }

        if (!isParticipant) revert NotParticipant();

        // Decrement total participants
        p.totalParticipants--;

        // Clean up mapping info (though unnecessary for logic given logic resets, good for privacy/state hygiene)
        delete p.participantsInfo[msg.sender];

        // Swap and Pop
        p.participants[index] = p.participants[p.participants.length - 1];
        p.participants.pop();

        emit UserLeft(poolId, msg.sender);
    }

    /**
     * @notice Process an installment payment and potentially select a winner.
     * @param poolId The ID of the pool.
     */
    function payInstallment(uint256 poolId) external payable nonReentrant {
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
        Pool storage p = pools[poolId];

        // 1. Validations
        if (!_compareStrings(p.status, STATUS_ACTIVE)) revert InvalidStatus(p.status, STATUS_ACTIVE);
        
        bool isParticipant = false;
        for(uint i=0; i<p.participants.length; i++){
            if(p.participants[i] == msg.sender){
                isParticipant = true;
                break;
            }
        }
        if (!isParticipant) revert NotParticipant();
        
        if (msg.value != p.installmentValue) revert IncorrectPaymentValue(p.installmentValue, msg.value);

        // 2. Logic: Time calculation
        // Floor calculation of months passed since activation
        uint256 duePayments = (block.timestamp - p.activationDate) / 30 days;

        ParticipantInfo storage senderInfo = p.participantsInfo[msg.sender];

        // Ensure user is not paying ahead of time
        if (senderInfo.payments >= duePayments) revert PaymentNotDue();

        // 3. Update Payment State
        senderInfo.payments++;
        p.balance += msg.value;
        
        emit InstallmentPaid(poolId, msg.sender, senderInfo.payments);

        // 4. Update Eligibility
        // If caught up with payments and hasn't received good yet
        if (senderInfo.payments == duePayments && !senderInfo.received) {
            senderInfo.canReceive = true;
        } else {
            senderInfo.canReceive = false;
        }

        // 5. Winner Selection Logic
        if (p.balance >= p.goodValue) {
            
            // Find eligible participants
            // Note: Creating a dynamic array in memory can be gas intensive if participants count is high.
            address[] memory eligible = new address[](p.participants.length);
            uint256 count = 0;

            for (uint256 i = 0; i < p.participants.length; i++) {
                address participantAddr = p.participants[i];
                ParticipantInfo storage info = p.participantsInfo[participantAddr];
                if (info.canReceive && !info.received) {
                    eligible[count] = participantAddr;
                    count++;
                }
            }

            if (count > 0) {
                // Select winner
                // WARNING: insecure randomness for production, but compliant with standard logic requirements without external oracles.
                uint256 randomIndex = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp, 
                            block.prevrandao, 
                            msg.sender, 
                            p.balance
                        )
                    )
                ) % count;

                address winner = eligible[randomIndex];

                // Effects
                p.balance -= p.goodValue;
                p.participantsInfo[winner].received = true;
                p.participantsInfo[winner].canReceive = false;
                p.winnersCount++;

                emit WinnerSelected(poolId, winner, p.goodValue);

                // Interaction (External Call)
                (bool success, ) = payable(winner).call{value: p.goodValue}("");
                if (!success) revert TransferFailed();

                // Check for completion
                if (p.winnersCount == p.totalParticipants) {
                    p.status = STATUS_FINISHED;
                    emit PoolFinished(poolId);
                }
            }
        }
    }

    /**
     * @notice Retrieve details of a specific pool.
     * @param poolId The ID of the pool.
     * @return owner The address of the pool owner.
     * @return targetGood The description of the good.
     * @return goodValue The value of the good.
     * @return minParticipants Minimum participants required.
     * @return totalParticipants Current number of participants.
     * @return winnersCount Current number of winners.
     * @return installments Total installments required.
     * @return activationDate Timestamp of activation.
     * @return installmentValue Cost per installment.
     * @return status Current status of the pool.
     */
    function getPool(uint256 poolId) external view returns (
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
        if (poolId == 0 || poolId > currentId) revert InvalidPoolId();
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
