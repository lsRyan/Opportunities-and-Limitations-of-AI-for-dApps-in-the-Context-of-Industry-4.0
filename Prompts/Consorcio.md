# Role

You are a senior Ethereum smart contract developer responsible for implementing secure, efficient, well-documented Solidity contracts based on detailed specifications. Your work should follow industry-standard practices for structure, safety, and readability.

# Context

A company has requested the development of a financing pool smart contract, which allows users to collaboratively acquire goods by pooling funds. You are the lead developer responsible for implementing this project with all of the required functionalities in a secure and extensible manner using Solidity and employing all of the best practices for decentralized applications.

# Objective

Your task is to develop a fully functional, well-commented, and secure Solidity contract that implements the FinancialPoolManager contract, as will be thoroughly described below. The code must:
* Be secure, avoiding vulnerabilities such as reentrancy, integer overflows/underflows, access control issues, and all known vulnerabilities that could affect the contract's functionalities.
* Be readable, using clear naming conventions, structured logic, and inline documentation (Solidity comments).
* Follow best practices for gas efficiency and modularity.
* Support multiple concurrent financing pools.
* Use the latest Solidity compiler version you are familiar with.

# Application

## Overview

The smart contract must implement a system known as a financing pool, which allows users to collectively fund a purchase. Users contribute fixed installments over time, and once the total amount is reached, one user (randomly selected) receives the funded good's value. The selected user need to continue paying installments for the full duration of the pool. The contract must allow any user to create its own pool and support multiple pools running simultaneously. It should provide all of the necessary functionalities for pool owners to manage their pools.

## Contracts

### FinancialPoolManager

#### Variables

* `struct participantInfo`: The information regarding a participant in a pool. Includes:
  * `bool received`: Specifies if the participant has already been selected to receive the good's value.
  * `bool canReceive`: Specifies if the participant is eligible for receiving the good's value.
  * `uint256 payments`: The number of payments that the user already did.
* `struct pool`: The information regarding a financial pool. Include:
  * `address owner`: Pool owner.
  * `string targetGood`: Name or description of the good being purchased.
  * `uint256 goodValue`: The total value required for the purchase in wei.
  * `uint256 balance`: The total value under the pool's administration.
  * `uint256 minParticipants`: Minimum number of participants needed to activate the pool.
  * `uint256 totalParticipants`: The number of participants in the pool.
  * `address[] participants`: List of participants.
  * `mapping(address => participantInfo) participantsInfo`: Maps participants to their `participantInfo`.
  * `uint256 winnersCount`: Count the number of winners.
  * `uint256 installments`: Total number of installments (duration in months).
  * `uint256 activationDate`: The `block.timestamp` of the date when the pool was activated.
  * `uint256 installmentValue`: The value which should be payed for each installment.
  * `string memory status`: The current state of the pool, which can be "accepting_participants", "active", "canceled" and "finished".
* `mapping(uint256 => pool) internal pools`: Maps pool's ID to a `pool`.
* `uint256 public currentId`: The value of the latest id.

#### Functions

* `createPool(string memory targetGood, uint256 goodValue, uint256 minParticipants, uint256 installments) external returns (uint256)`
  * Increment `currentId`
  * Initialize `pools[currentId]` with:
    * `pools[currentId].owner` as `msg.sender`.
    * `pools[currentId].targetGood` as `targetGood`.
    * `pools[currentId].goodValue` as `goodValue`.
    * `pools[currentId].minParticipants` as `minParticipants`.
    * `pools[currentId].installments` as `installments`
    * `pools[currentId].installmentValue` as `goodValue`/`installments`.
    * `pools[currentId].status` as "accepting_participants".
  * Returns the assigned `currentId`.

* `activatePool(uint256 poolId) external`
  * Checks if:
    * `poolId` is valid.
    * `msg.sender` is `pools[poolId].owner`.
    * `pools[poolId]totalParticipants` is greater or equal to `pools[poolId]minParticipants`.
  * Set `pools[poolId].activationDate` to `block.timestamp`.
  * Set `pools[poolId].status` to "active".

