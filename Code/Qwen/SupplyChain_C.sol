// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Prescriptions Contract
 * @dev Manages medical prescriptions for patients, ensuring no dual-use limitations
 */
contract Prescriptions {
    // Address of the manager contract that controls access
    address public managerContract;

    /**
     * @dev Structure representing a medical prescription
     */
    struct Prescription {
        uint256 time;       // Timestamp when the prescription was created
        address doctor;     // Address of the doctor who prescribed
        string medicine;    // Name of the prescribed medicine
        uint256 dose;       // Number of units prescribed
        bool valid;         // Whether the prescription is still valid for use
    }

    /**
     * @dev Structure representing a patient's data
     */
    struct Patient {
        uint256 currentId;                              // Last prescription ID for this patient
        mapping(uint256 => Prescription) prescriptions; // Mapping from prescription IDs to prescriptions
    }

    // Mapping from patient addresses to their patient data
    mapping(address => Patient) private patients;

    /**
     * @dev Constructor to set the manager contract address
     * @param managerAddress Address of the manager contract
     */
    constructor(address managerAddress) {
        managerContract = managerAddress;
    }

    /**
     * @dev Internal function to create a new prescription
     * @param doctor Address of the prescribing doctor
     * @param patient Address of the patient receiving the prescription
     * @param _medicine Name of the medicine being prescribed
     * @param _dose Number of units being prescribed
     * @return The ID of the newly created prescription
     */
    function _prescribe(
        address doctor,
        address patient,
        string memory _medicine,
        uint256 _dose
    ) external returns (uint256) {
        require(msg.sender == managerContract, "Only manager contract can call this function");

        // Create new prescription
        Prescription memory newPrescription = Prescription({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });

        // Increment patient's current ID and assign the new prescription
        patients[patient].currentId++;
        patients[patient].prescriptions[patients[patient].currentId] = newPrescription;

        return patients[patient].currentId;
    }

    /**
     * @dev Internal function to get a prescription
     * @param patient Address of the patient
     * @param id ID of the prescription to retrieve
     * @return The requested prescription
     */
    function _getPrescription(
        address patient,
        uint256 id
    ) external view returns (Prescription memory) {
        require(msg.sender == managerContract, "Only manager contract can call this function");
        require(id <= patients[patient].currentId && id > 0, "Invalid prescription ID");

        return patients[patient].prescriptions[id];
    }

    /**
     * @dev Internal function to mark a prescription as used (invalid)
     * @param patient Address of the patient
     * @param id ID of the prescription to invalidate
     */
    function usePrescription(address patient, uint256 id) external {
        require(msg.sender == managerContract, "Only manager contract can call this function");
        require(id <= patients[patient].currentId && id > 0, "Invalid prescription ID");

        patients[patient].prescriptions[id].valid = false;
    }
}

/**
 * @title Authorization Certificates Contract
 * @dev Manages authorization for hospitals and manufacturers
 */
contract AuthorizationCertificates {
    address public admin;  // Admin account with full control

    // Mappings to track authorized entities
    mapping(address => bool) internal authorizedHospitals;
    mapping(address => bool) internal authorizedManufacturers;

    /**
     * @dev Constructor to set the initial admin
     */
    constructor() {
        admin = msg.sender;
    }

    /**
     * @dev Authorize a hospital
     * @param hospital Address of the hospital to authorize
     */
    function authorizeHospital(address hospital) external {
        require(msg.sender == admin, "Only admin can authorize hospitals");
        authorizedHospitals[hospital] = true;
    }

    /**
     * @dev Remove authorization from a hospital
     * @param hospital Address of the hospital to unauthorize
     */
    function unauthorizeHospital(address hospital) external {
        require(msg.sender == admin, "Only admin can unauthorize hospitals");
        authorizedHospitals[hospital] = false;
    }

    /**
     * @dev Authorize a manufacturer
     * @param manufacturer Address of the manufacturer to authorize
     */
    function authorizeManufacturer(address manufacturer) external {
        require(msg.sender == admin, "Only admin can authorize manufacturers");
        authorizedManufacturers[manufacturer] = true;
    }

    /**
     * @dev Remove authorization from a manufacturer
     * @param manufacturer Address of the manufacturer to unauthorize
     */
    function unauthorizeManufacturer(address manufacturer) external {
        require(msg.sender == admin, "Only admin can unauthorize manufacturers");
        authorizedManufacturers[manufacturer] = false;
    }

    /**
     * @dev Check if a hospital is authorized
     * @param hospital Address of the hospital to check
     * @return True if the hospital is authorized, false otherwise
     */
    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }

    /**
     * @dev Check if a manufacturer is authorized
     * @param manufacturer Address of the manufacturer to check
     * @return True if the manufacturer is authorized, false otherwise
     */
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }

    /**
     * @dev Change the admin address
     * @param newAdmin Address of the new admin
     */
    function changeAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only admin can change admin");
        admin = newAdmin;
    }
}

