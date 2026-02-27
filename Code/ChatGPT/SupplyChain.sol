// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            PRESCRIPTIONS
//////////////////////////////////////////////////////////////*/
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

    modifier onlyManager() {
        require(msg.sender == managerContract, "Not manager");
        _;
    }

    constructor(address managerAddress) {
        require(managerAddress != address(0), "Invalid manager");
        managerContract = managerAddress;
    }

    function _prescribe(
        address doctor,
        address patient,
        string memory _medicine,
        uint256 _dose
    ) external onlyManager returns (uint256) {
        require(patient != address(0), "Invalid patient");
        require(_dose > 0, "Invalid dose");

        Patient storage p = patients[patient];
        p.currentId++;

        p.prescriptions[p.currentId] = Prescription({
            time: block.timestamp,
            doctor: doctor,
            medicine: _medicine,
            dose: _dose,
            valid: true
        });

        return p.currentId;
    }

    function _getPrescription(
        address patient,
        uint256 id
    ) external view onlyManager returns (Prescription memory) {
        require(id > 0 && id <= patients[patient].currentId, "Invalid id");
        return patients[patient].prescriptions[id];
    }

    function usePrescription(address patient, uint256 id) external onlyManager {
        require(id > 0 && id <= patients[patient].currentId, "Invalid id");
        require(patients[patient].prescriptions[id].valid, "Already used");

        patients[patient].prescriptions[id].valid = false;
    }
}

/*//////////////////////////////////////////////////////////////
                    AUTHORIZATION CERTIFICATES
//////////////////////////////////////////////////////////////*/
contract AuthorizationCertificates {
    address public admin;

    mapping(address => bool) internal authorizedHospitals;
    mapping(address => bool) internal authorizedManufacturers;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    function authorizeHospital(address hospital) external onlyAdmin {
        authorizedHospitals[hospital] = true;
    }

    function unauthorizeHospital(address hospital) external onlyAdmin {
        authorizedHospitals[hospital] = false;
    }

    function authorizeManufacturer(address manufacturer) external onlyAdmin {
        authorizedManufacturers[manufacturer] = true;
    }

    function unauthorizeManufacturer(address manufacturer) external onlyAdmin {
        authorizedManufacturers[manufacturer] = false;
    }

    function isAuthorizedHospital(address hospital) external view returns (bool) {
        return authorizedHospitals[hospital];
    }

    function isAuthorizedManufacturer(address manufacturer) external view returns (bool) {
        return authorizedManufacturers[manufacturer];
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid admin");
        admin = newAdmin;
    }
}

/*//////////////////////////////////////////////////////////////
                        PHARMA COMPANY
//////////////////////////////////////////////////////////////*/
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAuthorizationCertificates {
    function isAuthorizedHospital(address hospital) external view returns (bool);
}

interface IHospitalManagement {
    function authorizeSale(
        uint256 prescriptionId,
        address patient,
        string calldata medicine,
        uint256 amount
    ) external returns (bool);
}

contract PharmaCompany is ERC1155, ERC1155Burnable, Ownable {
    mapping(string => uint256) public medicines;
    mapping(uint256 => uint256) public prices;

    address public govAuthorizationContract;

    constructor(address _govAuthorizationContract)
        ERC1155("https://pharma.com/medicine/")
        Ownable(msg.sender)
    {
        govAuthorizationContract = _govAuthorizationContract;
    }

    function mint(
        uint256 id,
        uint256 amount,
        bytes memory data,
        string memory medicineName
    ) public onlyOwner {
        require(id != 0, "Invalid id");
        medicines[medicineName] = id;
        _mint(msg.sender, id, amount, data);
    }

    function mintBatch(
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data,
        string[] memory medicineNames
    ) public onlyOwner {
        require(ids.length == medicineNames.length, "Length mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] != 0, "Invalid id");
            medicines[medicineNames[i]] = ids[i];
        }

        _mintBatch(msg.sender, ids, amounts, data);
    }

    function buyMedicine(
        string memory medicineName,
        address hospital,
        uint256 prescriptionId,
        address to,
        uint256 amount
    ) external payable {
        require(
            IAuthorizationCertificates(govAuthorizationContract)
                .isAuthorizedHospital(hospital),
            "Hospital not authorized"
        );

        uint256 id = medicines[medicineName];
        require(id != 0, "Medicine not found");
        require(balanceOf(owner(), id) >= amount, "Insufficient stock");
        require(msg.value == amount * prices[id], "Incorrect payment");

        bool authorized = IHospitalManagement(hospital).authorizeSale(
            prescriptionId,
            to,
            medicineName,
            amount
        );

        require(authorized, "Sale not authorized");

        _safeTransferFrom(owner(), to, id, amount, bytes(medicineName));
    }

    function updatePrice(uint256 id, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Invalid price");
        prices[id] = newPrice;
    }
}

