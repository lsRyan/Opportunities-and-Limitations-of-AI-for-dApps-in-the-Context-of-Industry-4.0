// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
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

    uint256 private voteTimeout = 1 days;
    uint256 private voteQuorum = 70;
    uint256 private currentId = 0;
    mapping(uint256 => Proposal) private proposals;

    constructor(uint256 amount, address[] memory tokenOwners)
        ERC20("Assembleia", "ASS")
        ERC20Permit("Assembleia")
        Ownable(msg.sender)
    {
        require(amount >= tokenOwners.length, "Not enough tokens for all owners");
        _mint(msg.sender, amount);
        
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            _mint(tokenOwners[i], 1);
            _delegate(tokenOwners[i], tokenOwners[i]);
        }
        
        // Mint remaining tokens to owner
        if (amount > tokenOwners.length) {
            _mint(msg.sender, amount - tokenOwners.length);
        }
    }

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    function propose(string memory description, uint256 budget)
        external
        returns (uint256)
    {
        require(balanceOf(msg.sender) > 0, "Only token holders can propose");
        currentId++;
        proposals[currentId].proposer = msg.sender;
        proposals[currentId].status = "UnderDeliberation";
        proposals[currentId].description = description;
        proposals[currentId].budget = budget;
        
        return currentId;
    }

    function cancelProposal(uint256 id) external {
        require(balanceOf(msg.sender) > 0, "Only token holders can cancel proposals");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(proposals[id].proposer == msg.sender, "Only proposer can cancel");
        require(
            keccak256(abi.encodePacked(proposals[id].status)) == keccak256(abi.encodePacked("UnderDeliberation")),
            "Proposal not under deliberation"
        );
        proposals[id].status = "Canceled";
    }

    function modifyProposal(
        uint256 id,
        string memory newDescription,
        uint256 newBudget
    ) external {
        require(balanceOf(msg.sender) > 0, "Only token holders can modify proposals");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(proposals[id].proposer == msg.sender, "Only proposer can modify");
        require(
            keccak256(abi.encodePacked(proposals[id].status)) == keccak256(abi.encodePacked("UnderDeliberation")),
            "Proposal not under deliberation"
        );
        proposals[id].description = newDescription;
        proposals[id].budget = newBudget;
    }

    function openVoting(uint256 id) external onlyOwner {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(
            keccak256(abi.encodePacked(proposals[id].status)) == keccak256(abi.encodePacked("UnderDeliberation")),
            "Proposal not under deliberation"
        );
        proposals[id].status = "Voting";
        proposals[id].voteStart = clock();
    }

    function voteOnProposal(uint256 id, bool approve) external returns (bool) {
        require(msg.sender != owner(), "Contract owner cannot vote");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(keccak256(abi.encodePacked(proposals[id].status)) == keccak256(abi.encodePacked("Voting")), "Proposal not in voting period");
        require(
            clock() - proposals[id].voteStart <= voteTimeout,
            "Voting period has ended"
        );
        
        uint256 votePower = getPastVotes(msg.sender, proposals[id].voteStart);
        require(votePower > 0, "No voting power");
        
        if (!proposals[id].voted[msg.sender]) {
            if (approve) {
                proposals[id].approvePower += votePower;
            } else {
                proposals[id].rejectPower += votePower;
            }
            proposals[id].voted[msg.sender] = true;
            proposals[id].votes[msg.sender] = approve;
        } else {
            if (proposals[id].votes[msg.sender] && !approve) {
                proposals[id].approvePower -= votePower;
                proposals[id].rejectPower += votePower;
            } else if (!proposals[id].votes[msg.sender] && approve) {
                proposals[id].rejectPower -= votePower;
                proposals[id].approvePower += votePower;
            }
            proposals[id].votes[msg.sender] = approve;
        }
        
        return proposals[id].votes[msg.sender];
    }

    function endVote(uint256 id) external returns (string memory) {
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        require(keccak256(abi.encodePacked(proposals[id].status)) == keccak256(abi.encodePacked("Voting")), "Proposal not in voting period");
        
        bool canEndEarly = (balanceOf(msg.sender) > 0) &&
            (clock() - proposals[id].voteStart > voteTimeout) ||
            (msg.sender == owner() &&
                ((proposals[id].approvePower + proposals[id].rejectPower) * 100) /
                (totalSupply() - getPastVotes(owner(), proposals[id].voteStart)) >= voteQuorum);
        
        require(canEndEarly, "Cannot end vote yet");
        
        if (proposals[id].approvePower > proposals[id].rejectPower) {
            proposals[id].status = "Approved";
        } else {
            proposals[id].status = "Rejected";
        }
        
        return proposals[id].status;
    }

    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
    }

    function changeQuorum(uint256 newQuorum) external onlyOwner {
        voteQuorum = newQuorum;
    }

    function getProposal(uint256 id)
        external
        returns (address, uint48, string memory, string memory, uint256)
    {
        require(balanceOf(msg.sender) > 0, "Only token holders can view proposals");
        require(id > 0 && id <= currentId, "Invalid proposal ID");
        return (
            proposals[id].proposer,
            proposals[id].voteStart,
            proposals[id].status,
            proposals[id].description,
            proposals[id].budget
        );
    }
}
