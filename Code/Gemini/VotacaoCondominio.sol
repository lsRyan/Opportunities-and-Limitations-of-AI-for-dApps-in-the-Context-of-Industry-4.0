// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CondoVotingSystem
 * @dev A voting system for condominium property owners using ERC20Votes for governance.
 * Allows proposal creation, voting with weight based on token holdings, and administration by an owner.
 */
contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // =============================================================
    //                           STRUCTS
    // =============================================================

    struct Proposal {
        address proposer;
        uint48 voteStart;
        // Maps each token owner to whether they have voted
        mapping(address => bool) voted;
        // Maps each token owner to their vote (true = approve, false = reject)
        mapping(address => bool) votes;
        uint256 approvePower;
        uint256 rejectPower;
        string status; // "UnderDeliberation", "Voting", "Approved", "Rejected", "Canceled"
        string description;
        uint256 budget;
    }

    // =============================================================
    //                       STATE VARIABLES
    // =============================================================

    // Mapping proposal ID to the Proposal struct
    mapping(uint256 => Proposal) private proposals;

    // Configuration
    uint256 private voteTimeout; // in seconds (derived from days)
    uint256 private voteQuorum;  // Percentage (0-100)
    uint256 private currentId;   // Latest proposal ID

    // =============================================================
    //                           EVENTS
    // =============================================================

    event ProposalCreated(uint256 indexed id, address indexed proposer, string description);
    event ProposalStatusChanged(uint256 indexed id, string newStatus);
    event Voted(uint256 indexed id, address indexed voter, bool approve, uint256 power);
    event VoteConfigChanged(string param, uint256 newValue);

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /**
     * @notice Initializes the contract, mints tokens to owners, and sets defaults.
     * @param amount Total amount of tokens to mint.
     * @param tokenOwners List of addresses to receive one token each.
     */
    constructor(uint256 amount, address[] memory tokenOwners)
        ERC20("Assembleia", "ASS")
        ERC20Permit("Assembleia")
        Ownable(msg.sender)
    {
        require(amount >= tokenOwners.length, "Amount must be >= number of owners");

        // Mint 1 token to each owner and delegate power
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            _mint(tokenOwners[i], 1 ether); // Assuming 18 decimals, 1 full token
            // Delegate voting power to self to activate checkpoints immediately
            _delegate(tokenOwners[i], tokenOwners[i]);
        }

        // Mint remaining tokens to contract owner (msg.sender)
        uint256 remaining = amount - tokenOwners.length;
        if (remaining > 0) {
            _mint(msg.sender, remaining * 1 ether);
            _delegate(msg.sender, msg.sender);
        }

        // Set defaults
        voteTimeout = 1 days;
        voteQuorum = 70;
        currentId = 0;
    }

    // =============================================================
    //                     STANDARD OVERRIDES
    // =============================================================

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    // =============================================================
    //                      CUSTOM FUNCTIONS
    // =============================================================

    /**
     * @notice Creates a new proposal.
     * @param description Text description of the proposal.
     * @param budget Budget in wei required.
     * @return The ID of the new proposal.
     */
    function propose(string memory description, uint256 budget) external returns (uint256) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to propose");

        currentId++;
        uint256 newId = currentId;

        Proposal storage p = proposals[newId];
        p.proposer = msg.sender;
        p.status = "UnderDeliberation";
        p.description = description;
        p.budget = budget;
        // Voting power maps are initialized empty by default

        emit ProposalCreated(newId, msg.sender, description);
        return newId;
    }

    /**
     * @notice Cancels a proposal that is still under deliberation.
     * @param id The proposal ID.
     */
    function cancelProposal(uint256 id) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        
        Proposal storage p = proposals[id];
        
        require(msg.sender == p.proposer, "Only proposer can cancel");
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("UnderDeliberation")), 
            "Status must be UnderDeliberation"
        );

        p.status = "Canceled";
        emit ProposalStatusChanged(id, "Canceled");
    }

    /**
     * @notice Modifies a proposal that is still under deliberation.
     * @param id The proposal ID.
     * @param newDescription Updated description.
     * @param newBudget Updated budget.
     */
    function modifyProposal(uint256 id, string memory newDescription, uint256 newBudget) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens");
        require(id > 0 && id <= currentId, "Invalid proposal ID");

        Proposal storage p = proposals[id];

        require(msg.sender == p.proposer, "Only proposer can modify");
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("UnderDeliberation")), 
            "Status must be UnderDeliberation"
        );

        p.description = newDescription;
        p.budget = newBudget;
    }

    /**
     * @notice Opens a proposal for voting. Only callable by contract owner.
     * @param id The proposal ID.
     */
    function openVoting(uint256 id) external onlyOwner {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        
        Proposal storage p = proposals[id];
        
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("UnderDeliberation")), 
            "Status must be UnderDeliberation"
        );

        p.status = "Voting";
        p.voteStart = clock();

        emit ProposalStatusChanged(id, "Voting");
    }

    /**
     * @notice Casts a vote on an active proposal.
     * @param id The proposal ID.
     * @param approve True to approve, False to reject.
     * @return The recorded vote boolean.
     */
    function voteOnProposal(uint256 id, bool approve) external returns (bool) {
        require(msg.sender != owner(), "Owner cannot vote");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        
        Proposal storage p = proposals[id];
        
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("Voting")), 
            "Proposal not in Voting stage"
        );

        // Snapshot voting power retrieval
        uint256 votePower = getPastVotes(msg.sender, p.voteStart);
        require(votePower > 0, "No voting power at start time");

        require((clock() - p.voteStart) <= voteTimeout, "Voting timeout reached");

        if (!p.voted[msg.sender]) {
            // First time voting
            if (approve) {
                p.approvePower += votePower;
            } else {
                p.rejectPower += votePower;
            }
            p.voted[msg.sender] = true;
            p.votes[msg.sender] = approve;
        } else {
            // Changing vote
            bool previousVote = p.votes[msg.sender];
            
            // Logic explicitly requested: verify current vote state matches prompt logic
            if (previousVote == true && approve == false) {
                // Was Approve, changing to Reject
                p.approvePower -= votePower;
                p.rejectPower += votePower;
                p.votes[msg.sender] = false;
            } else if (previousVote == false && approve == true) {
                // Was Reject, changing to Approve
                p.rejectPower -= votePower;
                p.approvePower += votePower;
                p.votes[msg.sender] = true;
            }
            // If previousVote == approve, no change in power needed
        }

        emit Voted(id, msg.sender, p.votes[msg.sender], votePower);
        return p.votes[msg.sender];
    }

    /**
     * @notice Finalizes the vote. Can be called if timeout passed OR if quorum reached (by owner).
     * @param id The proposal ID.
     * @return The final status string.
     */
    function endVote(uint256 id) external returns (string memory) {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        
        Proposal storage p = proposals[id];
        
        require(
            keccak256(bytes(p.status)) == keccak256(bytes("Voting")), 
            "Proposal not in Voting stage"
        );

        uint256 timeElapsed = clock() - p.voteStart;
        bool timeoutPassed = (balanceOf(msg.sender) > 0 && timeElapsed > voteTimeout);
        
        // Calculate quorum percentage.
        // Formula: ((approve + reject) * 100) / (totalSupply - ownerVotes)
        uint256 ownerVotesAtStart = getPastVotes(owner(), p.voteStart);
        uint256 eligibleSupply = totalSupply() - ownerVotesAtStart;
        
        // Prevent division by zero if eligible supply is somehow 0
        uint256 currentParticipation = 0;
        if (eligibleSupply > 0) {
            currentParticipation = ((p.approvePower + p.rejectPower) * 100) / eligibleSupply;
        }

        bool quorumReachedAndOwner = (msg.sender == owner() && currentParticipation >= voteQuorum);

        require(timeoutPassed || quorumReachedAndOwner, "Cannot end vote yet");

        if (p.approvePower > p.rejectPower) {
            p.status = "Approved";
        } else {
            p.status = "Rejected";
        }

        emit ProposalStatusChanged(id, p.status);
        return p.status;
    }

    /**
     * @notice Updates the voting window duration.
     * @param newTimeout New timeout duration in seconds (or days format).
     */
    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
        emit VoteConfigChanged("Timeout", newTimeout);
    }

    /**
     * @notice Updates the percentage required to close a vote early.
     * @param newQuorum New quorum percentage (0-100).
     */
    function changeQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Quorum cannot exceed 100%");
        voteQuorum = newQuorum;
        emit VoteConfigChanged("Quorum", newQuorum);
    }

    /**
     * @notice Retrieves details of a specific proposal.
     * @param id The proposal ID.
     * @return proposer The address of the proposer.
     * @return voteStart Timestamp when voting started.
     * @return status Current status string.
     * @return description Description of the proposal.
     * @return budget Budget required.
     */
    function getProposal(uint256 id) external view returns (
        address proposer, 
        uint48 voteStart, 
        string memory status, 
        string memory description, 
        uint256 budget
    ) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens");
        require(id > 0 && id <= currentId, "Invalid proposal ID");

        Proposal storage p = proposals[id];
        return (p.proposer, p.voteStart, p.status, p.description, p.budget);
    }
}