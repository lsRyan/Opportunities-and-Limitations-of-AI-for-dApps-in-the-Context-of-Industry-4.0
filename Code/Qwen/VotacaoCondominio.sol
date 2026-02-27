// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // Struct representing a proposal
    struct Proposal {
        address proposer;
        uint48 voteStart;
        mapping(address => bool) voted;
        mapping(address => bool) votes;
        uint256 approvePower;
        uint256 rejectPower;
        string status;
        string description;
        uint256 budget;
    }

    // Mapping from proposal ID to Proposal struct
    mapping(uint256 => Proposal) private proposals;

    // Maximum voting time in days
    uint256 private voteTimeout;

    // Minimum percentage of token holders required for early vote closure
    uint256 private voteQuorum;

    // Current proposal ID counter
    uint256 private currentId;

    // Events for logging actions
    event ProposalCreated(uint256 indexed id, address indexed proposer, string description);
    event ProposalCancelled(uint256 indexed id, address indexed proposer);
    event ProposalModified(uint256 indexed id, address indexed proposer);
    event VotingOpened(uint256 indexed id);
    event VoteCast(uint256 indexed id, address indexed voter, bool approve, uint256 votePower);
    event VoteEnded(uint256 indexed id, string result);

    /**
     * @dev Constructor to initialize the contract with initial token distribution
     * @param amount Total number of tokens to mint
     * @param tokenOwners Array of addresses to receive initial tokens
     */
    constructor(uint256 amount, address[] memory tokenOwners) 
        ERC20("Assembleia", "ASS") 
        ERC20Permit("Assembleia") 
        Ownable(msg.sender)
    {
        require(amount >= tokenOwners.length, "Amount must be greater or equal to tokenOwners length");

        // Mint the total supply of tokens
        _mint(address(this), amount);

        // Distribute tokens to the specified addresses
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            _transfer(address(this), tokenOwners[i], 1);
            // Delegate voting power to the token owner
            delegate(tokenOwners[i]);
        }

        // Transfer remaining tokens to the contract owner
        uint256 remainingTokens = amount - tokenOwners.length;
        if (remainingTokens > 0) {
            _transfer(address(this), msg.sender, remainingTokens);
        }

        // Set default values
        voteTimeout = 1; // 1 day default
        voteQuorum = 70; // 70% default
        currentId = 0;
    }

    /**
     * @dev Returns the current block timestamp as clock value
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Returns the clock mode as a string
     */
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Internal function to update balances and voting power
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Returns the current nonce for an owner
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @dev Creates a new proposal
     * @param description Description of the proposal
     * @param budget Budget required for the proposal
     * @return uint256 The ID of the created proposal
     */
    function propose(string memory description, uint256 budget) external returns (uint256) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to propose");
        
        currentId++;
        uint256 id = currentId;
        
        Proposal storage newProposal = proposals[id];
        newProposal.proposer = msg.sender;
        newProposal.status = "UnderDeliberation";
        newProposal.description = description;
        newProposal.budget = budget;
        
        emit ProposalCreated(id, msg.sender, description);
        return id;
    }

    /**
     * @dev Cancels a proposal if it's still under deliberation
     * @param id ID of the proposal to cancel
     */
    function cancelProposal(uint256 id) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to cancel proposal");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(msg.sender == proposals[id].proposer, "Only proposer can cancel");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")), 
            "Proposal is not under deliberation"
        );
        
        proposals[id].status = "Canceled";
        emit ProposalCancelled(id, msg.sender);
    }

    /**
     * @dev Modifies an existing proposal if it's still under deliberation
     * @param id ID of the proposal to modify
     * @param newDescription New description for the proposal
     * @param newBudget New budget for the proposal
     */
    function modifyProposal(uint256 id, string memory newDescription, uint256 newBudget) external {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to modify proposal");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(msg.sender == proposals[id].proposer, "Only proposer can modify");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")), 
            "Proposal is not under deliberation"
        );
        
        proposals[id].description = newDescription;
        proposals[id].budget = newBudget;
        emit ProposalModified(id, msg.sender);
    }

    /**
     * @dev Opens voting for a proposal (only owner can call)
     * @param id ID of the proposal to open voting for
     */
    function openVoting(uint256 id) external onlyOwner {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("UnderDeliberation")), 
            "Proposal is not under deliberation"
        );
        
        proposals[id].status = "Voting";
        proposals[id].voteStart = clock();
        emit VotingOpened(id);
    }

    /**
     * @dev Allows a token holder to vote on a proposal
     * @param id ID of the proposal to vote on
     * @param approve Whether to approve or reject the proposal
     * @return bool The vote cast by the caller
     */
    function voteOnProposal(uint256 id, bool approve) external returns (bool) {
        require(msg.sender != owner(), "Contract owner cannot vote");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("Voting")), 
            "Voting is not active for this proposal"
        );
        
        uint256 votePower = getPastVotes(msg.sender, proposals[id].voteStart);
        require(votePower > 0, "No voting power at start of voting period");
        
        uint256 timeElapsed = clock() - proposals[id].voteStart;
        uint256 timeoutInSeconds = voteTimeout * 1 days;
        require(timeElapsed <= timeoutInSeconds, "Voting period has ended");
        
        Proposal storage proposal = proposals[id];
        
        if (!proposal.voted[msg.sender]) {
            // First vote
            if (approve) {
                proposal.approvePower += votePower;
            } else {
                proposal.rejectPower += votePower;
            }
            
            proposal.voted[msg.sender] = true;
            proposal.votes[msg.sender] = approve;
        } else {
            // Changing vote
            bool previousVote = proposal.votes[msg.sender];
            
            if (previousVote && !approve) {
                // Switching from approve to reject
                proposal.approvePower -= votePower;
                proposal.rejectPower += votePower;
            } else if (!previousVote && approve) {
                // Switching from reject to approve
                proposal.rejectPower -= votePower;
                proposal.approvePower += votePower;
            }
            
            proposal.votes[msg.sender] = approve;
        }
        
        emit VoteCast(id, msg.sender, approve, votePower);
        return proposal.votes[msg.sender];
    }

    /**
     * @dev Ends the voting process for a proposal
     * @param id ID of the proposal to end voting for
     * @return string The final status of the proposal ("Approved" or "Rejected")
     */
    function endVote(uint256 id) external returns (string memory) {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(bytes(proposals[id].status)) == keccak256(bytes("Voting")), 
            "Voting is not active for this proposal"
        );
        
        bool canEndByTime = balanceOf(msg.sender) > 0 && 
                           (clock() - proposals[id].voteStart) > (voteTimeout * 1 days);
        
        uint256 totalActiveVotes = proposals[id].approvePower + proposals[id].rejectPower;
        uint256 totalSupplyExcludingOwner = totalSupply() - getPastVotes(owner(), proposals[id].voteStart);
        
        bool canEndByQuorum = false;
        if (totalSupplyExcludingOwner > 0) {
            uint256 participationPercentage = (totalActiveVotes * 100) / totalSupplyExcludingOwner;
            canEndByQuorum = msg.sender == owner() && participationPercentage >= voteQuorum;
        }
        
        require(canEndByTime || canEndByQuorum, "Cannot end vote yet");
        
        if (proposals[id].approvePower > proposals[id].rejectPower) {
            proposals[id].status = "Approved";
        } else {
            proposals[id].status = "Rejected";
        }
        
        emit VoteEnded(id, proposals[id].status);
        return proposals[id].status;
    }

    /**
     * @dev Changes the voting timeout period (only owner can call)
     * @param newTimeout New timeout value in days
     */
    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
    }

    /**
     * @dev Changes the voting quorum percentage (only owner can call)
     * @param newQuorum New quorum percentage
     */
    function changeQuorum(uint256 newQuorum) external onlyOwner {
        voteQuorum = newQuorum;
    }

    /**
     * @dev Retrieves information about a proposal
     * @param id ID of the proposal to retrieve
     * @return address Proposer address
     * @return uint48 Start time of voting
     * @return string Status of the proposal
     * @return string Description of the proposal
     * @return uint256 Budget required for the proposal
     */
    function getProposal(uint256 id) external view returns (
        address,
        uint48,
        string memory,
        string memory,
        uint256
    ) {
        require(balanceOf(msg.sender) > 0, "Must hold tokens to view proposal");
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
}