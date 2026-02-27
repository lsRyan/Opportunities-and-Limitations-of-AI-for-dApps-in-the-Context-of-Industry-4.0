// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";

/**
 * @title CondoVotingSystem
 * @dev A governance token contract for condominium voting with proposal management.
 * Implements ERC20Votes for snapshot-based voting power and ERC20Permit for gasless approvals.
 */
contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
    
    /// @dev Struct representing a proposal in the voting system
    struct Proposal {
        address proposer;                      // Address of the proposal creator
        uint48 voteStart;                      // Timestamp when voting started
        mapping(address => bool) voted;        // Tracks if an address has voted
        mapping(address => bool) votes;        // Tracks the vote choice (true = approve, false = reject)
        uint256 approvePower;                  // Total voting power approving the proposal
        uint256 rejectPower;                   // Total voting power rejecting the proposal
        string status;                         // Current status of the proposal
        string description;                    // Description of the proposal
        uint256 budget;                        // Budget required in wei
    }

    /// @dev Mapping from proposal ID to Proposal struct
    mapping(uint256 => Proposal) private proposals;
    
    /// @dev Maximum voting time in seconds (defaults to 1 day)
    uint256 private voteTimeout = 1 days;
    
    /// @dev Minimum percentage of token holders required for early vote closure (defaults to 70%)
    uint256 private voteQuorum = 70;
    
    /// @dev Counter for proposal IDs
    uint256 private currentId;

    /**
     * @dev Constructor that mints tokens and distributes them to initial owners
     * @param amount Total number of tokens to mint
     * @param tokenOwners Array of addresses to receive one token each
     */
    constructor(
        uint256 amount, 
        address[] memory tokenOwners
    ) 
        ERC20("Assembleia", "ASS") 
        ERC20Permit("Assembleia") 
        Ownable(msg.sender) 
    {
        require(amount >= tokenOwners.length, "Insufficient tokens for all owners");
        
        // Mint total supply to this contract first
        _mint(address(this), amount);
        
        // Distribute one token to each owner and delegate voting power
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            _transfer(address(this), tokenOwners[i], 1);
            _delegate(tokenOwners[i], tokenOwners[i]);
        }
        
        // Transfer remaining tokens to contract owner if any
        uint256 remaining = amount - tokenOwners.length;
        if (remaining > 0) {
            _transfer(address(this), msg.sender, remaining);
        }
    }

    /**
     * @dev Creates a new proposal
     * @param description Description of the proposal
     * @param budget Budget required for the proposal in wei
     * @return uint256 The ID of the created proposal
     */
    function propose(string memory description, uint256 budget) external returns (uint256) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to propose");
        
        currentId++;
        
        Proposal storage newProposal = proposals[currentId];
        newProposal.proposer = msg.sender;
        newProposal.status = "UnderDeliberation";
        newProposal.description = description;
        newProposal.budget = budget;
        
        return currentId;
    }

    /**
     * @dev Cancels a proposal that is under deliberation
     * @param id The proposal ID to cancel
     */
    function cancelProposal(uint256 id) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to cancel");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(msg.sender == proposals[id].proposer, "Only proposer can cancel");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")),
            "Can only cancel proposals under deliberation"
        );
        
        proposals[id].status = "Canceled";
    }

    /**
     * @dev Modifies an existing proposal under deliberation
     * @param id The proposal ID to modify
     * @param newDescription New description for the proposal
     * @param newBudget New budget for the proposal
     */
    function modifyProposal(
        uint256 id, 
        string memory newDescription, 
        uint256 newBudget
    ) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to modify");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(msg.sender == proposals[id].proposer, "Only proposer can modify");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")),
            "Can only modify proposals under deliberation"
        );
        
        proposals[id].description = newDescription;
        proposals[id].budget = newBudget;
    }

    /**
     * @dev Opens voting for a proposal (only owner)
     * @param id The proposal ID to open for voting
     */
    function openVoting(uint256 id) external onlyOwner {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")),
            "Proposal must be under deliberation"
        );
        
        proposals[id].status = "Voting";
        proposals[id].voteStart = clock();
    }

    /**
     * @dev Cast or change a vote on a proposal
     * @param id The proposal ID to vote on
     * @param approve True to approve, false to reject
     * @return bool The final vote of the caller
     */
    function voteOnProposal(uint256 id, bool approve) external returns (bool) {
        require(msg.sender != owner(), "Owner cannot vote");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("Voting")),
            "Proposal is not open for voting"
        );
        
        uint256 votePower = getPastVotes(msg.sender, proposals[id].voteStart);
        require(votePower > 0, "No voting power at proposal start");
        require(
            clock() - proposals[id].voteStart <= voteTimeout,
            "Voting period has ended"
        );
        
        Proposal storage proposal = proposals[id];
        
        // First time voting
        if (!proposal.voted[msg.sender]) {
            if (approve) {
                proposal.approvePower += votePower;
            } else {
                proposal.rejectPower += votePower;
            }
            proposal.voted[msg.sender] = true;
        } 
        // Changing vote
        else {
            // Was approve, now reject
            if (proposal.votes[msg.sender] && !approve) {
                proposal.approvePower -= votePower;
                proposal.rejectPower += votePower;
            }
            // Was reject, now approve
            else if (!proposal.votes[msg.sender] && approve) {
                proposal.rejectPower -= votePower;
                proposal.approvePower += votePower;
            }
        }
        
        proposal.votes[msg.sender] = approve;
        return proposal.votes[msg.sender];
    }

    /**
     * @dev Ends voting for a proposal and determines the outcome
     * @param id The proposal ID to end voting for
     * @return string The final status of the proposal
     */
    function endVote(uint256 id) external returns (string memory) {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("Voting")),
            "Proposal is not being voted on"
        );
        
        Proposal storage proposal = proposals[id];
        bool canEnd = false;
        
        // Token holders can end after timeout
        if (balanceOf(msg.sender) > 0 && clock() - proposal.voteStart > voteTimeout) {
            canEnd = true;
        }
        
        // Owner can end early if quorum is reached
        if (msg.sender == owner()) {
            uint256 ownerVotePower = getPastVotes(owner(), proposal.voteStart);
            uint256 eligibleSupply = totalSupply() - ownerVotePower;
            uint256 participationPercentage = ((proposal.approvePower + proposal.rejectPower) * 100) / eligibleSupply;
            
            if (participationPercentage >= voteQuorum) {
                canEnd = true;
            }
        }
        
        require(canEnd, "Conditions to end vote not met");
        
        // Determine outcome
        if (proposal.approvePower > proposal.rejectPower) {
            proposal.status = "Approved";
        } else {
            proposal.status = "Rejected";
        }
        
        return proposal.status;
    }

    /**
     * @dev Changes the voting timeout period (only owner)
     * @param newTimeout New timeout in seconds
     */
    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
    }

    /**
     * @dev Changes the quorum percentage (only owner)
     * @param newQuorum New quorum percentage (0-100)
     */
    function changeQuorum(uint256 newQuorum) external onlyOwner {
        voteQuorum = newQuorum;
    }

    /**
     * @dev Retrieves proposal details
     * @param id The proposal ID to query
     * @return proposer Address of the proposer
     * @return voteStart Timestamp when voting started
     * @return status Current status of the proposal
     * @return description Description of the proposal
     * @return budget Budget required for the proposal
     */
    function getProposal(uint256 id) external view returns (
        address proposer,
        uint48 voteStart,
        string memory status,
        string memory description,
        uint256 budget
    ) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to view proposals");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        
        Proposal storage proposal = proposals[id];
        return (
            proposal.proposer,
            proposal.voteStart,
            proposal.status,
            proposal.description,
            proposal.budget
        );
    }

    /**
     * @dev Returns the current block timestamp as a uint48
     * @return uint48 Current timestamp
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Returns the clock mode (timestamp-based)
     * @return string Clock mode descriptor
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Internal function to update token balances and voting power
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param value Amount of tokens transferred
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Returns the current nonce for an address
     * @param owner Address to query nonce for
     * @return uint256 Current nonce
     */
    function nonces(address owner) 
        public 
        view 
        override(ERC20Permit, Nonces) 
        returns (uint256) 
    {
        return super.nonces(owner);
    }
}