/**
 * @title Pharma Company Contract
 * @dev ERC1155-based contract for managing medicine tokens
 */
contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    // Mappings for medicine management
    mapping(string => uint256) public medicines;      // Maps medicine names to their IDs
    mapping(uint256 => uint256) public prices;        // Maps medicine IDs to their prices in wei
    address public govAuthorizationContract;          // Address of the government authorization contract

    /**
     * @dev Constructor for the Pharma Company contract
     * @param _govAuthorizationContract Address of the government authorization contract
     */
    constructor(address _govAuthorizationContract) 
        ERC1155("https://pharma.com/medicine/{id}.json") 
        Ownable(msg.sender) 
    {
        govAuthorizationContract = _govAuthorizationContract;
    }

    /**
     * @dev Mint a single type of medicine token
     * @param id ID of the medicine to mint
     * @param amount Amount of tokens to mint
     * @param data Additional data to pass
     * @param medicineName Name of the medicine
     */
    function mint(
        uint256 id,
        uint256 amount,
        bytes memory data,
        string memory medicineName
    ) public onlyOwner {
        require(id != 0, "ID cannot be zero");
        
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
    }

    /**
     * @dev Mint multiple types of medicine tokens
     * @param ids Array of IDs of medicines to mint
     * @param amounts Array of amounts of tokens to mint
     * @param data Additional data to pass
     * @param medicineNames Array of medicine names
     */
    function mintBatch(
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data,
        string[] memory medicineNames
    ) public onlyOwner {
        require(ids.length == amounts.length && ids.length == medicineNames.length, "Array lengths must match");
        
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] != 0, "ID cannot be zero");
            medicines[medicineNames[i]] = ids[i];
        }
        
        _mintBatch(msg.sender, ids, amounts, data);
    }

    /**
     * @dev Buy medicine using a valid prescription
     * @param medicineName Name of the medicine to buy
     * @param hospital Address of the hospital issuing the prescription
     * @param prescriptionId ID of the prescription
     * @param to Recipient address for the medicine
     * @param amount Amount of medicine to buy
     */
    function buyMedicine(
        string memory medicineName,
        address hospital,
        uint256 prescriptionId,
        address to,
        uint256 amount
    ) external payable {
        // Verify that the hospital is authorized
        bool isHospitalAuth = AuthorizationCertificates(govAuthorizationContract).isAuthorizedHospital(hospital);
        require(isHospitalAuth, "Hospital is not authorized");

        // Verify that the requested medicine is available
        uint256 medicineId = medicines[medicineName];
        require(balanceOf(owner(), medicineId) >= amount, "Not enough medicine in stock");

        // Verify that the payment matches the expected price
        uint256 expectedPrice = amount * prices[medicineId];
        require(msg.value == expectedPrice, "Incorrect payment amount");

        // Verify the prescription through the hospital contract
        bool saleAuthorized = PharmaHospital(hospital).authorizeSale(prescriptionId, to, medicineName, amount);
        require(saleAuthorized, "Prescription validation failed");

        // Transfer the medicine tokens to the buyer
        _safeTransferFrom(owner(), to, medicineId, amount, bytes(medicineName));
    }

    /**
     * @dev Update the price of a medicine
     * @param id ID of the medicine to update
     * @param newPrice New price in wei
     */
    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        prices[id] = newPrice;
    }
}

/**
 * @title Hospital Management Contract
 * @dev Manages hospital operations including doctor authorization and prescription handling
 */
