# Role

You are a senior Ethereum smart contract developer responsible for implementing secure, efficient, well-documented Solidity contracts based on detailed specifications. Your work should follow industry-standard practices for structure, safety, and readability.

# Context

A condo has requested the development of a smart contract for owners' to make proposals and vote on them. You are the lead developer responsible for employing OpenZeppelin's ERC20 standard token to implement this project with all of the required functionalities in a secure and extensible manner using Solidity and employing all of the best practices for decentralized applications.

# Objective
Your task is to develop a fully functional, well-commented, and secure Solidity contract that implements the CondoVotingSystem smart contract, as will be thoroughly described below. The code must:

* Be secure, avoiding vulnerabilities such as reentrancy, integer overflows/underflows, access control issues, and all known vulnerabilities that could affect the contract's functionalities.
* Be readable, using clear naming conventions, structured logic, and inline documentation (Solidity comments).
* Follow best practices for gas efficiency, modularity, and full integration of OpenZeppelin libraries.
* Employ OpenZeppelin's  ERC20 standard to determine voting power in each proposal.
* Use the latest Solidity compiler version you are familiar with.

# Application

## Overview

The contract must implement a voting mechanism for property owners in a condominium. Key requirements include:
* The token is minted during contract deployment to property owners. A list of owner should be provided, with each address receiving one token. If more tokens than addresses are minted, those should be awarded to the contract owner.
* Only token holders may propose or vote on proposals.
* Proposals must be voted on within a configurable time window, with early finalization only possible after a specific quorum is reached.
* The contract owner may modify voting timeout and quorum settings.
* Voting results are logged for future reference.

Importantly, the implementation must leverage ERC20Votes built-in functions to track voting power and votes, ensuring compatibility with governance systems. Note that the contract owner cannot vote, e.g., token's owned by the contract owner cannot be used to vote.

## Contracts

### CondoVotingSystem

#### Variables

* `struct proposal`: A struct containing:
  * `address proposer`: The address of the proposal creator.
  * `uint48 voteStart`: The time in which proposal's voting started.
  * `mapping(address => bool) voted` Maps each token owner to whether he has voted.
  * `mapping(address => bool) votes`: Maps each token owner to its vote (`true` = approve, `false` = reject).
  * `uint256 approvePower`: The total vote power to approve the proposal.
  * `uint256 rejectPower`: The total vote power to reject the proposal.
  * `string status`: The current proposal status. Can be set as: "UnderDeliberation", "Voting", "Approved", "Rejected", or "Canceled".
  * `string description`: A string describing the proposal.
  * `uint256 budget`: The expected value needed to implement the proposal in wei.
* `mapping(uint256 => proposal) private proposals`: Maps the id to its corresponding `proposal`.
* `uint256 private voteTimeout`: Maximum voting time (in days). Defaults to 1 day at contract creation.
* `uint256 private voteQuorum`: Minimum percentage of token holders required for a vote to be closed early. Defaults to 70% at contract creation.
* `uint256 private currentId`: A private variable storing the latest proposal ID, defaulting to 0.

#### Functions

##### Standard Functions

The contract should follow OpenZeppelin's ERC20. Hence, the following libraries should be used:

* `ERC20`
* `ERC20Permit`
* `ERC20Votes`
* `Ownable`

As per OpenZeppelin's token wizard, the following functions should be present:

* `clock() public view override returns (uint48)`
  * Return uint48(`block.timestamp`).
  
* `CLOCK_MODE() public pure override returns (string memory)`
  * Return "mode=timestamp".
  
* `_update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes)`
  * Call super._update(`from`, `to`, `value`).

* `nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256)`
  * Returns super.nonces(`owner`).

##### Custom Functions

* `constructor(uint256 amount, address[] tokenOwners) ERC20("Assembleia", "ASS") ERC20Permit("Assembleia") Ownable(msg.sender)`
  * Check if:
    * `amount` is greater or equal than `tokenOwners.length`
  * Mint `amount` tokens.
  * For each address in `tokenOwners`:
    * Grant the address the ownership of one token.
    * Delegate voting power to the address.
  * Remaining tokens should be assigner to `msg.sender`.