/*//////////////////////////////////////////////////////////////
                    HOSPITAL MANAGEMENT
//////////////////////////////////////////////////////////////*/
interface IPrescriptions {
    function _prescribe(
        address doctor,
        address patient,
        string calldata medicine,
        uint256 dose
    ) external returns (uint256);

    function _getPrescription(
        address patient,
        uint256 id
    ) external view returns (Prescriptions.Prescription memory);

    function usePrescription(address patient, uint256 id) external;
}

interface IAuthorization {
    function isAuthorizedManufacturer(address manufacturer) external view returns (bool);
}

contract HospitalManagement {
    mapping(address => bool) public admins;
    uint256 internal adminsCount;

    mapping(address => bool) public doctors;

    address public prescriptionsContract;
    address public govAuthorizationContract;

    constructor(address _govAuthorizationContract) {
        admins[msg.sender] = true;
        adminsCount = 1;
        govAuthorizationContract = _govAuthorizationContract;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "Not admin");
        _;
    }

    function addAdmin(address newAdmin) external onlyAdmin {
        require(!admins[newAdmin], "Already admin");
        admins[newAdmin] = true;
        adminsCount++;
    }

    function removeAdmin(address admin) external onlyAdmin {
        require(admins[admin], "Not admin");
        require(adminsCount > 1, "At least one admin required");
        admins[admin] = false;
        adminsCount--;
    }

    function addDoctor(address newDoctor) external onlyAdmin {
        doctors[newDoctor] = true;
    }

    function removeDoctor(address doctor) external onlyAdmin {
        doctors[doctor] = false;
    }

    function prescribe(
        address patient,
        string memory medicine,
        uint256 dose
    ) external returns (uint256) {
        require(doctors[msg.sender], "Not doctor");
        return IPrescriptions(prescriptionsContract)._prescribe(
            msg.sender,
            patient,
            medicine,
            dose
        );
    }

    function getPrescription(
        address patient,
        uint256 prescriptionId
    ) external view returns (Prescriptions.Prescription memory) {
        require(
            doctors[msg.sender] || msg.sender == patient,
            "Not authorized"
        );

        return
            IPrescriptions(prescriptionsContract)._getPrescription(
                patient,
                prescriptionId
            );
    }

    function authorizeSale(
        uint256 prescriptionId,
        address patient,
        string memory medicine,
        uint256 amount
    ) external returns (bool) {
        require(
            IAuthorization(govAuthorizationContract)
                .isAuthorizedManufacturer(msg.sender),
            "Manufacturer not authorized"
        );

        Prescriptions.Prescription memory p =
            IPrescriptions(prescriptionsContract)._getPrescription(
                patient,
                prescriptionId
            );

        if (
            p.valid &&
            keccak256(bytes(p.medicine)) == keccak256(bytes(medicine)) &&
            amount == p.dose
        ) {
            IPrescriptions(prescriptionsContract).usePrescription(
                patient,
                prescriptionId
            );
            return true;
        }

        return false;
    }

    function setPrescriptionContract(address newPrescriptionContract)
        external
        onlyAdmin
    {
        prescriptionsContract = newPrescriptionContract;
    }
}
