// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
    // Struct to represent a proposal
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

    // State variables
    mapping(uint256 => Proposal) private proposals;
    uint256 private voteTimeout = 1 days; // Default: 1 day in seconds
    uint256 private voteQuorum = 70; // Default: 70%
    uint256 private currentId = 0;

    // Events for transparency
    event ProposalCreated(uint256 indexed id, address indexed proposer, string description, uint256 budget);
    event ProposalModified(uint256 indexed id, string newDescription, uint256 newBudget);
    event ProposalCanceled(uint256 indexed id);
    event VotingStarted(uint256 indexed id, uint48 startTime);
    event Voted(uint256 indexed id, address indexed voter, bool vote, uint256 power);
    event VotingEnded(uint256 indexed id, string status);
    event VotingTimeoutChanged(uint256 newTimeout);
    event QuorumChanged(uint256 newQuorum);

    // Error messages
    error InvalidProposalId();
    error NotTokenHolder();
    error NotProposer();
    error InvalidProposalStatus();
    error VotingPeriodActive();
    error VotingPeriodEnded();
    error OwnerCannotVote();
    error InsufficientVotingPower();
    error QuorumNotMet();
    error InvalidAmount();
    error OnlyOwnerEarlyClosure();

    /**
     * @dev Constructor to initialize the token and distribute initial tokens
     * @param amount Total number of tokens to mint
     * @param tokenOwners Array of addresses to receive one token each
     */
    constructor(
        uint256 amount,
        address[] memory tokenOwners
    ) ERC20("Assembleia", "ASS") ERC20Permit("Assembleia") Ownable(msg.sender) {
        if (amount < tokenOwners.length) revert InvalidAmount();

        // Mint total supply
        _mint(address(this), amount);

        // Distribute one token to each owner and delegate voting power
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            _transfer(address(this), tokenOwners[i], 1);
            _delegate(tokenOwners[i], tokenOwners[i]);
        }

        // Transfer remaining tokens to contract owner
        uint256 remaining = amount - tokenOwners.length;
        if (remaining > 0) {
            _transfer(address(this), msg.sender, remaining);
            _delegate(msg.sender, msg.sender);
        }
    }

    /**
     * @dev Returns the current timestamp as the clock
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @dev Returns the clock mode
     */
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Override _update to update votes when tokens are transferred
     */
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /**
     * @dev Returns the nonce for permit functionality
     */
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @dev Creates a new proposal
     * @param description Description of the proposal
     * @param budget Expected budget in wei
     * @return Proposal ID
     */
    function propose(string memory description, uint256 budget) external returns (uint256) {
        if (balanceOf(msg.sender) == 0) revert NotTokenHolder();

        currentId++;
        Proposal storage newProposal = proposals[currentId];
        
        newProposal.proposer = msg.sender;
        newProposal.status = "UnderDeliberation";
        newProposal.description = description;
        newProposal.budget = budget;

        emit ProposalCreated(currentId, msg.sender, description, budget);
        return currentId;
    }

    /**
     * @dev Cancels a proposal (only by proposer during deliberation)
     * @param id Proposal ID
     */
    function cancelProposal(uint256 id) external {
        if (balanceOf(msg.sender) == 0) revert NotTokenHolder();
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        
        if (msg.sender != proposal.proposer) revert NotProposer();
        if (!_compareStrings(proposal.status, "UnderDeliberation")) revert InvalidProposalStatus();

        proposal.status = "Canceled";
        emit ProposalCanceled(id);
    }

    /**
     * @dev Modifies an existing proposal (only by proposer during deliberation)
     * @param id Proposal ID
     * @param newDescription New description
     * @param newBudget New budget
     */
    function modifyProposal(uint256 id, string memory newDescription, uint256 newBudget) external {
        if (balanceOf(msg.sender) == 0) revert NotTokenHolder();
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        
        if (msg.sender != proposal.proposer) revert NotProposer();
        if (!_compareStrings(proposal.status, "UnderDeliberation")) revert InvalidProposalStatus();

        proposal.description = newDescription;
        proposal.budget = newBudget;

        emit ProposalModified(id, newDescription, newBudget);
    }

    /**
     * @dev Starts voting on a proposal (only by owner)
     * @param id Proposal ID
     */
    function openVoting(uint256 id) external onlyOwner {
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        
        if (!_compareStrings(proposal.status, "UnderDeliberation")) revert InvalidProposalStatus();

        proposal.status = "Voting";
        proposal.voteStart = clock();

        emit VotingStarted(id, proposal.voteStart);
    }

    /**
     * @dev Cast a vote on a proposal
     * @param id Proposal ID
     * @param approve True for approve, false for reject
     * @return The voter's final vote
     */
    function voteOnProposal(uint256 id, bool approve) external returns (bool) {
        if (msg.sender == owner()) revert OwnerCannotVote();
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        
        if (!_compareStrings(proposal.status, "Voting")) revert InvalidProposalStatus();
        
        uint256 votePower = getPastVotes(msg.sender, proposal.voteStart);
        if (votePower == 0) revert InsufficientVotingPower();
        
        if (clock() - proposal.voteStart > voteTimeout) revert VotingPeriodEnded();

        if (!proposal.voted[msg.sender]) {
            // First time voting
            if (approve) {
                proposal.approvePower += votePower;
            } else {
                proposal.rejectPower += votePower;
            }
            proposal.voted[msg.sender] = true;
        } else {
            // Changing vote
            if (proposal.votes[msg.sender] && !approve) {
                // Changing from approve to reject
                proposal.approvePower -= votePower;
                proposal.rejectPower += votePower;
            } else if (!proposal.votes[msg.sender] && approve) {
                // Changing from reject to approve
                proposal.rejectPower -= votePower;
                proposal.approvePower += votePower;
            }
            // If voting the same way again, nothing changes
        }

        proposal.votes[msg.sender] = approve;
        
        emit Voted(id, msg.sender, approve, votePower);
        return proposal.votes[msg.sender];
    }

    /**
     * @dev Ends voting on a proposal
     * @param id Proposal ID
     * @return Final status of the proposal
     */
    function endVote(uint256 id) external returns (string memory) {
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        
        if (!_compareStrings(proposal.status, "Voting")) revert InvalidProposalStatus();

        bool canEnd = false;
        
        // Condition 1: Any token holder can end after timeout
        if (balanceOf(msg.sender) > 0 && (clock() - proposal.voteStart) > voteTimeout) {
            canEnd = true;
        }
        
        // Condition 2: Owner can end early if quorum is reached
        if (msg.sender == owner()) {
            uint256 totalVotingPower = totalSupply() - getPastVotes(owner(), proposal.voteStart);
            uint256 votedPower = proposal.approvePower + proposal.rejectPower;
            uint256 quorumPercentage = (votedPower * 100) / totalVotingPower;
            
            if (quorumPercentage >= voteQuorum) {
                canEnd = true;
            } else {
                revert QuorumNotMet();
            }
        }

        if (!canEnd) revert OnlyOwnerEarlyClosure();

        // Determine result
        if (proposal.approvePower > proposal.rejectPower) {
            proposal.status = "Approved";
        } else {
            proposal.status = "Rejected";
        }

        emit VotingEnded(id, proposal.status);
        return proposal.status;
    }

    /**
     * @dev Changes the voting timeout (only by owner)
     * @param newTimeout New timeout in seconds
     */
    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
        emit VotingTimeoutChanged(newTimeout);
    }

    /**
     * @dev Changes the quorum percentage (only by owner)
     * @param newQuorum New quorum percentage (0-100)
     */
    function changeQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Quorum cannot exceed 100%");
        voteQuorum = newQuorum;
        emit QuorumChanged(newQuorum);
    }

    /**
     * @dev Retrieves proposal details
     * @param id Proposal ID
     * @return proposer Proposal's proposer 
     * @return voteStart Timestamp in which the vote started
     * @return status Current status
     * @return description Proposal's description
     * @return budget Proposal's budget
     */
    function getProposal(
        uint256 id
    ) external view returns (address proposer, uint48 voteStart, string memory status, string memory description, uint256 budget) {
        if (balanceOf(msg.sender) == 0) revert NotTokenHolder();
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
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
     * @dev Returns proposal voting results
     * @param id Proposal ID
     * @return approvePower Combined vote power of approval votes
     * @return rejectPower Combined vote power of refusal votes
     */
    function getProposalResults(uint256 id) external view returns (uint256 approvePower, uint256 rejectPower) {
        if (id == 0 || id > currentId) revert InvalidProposalId();
        
        Proposal storage proposal = proposals[id];
        return (proposal.approvePower, proposal.rejectPower);
    }

    /**
     * @dev Checks if an address has voted on a proposal
     * @param id Proposal ID
     * @param voter Address to check
     * @return True if voted, false otherwise
     */
    function hasVoted(uint256 id, address voter) external view returns (bool) {
        if (id == 0 || id > currentId) revert InvalidProposalId();
        return proposals[id].voted[voter];
    }

    /**
     * @dev Gets the current vote timeout
     * @return Current voting timeout in seconds
     */
    function getVoteTimeout() external view returns (uint256) {
        return voteTimeout;
    }

    /**
     * @dev Gets the current quorum percentage
     * @return Current quorum percentage
     */
    function getVoteQuorum() external view returns (uint256) {
        return voteQuorum;
    }

    /**
     * @dev Gets the current proposal ID counter
     * @return Current proposal ID
     */
    function getCurrentId() external view returns (uint256) {
        return currentId;
    }

    /**
     * @dev Internal helper to compare strings
     * @param a First string
     * @param b Second string
     * @return True if strings are equal
     */
    function _compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}