* `propose(string memory description, uint256 budget) external returns (uint256)`
  * Check if:
    * balanceOf(`msg.sender`) is greater than 0.
  * Increment `currentId`.
  * Initialize `proposals[currentId]` with:
    * `proposals[currentId].proposer` as `msg.sender`.
    * `proposals[currentId].status` as "underDeliberation".
    * `proposals[currentId].description` as `description`.
    * `proposals[currentId].budget` as `budget`.
  * Return `currentId`.
 
* `cancelProposal(uint256 id) external`
  * Check if:
    * balanceOf(`msg.sender`) is greater than 0.
    * The provided proposal's `id` is valid.
    * `msg.sender` is `proposals[id].proposer`
    * `proposals[id].status` is "underDeliberation".
  * Set `proposals[id].status` to "Canceled".

* `modifyProposal(uint256 id, string memory newDescription, uint256 newBudget) external`
  * Check if:
    * balanceOf(`msg.sender`) is greater than 0.
    * The provided proposal's `id` is valid.
    * `msg.sender` is `proposals[id].proposer`.
    * `proposals[id].status` is "underDeliberation".
  * Set `proposals[id].description` to `newDescription` and `proposals[id].budget` to `newBudget`.

* `openVoting(uint256 id) external onlyOwner`
  * Check if:
    * The provided proposal's `id` is valid.
    * `proposals[id].status` is "underDeliberation".
  * Set `proposals[id].status` to "Voting".
  * Set `proposals[id].voteStart` with the value returned by `clock()`.

* `voteOnProposal(uint256 id, bool approve) external returns (bool)`
  * Check if:
    * `msg.sender` is not `owner`.
    * The provided proposal's `id` is valid.
    * `proposals[id].status` is "Voting".
    * The value of ERC20Votes.getPastVotes(`msg.sender`, `proposals[id].voteStart`) is greater than 0.
    * The value of (`clock()` - `proposals[id].voteStart`) is less or equal than `voteTimeout`.
  * Set `votePower` as ERC20Votes.getPastVotes(`msg.sender`, `proposals[id].voteStart`)`.
  * If `proposals[id].voted[msg.sender]` is `false`:
    * If `approve` is `true`:
      * Increment `approvePower` by `votePower`.
    * Else:
      * Increment `rejectPower` by `votePower`.
    * Set `proposals[id].voted[msg.sender]` to `true`.
  * Else:
    * If `proposals[id].votes[msg.sender]` is `true` and `approve` is `false`:
      * Decrement `proposals[id].approvePower` by `votePower`.
      * Increment `proposals[id].rejectPower` by `votePower`.
    * If `proposals[id].votes[msg.sender]` is `false` and `approve` is `true`:
      * Decrement `proposals[id].rejectPower` by `votePower`.
      * Increment `proposals[id].approvePower` by `votePower`.
  * Set `proposals[id].votes[msg.sender]` to `approve`.
  * Return `proposals[id].votes[msg.sender]`.

* `endVote(uint256 id) external returns (string memory)`
  * Check if:
    * The provided proposal's `id` is valid.
    * `proposals[id].status` is "Voting".
  * Check for any of the following:
    * balanceOf(`msg.sender`) is greater than 0 and (`clock()` - `proposals[id].voteStart`) is greater than `voteTimeout`
    * `msg.sender` is `owner` and ((`proposals[id].approvePower` + `proposals[id].rejectPower`) * 100) / (totalSupply - ERC20Votes.getPastVotes(`owner`, `proposals[id].voteStart`)) is greater or equal than `voteQuorum`.
  * If `approvePower` is greater than `rejectPower`:
    * Set proposal `status` to "Approved".
  * Else: 
    * Set proposal `status` to "Rejected".
  * Return `proposals[id].status`

* `changeVotingTimeout(uint256 newTimeout) external onlyOwner`
  * Update de `voteTimeout`.

* `changeQuorum(uint256 newQuorum) external onlyOwner`
  * Update de `voteQuorum`.

* `getProposal(uint256 id) external returns (address, uint48, string memory, string memory, uint256)`
  * Check if:
    * balanceOf(`msg.sender`) is greater than 0.
    * The provided proposal's `id` is valid.
  * Return `proposals[id].proposer`, `proposals[id].voteStart`, `proposals[id].status`, `proposals[id].description`, `proposals[id].budget`.

# Response Format

Your response should be a fully implemented Solidity contract that includes all the functionalities described above. Remember that your implementation must be complete, secure, well-documented, and structured with best practices in mind. No additional text or explanation is required — just the code.