# Role

You are a senior Ethereum smart contract developer responsible for implementing secure, efficient, well-documented Solidity contracts based on detailed specifications. Your work should follow industry-standard practices for structure, safety, and readability.

# Context
A company has requested the development of a supply chain framework for unifying medicine prescriptions and usage for buying the prescribed medicine. Such application will automatically enforce the no dual-use limitation for the medical prescriptions. You are the lead developer responsible for implementing this project with all of the required functionalities in a secure and extensible manner using Solidity and employing all of the best practices for decentralized applications.

# Objective

Your task is to develop a fully functional, well-commented, and secure Solidity contract that implements all of the smart contracts required for this application, as will be thoroughly described below. The code must:
* Be secure, avoiding vulnerabilities such as reentrancy, integer overflows/underflows, access control issues, and all known vulnerabilities that could affect the contract's functionalities.
* Be readable, using clear naming conventions, structured logic, and inline documentation (Solidity comments).
* Follow best practices for gas efficiency and modularity.
* Enables reliable and transparent management of medicine prescriptions and purchases.
* Use the latest Solidity compiler version you are familiar with.

# Application

## Overview

The application should implement a modular supply chain management framework. Its main goal is to ensure that doctors can prescribe medicines for patients, which can be used in on-chain medicine market places, where medicines are represented as tokens. Crucially, sellers should be able to verify through the hospital contract if the purchase has a valid prescription and the the medicine name and dose are correct.

## Contracts

### Prescriptions

#### Variables

* `address public managerContract`: The address of the manager contract.
* `struct prescription`: A struct containing:
  * `uint256 time`: Timestamp in which the prescription was created.
  * `address doctor`: The address of the doctor that prescribed.
  * `string medicine`: The name of the medicine prescribed.
  * `uint256 dose`: Number of units prescribed.
  * `bool valid`: A bool showcasing if the prescription can be used to buy medicine.
* `struct patient`: A struct containing:
  * `uint256 currentId`: Last description id for this patient.
  * `mapping(uint256 => prescription) prescriptions`: Maps prescription ids to a `prescription`.
* `mapping(address => patient) private patients`: Maps a patient to `patient`.


#### Functions

* `constructor(address managerAddress)`:
  * Set `managerContract` as `managerAddress`.

* `_prescribe(address doctor, address patient, string memory _medicine, uint256 _dose) external returns (uint256)`
  * Check if:
    * `msg.sender` is `managerContract`.
  * Creates a `prescription` struct with:
    * `time` = `block.timestamp`.
    * `doctor` = `doctor`.
    * `medicine` = `_medicine`.
    * `dose` = `_dose`.
    * `valid` = `true`.
  * Increment `patients[patient].currentId`.
  * Set `patients[patient].prescriptions[patients[patient].currentId]` as the newly created `prescription` struct.
  * Return `patients[patient].currentId`.

* `_getPrescription(address patient, uint256 id) external view returns (prescription memory)`
  * Check if:
    * `msg.sender` is `managerContract`.
    * `id` is a valid prescription for this patient.
  * Return `patients[patient].prescriptions[id]`.

* `usePrescription(address patient, uint256 id) external`
  * Check if:
    * `msg.sender` is `managerContract`.
    * `id` is a valid prescription for this patient.
  * Set `patients[patient].prescriptions[id].valid` to `false`.

### authorizationCertificates

#### Variables

* `address public admin`: Admin account.
* `mapping(address => bool) internal authorizedHospitals`: Maps addresses to a bool showcasing if it is authorized.
* `mapping(address => bool) internal authorizedManufacturers`: Maps addresses to a bool showcasing if it is authorized.

#### Functions

* `constructor()`
  * Set `msg.sender` as `admin`

* `authorizeHospital(address hospital) external`
  * Check if:
    * `msg.sender` is `admin`.
  * Set `authorizedHospitals[hospital]` to `true`.

* `unauthorizeHospital(address hospital) external`
  * Check if:
    * `msg.sender` is `admin`.
  * Set `authorizedHospitals[hospital]` to `false`.

* `authorizeManufacturer(address manufacturer) external`
  * Check if:
    * `msg.sender` is `admin`.
  * Set `authorizedManufacturers[manufacturer]` to `true`.

* `unauthorizeManufacturer(address manufacturer) external`
  * Check if:
    * `msg.sender` is `admin`.
  * Set `authorizedManufacturers[manufacturer]` to `false`.

* `isAuthorizedHospital(address hospital) external returns (bool)`
  * Return `authorizedHospitals[hospital]`.

* `isAuthorizedManufacturer(address manufacturer) external returns (bool)`
  * Return `authorizedManufacturers[manufacturer]`.

* `changeAdmin(address newAdmin) external`
  * Check if:
    * `msg.sender` is `admin`.
  * Change `admin` to `newAdmin`.

### PharmaCompany

#### Variables

`mapping(string => uint256) public medicines`: Maps medicine names to their ids.
`mapping(uint256 => uint256) public prices`: Maps medicine ids to their prices in wei.
`address public govAuthorizationContract`: Address to the governmental contract which stores authorized hospital addresses.

#### Functions

The contract should follow OpenZeppelin's ERC1155. Hence, the following libraries should be used:

* `ERC1155`
* `ERC1155Burnable`
* `Ownable`

As per OpenZeppelin's token wizard, the following functions should be present:

