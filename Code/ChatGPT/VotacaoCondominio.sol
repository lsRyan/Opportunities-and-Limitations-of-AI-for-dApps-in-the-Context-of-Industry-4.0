// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title CondoVotingSystem
 * @author —
 * @notice ERC20-based condominium voting system using OpenZeppelin governance primitives.
 * @dev Voting power is derived from ERC20Votes snapshots (timestamp-based).
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CondoVotingSystem is ERC20, ERC20Permit, ERC20Votes, Ownable {
    /* -------------------------------------------------------------------------- */
    /*                                   STRUCTS                                  */
    /* -------------------------------------------------------------------------- */

    struct Proposal {
        address proposer;
        uint48 voteStart;
        mapping(address => bool) voted;
        mapping(address => bool) votes;
        uint256 approvePower;
        uint256 rejectPower;
        string status; // UnderDeliberation, Voting, Approved, Rejected, Canceled
        string description;
        uint256 budget;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 STATE VARS                                 */
    /* -------------------------------------------------------------------------- */

    mapping(uint256 => Proposal) private proposals;
    uint256 private voteTimeout; // in seconds
    uint256 private voteQuorum;  // percentage (0–100)
    uint256 private currentId;

    /* -------------------------------------------------------------------------- */
    /*                                CONSTRUCTOR                                 */
    /* -------------------------------------------------------------------------- */

    constructor(
        uint256 amount,
        address[] memory tokenOwners
    )
        ERC20("Assembleia", "ASS")
        ERC20Permit("Assembleia")
        Ownable(msg.sender)
    {
        require(amount >= tokenOwners.length, "Insufficient amount");

        // Mint total supply to this contract first
        _mint(address(this), amount);

        // Distribute one token per owner and delegate
        for (uint256 i = 0; i < tokenOwners.length; i++) {
            address ownerAddr = tokenOwners[i];
            _transfer(address(this), ownerAddr, 1);
            _delegate(ownerAddr, ownerAddr);
        }

        // Remaining tokens go to contract owner
        uint256 remaining = amount - tokenOwners.length;
        if (remaining > 0) {
            _transfer(address(this), msg.sender, remaining);
            _delegate(msg.sender, msg.sender);
        }

        voteTimeout = 1 days;
        voteQuorum = 70;
        currentId = 0;
    }

    /* -------------------------------------------------------------------------- */
    /*                          ERC20 / ERC20Votes OVERRIDES                      */
    /* -------------------------------------------------------------------------- */

    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(
        address owner_
    )
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner_);
    }

    /* -------------------------------------------------------------------------- */
    /*                              PROPOSAL LOGIC                                */
    /* -------------------------------------------------------------------------- */

    function propose(
        string memory description,
        uint256 budget
    ) external returns (uint256) {
        require(balanceOf(msg.sender) > 0, "Not a token holder");

        currentId += 1;
        Proposal storage p = proposals[currentId];

        p.proposer = msg.sender;
        p.status = "UnderDeliberation";
        p.description = description;
        p.budget = budget;

        return currentId;
    }

    function cancelProposal(uint256 id) external {
        require(balanceOf(msg.sender) > 0, "Not a token holder");
        require(id > 0 && id <= currentId, "Invalid proposal");
        Proposal storage p = proposals[id];

        require(msg.sender == p.proposer, "Not proposer");
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("UnderDeliberation")),
            "Cannot cancel"
        );

        p.status = "Canceled";
    }

    function modifyProposal(
        uint256 id,
        string memory newDescription,
        uint256 newBudget
    ) external {
        require(balanceOf(msg.sender) > 0, "Not a token holder");
        require(id > 0 && id <= currentId, "Invalid proposal");
        Proposal storage p = proposals[id];

        require(msg.sender == p.proposer, "Not proposer");
        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("UnderDeliberation")),
            "Cannot modify"
        );

        p.description = newDescription;
        p.budget = newBudget;
    }

    function openVoting(uint256 id) external onlyOwner {
        require(id > 0 && id <= currentId, "Invalid proposal");
        Proposal storage p = proposals[id];

        require(
            keccak256(bytes(p.status)) ==
                keccak256(bytes("UnderDeliberation")),
            "Wrong status"
        );

        p.status = "Voting";
        p.voteStart = clock();
    }

    function voteOnProposal(
        uint256 id,
        bool approve
    ) external returns (bool) {
        require(msg.sender != owner(), "Owner cannot vote");
        require(id > 0 && id <= currentId, "Invalid proposal");

        Proposal storage p = proposals[id];

        require(
            keccak256(bytes(p.status)) == keccak256(bytes("Voting")),
            "Voting not open"
        );

        uint256 votePower = getPastVotes(msg.sender, p.voteStart);
        require(votePower > 0, "No voting power");

        require(
            clock() - p.voteStart <= voteTimeout,
            "Voting period ended"
        );

        if (!p.voted[msg.sender]) {
            if (approve) {
                p.approvePower += votePower;
            } else {
                p.rejectPower += votePower;
            }
            p.voted[msg.sender] = true;
        } else {
            if (p.votes[msg.sender] && !approve) {
                p.approvePower -= votePower;
                p.rejectPower += votePower;
            } else if (!p.votes[msg.sender] && approve) {
                p.rejectPower -= votePower;
                p.approvePower += votePower;
            }
        }

        p.votes[msg.sender] = approve;
        return approve;
    }

    function endVote(uint256 id) external returns (string memory) {
        require(id > 0 && id <= currentId, "Invalid proposal");
        Proposal storage p = proposals[id];

        require(
            keccak256(bytes(p.status)) == keccak256(bytes("Voting")),
            "Not voting"
        );

        bool timeoutReached =
            balanceOf(msg.sender) > 0 &&
            (clock() - p.voteStart) > voteTimeout;

        uint256 ownerVotes = getPastVotes(owner(), p.voteStart);
        uint256 effectiveSupply = totalSupply() - ownerVotes;

        bool quorumReached =
            msg.sender == owner() &&
            ((p.approvePower + p.rejectPower) * 100) /
                effectiveSupply >=
            voteQuorum;

        require(timeoutReached || quorumReached, "Cannot end vote yet");

        if (p.approvePower > p.rejectPower) {
            p.status = "Approved";
        } else {
            p.status = "Rejected";
        }

        return p.status;
    }

    /* -------------------------------------------------------------------------- */
    /*                              ADMIN FUNCTIONS                                */
    /* -------------------------------------------------------------------------- */

    function changeVotingTimeout(uint256 newTimeout) external onlyOwner {
        voteTimeout = newTimeout;
    }

    function changeQuorum(uint256 newQuorum) external onlyOwner {
        require(newQuorum <= 100, "Invalid quorum");
        voteQuorum = newQuorum;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 VIEW LOGIC                                  */
    /* -------------------------------------------------------------------------- */

    function getProposal(
        uint256 id
    )
        external
        view
        returns (
            address,
            uint48,
            string memory,
            string memory,
            uint256
        )
    {
        require(balanceOf(msg.sender) > 0, "Not a token holder");
        require(id > 0 && id <= currentId, "Invalid proposal");

        Proposal storage p = proposals[id];
        return (
            p.proposer,
            p.voteStart,
            p.status,
            p.description,
            p.budget
        );
    }
}
