// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Prescriptions {
    address public managerContract;

    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    struct Patient {
        uint256 currentId;
        mapping(uint256 => Prescription) prescriptions;
    }

    mapping(address => Patient) private patients;

    constructor(address managerAddress) {
        managerContract = managerAddress;
    }

    function _prescribe(address doctor, address patient, string memory _medicine, uint256 _dose) external returns (uint256) {
        require(msg.sender == managerContract, "Only manager contract can prescribe");
        patients[patient].currentId++;
        uint256 newId = patients[patient].currentId;
        patients[patient].prescriptions[newId] = Prescription({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });
        return newId;
    }

    function _getPrescription(address patient, uint256 id) external view returns (Prescription memory) {
        require(msg.sender == managerContract, "Only manager contract can get prescription");
        require(id <= patients[patient].currentId && id != 0, "Invalid prescription ID");
        return patients[patient].prescriptions[id];
    }

    function usePrescription(address patient, uint256 id) external {
        require(msg.sender == managerContract, "Only manager contract can use prescription");
        require(id <= patients[patient].currentId && id != 0, "Invalid prescription ID");
        patients[patient].prescriptions[id].valid = false;
    }
}

contract authorizationCertificates {
    address public admin;
    mapping(address => bool) internal authorizedHospitals;
    mapping(address => bool) internal authorizedManufacturers;

    constructor() {
        admin = msg.sender;
    }

    function authorizeHospital(address hospital) external {
        require(msg.sender == admin, "Only admin can authorize hospital");
        authorizedHospitals[hospital] = true;
    }

    function unauthorizeHospital(address hospital) external {
        require(msg.sender == admin, "Only admin can unauthorize hospital");
        authorizedHospitals[hospital] = false;
    }

    function authorizeManufacturer(address manufacturer) external {
        require(msg.sender == admin, "Only admin can authorize manufacturer");
        authorizedManufacturers[manufacturer] = true;
    }

    function unauthorizeManufacturer(address manufacturer) external {
        require(msg.sender == admin, "Only admin can unauthorize manufacturer");
        authorizedManufacturers[manufacturer] = false;
    }

    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }

    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }

    function changeAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only admin can change admin");
        admin = newAdmin;
    }
}

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    mapping(string => uint256) public medicines;
    mapping(uint256 => uint256) public prices;
    address public govAuthorizationContract;

    constructor(address _govAuthorizationContract) ERC1155("https://pharma.com/medicine/") Ownable(msg.sender) {
        govAuthorizationContract = _govAuthorizationContract;
    }

    function mint(uint256 id, uint256 amount, bytes memory data, string memory medicineName) public onlyOwner {
        require(id != 0, "ID cannot be 0");
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
    }

    function mintBatch(uint256[] memory ids, uint256[] memory amounts, bytes memory data, string[] memory medicineNames) public onlyOwner {
        require(ids.length == medicineNames.length, "Arrays length mismatch");
        for (uint256 i = 0; i < medicineNames.length; i++) {
            require(ids[i] != 0, "ID cannot be 0");
            medicines[medicineNames[i]] = ids[i];
        }
        _mintBatch(msg.sender, ids, amounts, data);
    }

    function buyMedicine(string memory medicineName, address hospital, uint256 prescriptionId, address to, uint256 amount) external payable {
        require(IAuthorizationCertificatesHospitals(govAuthorizationContract).isAuthorizedHospital(hospital), "Hospital not authorized");
        require(balanceOf(owner(), medicines[medicineName]) > 0, "Medicine not available");
        require(msg.value == amount * prices[medicines[medicineName]], "Incorrect payment amount");
        require(IHospitalManagement(hospital).authorizeSale(prescriptionId, to, medicineName, amount), "Sale not authorized");
        _safeTransferFrom(owner(), to, medicines[medicineName], amount, bytes(medicineName));
    }

    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        prices[id] = newPrice;
    }
}

interface IAuthorizationCertificatesHospitals {
    function isAuthorizedHospital(address hospital) external view returns (bool);
}

interface IHospitalManagement {
    function authorizeSale(uint256 prescriptionId, address patient, string memory medicine, uint256 amount) external returns (bool);
}

contract hospitalManagement {
    mapping(address => bool) public admins;
    uint256 internal adminsCount;
    mapping(address => bool) public doctors;
    address public prescriptionsContract;
    address public govAuthorizationContract;

    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    constructor(address _govAuthorizationContract) {
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
    }

    function addAdmin(address newAdmin) external {
        require(admins[msg.sender], "Only admin can add admin");
        adminsCount++;
        admins[newAdmin] = true;
    }

    function removeAdmin(address admin) external {
        require(admins[msg.sender], "Only admin can remove admin");
        require(adminsCount > 1, "Cannot remove last admin");
        adminsCount--;
        admins[admin] = false;
    }

    function addDoctor(address newDoctor) external {
        require(admins[msg.sender], "Only admin can add doctor");
        doctors[newDoctor] = true;
    }

    function removeDoctor(address doctor) external {
        require(admins[msg.sender], "Only admin can remove doctor");
        doctors[doctor] = false;
    }

    function prescribe(address patient, string memory medicine, uint256 dose) external returns (uint256) {
        require(doctors[msg.sender], "Only doctor can prescribe");
        return IPrescriptions(prescriptionsContract)._prescribe(msg.sender, patient, medicine, dose);
    }

    function getPrescription(address patient, uint256 prescriptionId) external view returns (Prescription memory) {
        require(doctors[msg.sender] || msg.sender == patient, "Only doctor or patient can get prescription");
        IPrescriptions.Prescription memory prescription = IPrescriptions(prescriptionsContract)._getPrescription(patient, prescriptionId);
        return Prescription(
            prescription.time,
            prescription.doctor,
            prescription.medicine,
            prescription.dose,
            prescription.valid
        );
    }

    function authorizeSale(uint256 prescriptionId, address patient, string memory medicine, uint256 amount) external returns (bool) {
        require(IAuthorizationCertificatesManufacturers(govAuthorizationContract).isAuthorizedManufacturer(msg.sender), "Only authorized manufacturer can authorize sale");
        IPrescriptions.Prescription memory prescription = IPrescriptions(prescriptionsContract)._getPrescription(patient, prescriptionId);
        if (prescription.valid && keccak256(bytes(prescription.medicine)) == keccak256(bytes(medicine)) && prescription.dose == amount) {
            IPrescriptions(prescriptionsContract).usePrescription(patient, prescriptionId);
            return true;
        }
        return false;
    }

    function setPrescriptionContract(address newPrescriptionContract) external {
        require(admins[msg.sender], "Only admin can set prescription contract");
        prescriptionsContract = newPrescriptionContract;
    }
}

interface IPrescriptions {
    struct Prescription {
        uint256 time;
        address doctor;
        string medicine;
        uint256 dose;
        bool valid;
    }

    function _prescribe(address doctor, address patient, string memory _medicine, uint256 _dose) external returns (uint256);
    function _getPrescription(address patient, uint256 id) external view returns (Prescription memory);
    function usePrescription(address patient, uint256 id) external;
}

interface IAuthorizationCertificatesManufacturers {
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool);
}