* `mint(uint256 id, uint256 amount, bytes memory data, string memory medicineName) public onlyOwner`
  * Check if:
    * `id` is not 0.
  * Set `medicines[medicineName]` to `id`.
  * Call _mint(`msg.sender`, `id`, `amount`, `data`).

* `mintBatch(uint256[] memory ids, uint256[] memory amounts, bytes memory data, string[] memory medicineNames) public onlyOwner`
  * Check if:
    * No `id` in `ids` is 0.
  * For each entry in `medicineNames`:
    * Set `medicines[medicineNames[index]]` to `ids[index]`.
  * Call _mintBatch(`msg.sender`, `ids`, `amounts`, `data`)

##### Custom Functions

* `constructor(address _govAuthorizationContract) ERC1155("https://pharma.com/medicine/") Ownable(msg.sender)`
  * Set `govAuthorizationContract` as `_govAuthorizationContract`.

* `buyMedicine(string memory medicineName, address hospital, uint256 prescriptionId, uint256 to, uint256 amount) external payable`
  * Check if:
    * The return of calling isAuthorizedHospital(`hospital`), from `govAuthorizationContract`, is `true`.
    * Medicine is available. That is, balanceOf(`owner`, `medicines[medicineName]`) is greater than zero.
    * `msg.value` is equal to `amount` * `prices[medicines[medicineName]]`.
  * Call authorizeSale(`prescriptionId`, `to`, `medicineName`, `amount`) from `hospital`. If it returns `true`:
    * Call _safeTransferFrom(`owner`, `to`, `medicines[medicineName]`, `amount`, bytes(`medicineName`))

* `updatePrice(uint256 id, uint256 newPrice) external onlyOwner`
  * Check if:
    * `newPrice` is greater than 0.
  * Set `prices[id]` to `newPrice`.

### hospitalManagement

#### Variables

* `mapping(address => bool) public admins`: Maps addresses to bools, showcasing which addresses are hospital administrators.
* `uint256 internal adminsCount`: Number of active admins.
* `mapping(address => bool) public doctors`: Maps addresses to bools, showcasing which addresses are doctors.
* `address public prescriptionsContract`: The address of the prescriptions contract.
* `address public govAuthorizationContract`: Address to the governmental contract which stores authorized hospital addresses.
* `struct prescription`: A struct containing:
  * `uint256 time`: Timestamp in which the prescription was created.
  * `address doctor`: The address of the doctor that prescribed.
  * `string medicine`: The name of the medicine prescribed.
  * `uint256 dose`: Number of units prescribed.
  * `bool valid`: A bool showcasing if the prescription can be used to buy medicine. 

### Functions

* `constructor(address _govAuthorizationContract)`
  * Set `admins[msg.sender]` as `true`.
  * Increment `adminsCount` by 1.
  * Set `govAuthorizationContract` as `_govAuthorizationContract`.

* `addAdmin(address newAdmin) external`
  * Check if:
    * `admins[msg.sender]` is `true`.
  * Increment `adminsCount` by 1.
  * Set `admins[newAdmin]` to `true`.

* `removeAdmin(address admin) external`
  * Check if:
    * `admins[msg.sender]` is `true`.
    * `adminsCount` is greater than 1.
  * Decrement `adminsCount` by 1.
  * Set `admins[admin]` to `false`.

* `addDoctor(address newDoctor) external`
  * Check if:
    * `admins[msg.sender]` is `true`.
  * Set `doctors[newDoctor]` to `true`.

* `removeDoctor(address doctor) external`
  * Check if:
    * `admins[msg.sender]` is `true`.
  * Set `doctors[doctor]` to `false`.

* `prescribe(address patient, string memory medicine, uint256 dose) external returns (uint256)`
  * Check if:
    * `doctors[msg.sender]` is `true`.
  * Call _prescribe(`msg.sender`, `patient`, `medicine`, `dose`) from the `prescriptionsContract` contract and store the returned value in `prescriptionId`.
  * Return `prescriptionId`.

* `getPrescription(address patient, uint256 prescriptionId) external view returns (prescription memory)`
  * Check for one of the following:
    * `doctors[msg.sender]` is `true`
    * `msg.sender` is equal to `patient`.
  * Call _getPrescription(`patient`, `prescriptionId`) from the `prescriptionsContract` contract and store returned struct in `prescription`.
  * Return `prescription`.

* `authorizeSale(uint256 prescriptionId, address patient, string memory medicine, uint256 amount) external returns (bool)`
  * Check if:
    * The returned bool of calling isAuthorizedManufacturer(`msg.sender`), from `govAuthorizationContract`, is `true`.
  * Call _getPrescription(`patient`, `prescriptionId`) from the `prescriptionsContract` contract and store returned struct in `prescription`.
  * If:
    * `prescription.valid` is `true`.
    * `medicine` is equal to `prescription.medicine`.
    * `amount` is equal to `prescription.dose`
  * Call usePrescription(`patient`, `prescriptionId`) from `prescriptionsContract`.
  * Return `true`.
  * Else return `false`.

* `setPrescriptionContract(address newPrescriptionContract) external`
  * Check if:
    * `admins[msg.sender]` is `true`.
  * Set `prescriptionsContract` as `newPrescriptionContract`.

# Response Format

Your response should be the fully implemented Solidity contract that includes all the functionalities and functions described above. No additional content is required.