* `deletePool(uint256 poolId) external`
  * Checks if:
    * `poolId` is valid.
    * `msg.sender` is `pools[poolId].owner`.
    * `pools[poolId].status` is "accepting_participants".
  * Set `pools[poolId].status` to "canceled".

* `participateInPool(uint256 poolId) external`
  * Check if:
    * `poolId` is valid.
    * `pools[poolId].status` is "accepting_participants".
    * `msg.sender` is not in `pools[poolId].participants`.
  * Increment `pools[poolId].totalParticipants`
  * Add `msg.sender` to `pools[poolId].participants`.

* `leavePool(uint256 poolId) external`
  * Checks if:
    * `poolId` is valid.
    * `pools[poolId].status` is "accepting_participants".
    * `msg.sender` is in `pools[poolId].participants`.
  * Set `index` as the `msg.sender` index in `pools[poolId].participants`.
  * Decrement `pools[poolId].totalParticipants`
  * Execute `delete pools[poolId].participants[index]`.
  * Copy the last entry in `pools[poolId].participants` to `pools[poolId].participants[index]`.
  * Execute `pools[poolId].participants.pop()`.

* `payInstallment(uint256 poolId) external payable`
  * Checks if:
    * `poolId` is valid.
    * `pools[poolId].status` is "active".
    * `msg.sender` is in `pools[poolId].participants`.
    * The value sent is equal to `installmentValue`.
  * Calculate `duePayments` as floor((`block.timestamp` - `activationDate`) / 30 `days`).
  * Checks if:
    * `pools[poolId].participantsInfo[msg.sender].payments` is smaller than `duePayments`.
  * Increment the caller's `payments` by one.
  * Increment `pool[poolId].balance` by `msg.value`.
  * If `pools[poolId].participantsInfo[msg.sender].payments` is equal to `duePayments` and `pools[poolId].participantsInfo[msg.sender].received` is `false`:
    * Set `pools[poolId].participantsInfo[msg.sender].canReceive` to `true`.
  * Else:
    * Set `pools[poolId].participantsInfo[msg.sender].canReceive` to `false`.
  * If `pool[poolId].balance` is greater or equal than `goodValue`:
    * Select a `winner` as random address from `pools[poolId].participants`, filtering for those whose `pools[poolId].participantsInfo[winner].canReceive` is `true` and `pools[poolId].participantsInfo[winner].received` is `false`.
    * If no one is eligible:
      * No transfer occurs.
    * Else:
      * Subtract `pool[poolId].goodValue` from the pool's `pool[poolId].balance`.
      * Transfer the `pool[poolId].goodValue` to `winner`.
      * Increment `pool[poolId].winnersCount`.
      * Set `pools[poolId].participantsInfo[winner].received` to `true`.
      * Set `pools[poolId].participantsInfo[winner].canReceive` to `false`.
    * If the value of `pools[poolId].winnerCount` equal to `pools[poolId].totalParticipants`:
      * Set `pools[poolId].status` to "finished".

* `getPool(uint256 poolId) external view returns (address, string memory, uint256, uint256, uint256, uint256, uint256, uint256, uint256, string memory)`
  * Checks if:
    * `poolId` is valid.
  * Return `pools[poolId].owner`, `pools[poolId].targetGood`, `pools[poolId].goodValue`, `pools[poolId].minParticipants`, `pools[poolId].totalParticipants`, `pools[poolId].winnersCount`, `pools[poolId].installments`, `pools[poolId].activationDate`, `pools[poolId].installmentValue`, `pools[poolId].status`.

# Response Format

Your response should be a fully implemented Solidity contract that includes all the functionalities described above. Remember that your implementation must be complete, secure, well-documented, and structured with best practices in mind. No additional text or explanation is required — just the code.