contract PharmaHospital {
    // Mappings for hospital administration
    mapping(address => bool) public admins;           // Maps addresses to admin status
    uint256 internal adminsCount;                     // Count of active admins
    mapping(address => bool) public doctors;          // Maps addresses to doctor status

    address public prescriptionsContract;             // Address of the prescriptions contract
    address public govAuthorizationContract;          // Address of the government authorization contract

    /**
     * @dev Structure representing a medical prescription (replicated for visibility)
     */
    struct Prescription {
        uint256 time;       // Timestamp when the prescription was created
        address doctor;     // Address of the doctor who prescribed
        string medicine;    // Name of the prescribed medicine
        uint256 dose;       // Number of units prescribed
        bool valid;         // Whether the prescription is still valid for use
    }

    /**
     * @dev Constructor for the hospital management contract
     * @param _govAuthorizationContract Address of the government authorization contract
     */
    constructor(address _govAuthorizationContract) {
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
    }

    /**
     * @dev Add a new admin to the hospital
     * @param newAdmin Address of the new admin
     */
    function addAdmin(address newAdmin) external {
        require(admins[msg.sender], "Only existing admins can add new admins");
        require(!admins[newAdmin], "Admin already exists");
        
        admins[newAdmin] = true;
        adminsCount++;
    }

    /**
     * @dev Remove an admin from the hospital
     * @param admin Address of the admin to remove
     */
    function removeAdmin(address admin) external {
        require(admins[msg.sender], "Only existing admins can remove other admins");
        require(admins[admin], "Admin does not exist");
        require(adminsCount > 1, "Cannot remove the last admin");
        
        admins[admin] = false;
        adminsCount--;
    }

    /**
     * @dev Add a doctor to the hospital
     * @param newDoctor Address of the new doctor
     */
    function addDoctor(address newDoctor) external {
        require(admins[msg.sender], "Only admins can add doctors");
        doctors[newDoctor] = true;
    }

    /**
     * @dev Remove a doctor from the hospital
     * @param doctor Address of the doctor to remove
     */
    function removeDoctor(address doctor) external {
        require(admins[msg.sender], "Only admins can remove doctors");
        doctors[doctor] = false;
    }

    /**
     * @dev Create a new prescription
     * @param patient Address of the patient
     * @param medicine Name of the medicine being prescribed
     * @param dose Amount of medicine to prescribe
     * @return The ID of the new prescription
     */
    function prescribe(
        address patient,
        string memory medicine,
        uint256 dose
    ) external returns (uint256) {
        require(doctors[msg.sender], "Only doctors can prescribe medicine");
        
        uint256 prescriptionId = Prescriptions(prescriptionsContract)._prescribe(
            msg.sender,
            patient,
            medicine,
            dose
        );
        
        return prescriptionId;
    }

    /**
     * @dev Get a prescription
     * @param patient Address of the patient
     * @param prescriptionId ID of the prescription to retrieve
     * @return The requested prescription
     */
    function getPrescription(
        address patient,
        uint256 prescriptionId
    ) external view returns (Prescription memory) {
        // Allow access if the caller is a doctor or the patient themselves
        require(
            doctors[msg.sender] || msg.sender == patient,
            "Only doctors or patients can view prescriptions"
        );

        Prescriptions.Prescription memory presc = Prescriptions(prescriptionsContract)._getPrescription(
            patient,
            prescriptionId
        );
        
        // Convert to local struct type
        return Prescription({
            time: presc.time,
            doctor: presc.doctor,
            medicine: presc.medicine,
            dose: presc.dose,
            valid: presc.valid
        });
    }

    /**
     * @dev Authorize a sale based on a valid prescription
     * @param prescriptionId ID of the prescription to validate
     * @param patient Address of the patient
     * @param medicine Name of the medicine being purchased
     * @param amount Amount of medicine being purchased
     * @return True if the sale is authorized, false otherwise
     */
    function authorizeSale(
        uint256 prescriptionId,
        address patient,
        string memory medicine,
        uint256 amount
    ) external returns (bool) {
        // Verify that the caller is an authorized manufacturer
        bool isManufacturerAuth = AuthorizationCertificates(govAuthorizationContract)
            .isAuthorizedManufacturer(msg.sender);
        require(isManufacturerAuth, "Only authorized manufacturers can call this function");

        // Retrieve the prescription
        Prescriptions.Prescription memory presc = Prescriptions(prescriptionsContract)._getPrescription(
            patient,
            prescriptionId
        );

        // Validate the prescription details
        if (
            presc.valid &&
            keccak256(bytes(presc.medicine)) == keccak256(bytes(medicine)) &&
            amount == presc.dose
        ) {
            // Mark the prescription as used
            Prescriptions(prescriptionsContract).usePrescription(patient, prescriptionId);
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Set the prescriptions contract address
     * @param newPrescriptionContract Address of the new prescriptions contract
     */
    function setPrescriptionContract(address newPrescriptionContract) external {
        require(admins[msg.sender], "Only admins can set the prescription contract");
        prescriptionsContract = newPrescriptionContract;
    }
}