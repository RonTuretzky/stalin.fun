// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFoodProductionOracle {
    function getRegionProduction(bytes32 region) external view returns (uint256);
    function getTotalProduction() external view returns (uint256);
}

interface ILaborCompensation {
    function ensureCompensationFunded(uint256 amount) external view returns (bool);
    function distributeCompensation(address recipient, uint256 amount) external;
}

contract GrainRequisition {
    address public owner;
    address public holodomorPrevention;
    IFoodProductionOracle public productionOracle;
    ILaborCompensation public laborCompensation;
    
    uint256 public requisitionBudget;
    uint256 public budgetSpent;
    bool public budgetFrozen;
    bool public requisitionsPaused;
    
    struct RequisitionOrder {
        bytes32 region;
        uint256 amount;
        uint256 compensationPerUnit;
        uint256 timestamp;
        address authorizedBy;
        bool executed;
        bool cancelled;
    }
    
    mapping(uint256 => RequisitionOrder) public requisitionOrders;
    mapping(bytes32 => uint256) public regionRequisitioned;
    mapping(address => uint256) public farmerCompensationOwed;
    
    uint256 public orderCounter;
    uint256 public constant MAX_REQUISITION_PERCENTAGE = 20; // Max 20% of production
    uint256 public constant MIN_COMPENSATION_RATE = 100; // Min price per unit
    
    event BudgetSet(uint256 newBudget);
    event BudgetFrozen(uint256 timestamp);
    event BudgetUnfrozen(uint256 timestamp);
    event RequisitionOrderCreated(uint256 orderId, bytes32 region, uint256 amount);
    event RequisitionExecuted(uint256 orderId, address farmer, uint256 compensation);
    event RequisitionsPaused(uint256 timestamp);
    event RequisitionsResumed(uint256 timestamp);
    event CompensationDistributed(address farmer, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyAuthorized() {
        require(
            msg.sender == owner || 
            msg.sender == holodomorPrevention,
            "Not authorized"
        );
        _;
    }
    
    modifier whenNotPaused() {
        require(!requisitionsPaused, "Requisitions paused");
        _;
    }
    
    modifier budgetNotFrozen() {
        require(!budgetFrozen, "Budget is frozen");
        _;
    }
    
    constructor(address _productionOracle, address _laborCompensation) {
        owner = msg.sender;
        productionOracle = IFoodProductionOracle(_productionOracle);
        laborCompensation = ILaborCompensation(_laborCompensation);
    }
    
    function setHolodomorPrevention(address _holodomorPrevention) external onlyOwner {
        holodomorPrevention = _holodomorPrevention;
    }
    
    function setRequisitionBudget(uint256 _budget) external onlyOwner budgetNotFrozen {
        requisitionBudget = _budget;
        emit BudgetSet(_budget);
    }
    
    function freezeBudget() external onlyAuthorized {
        budgetFrozen = true;
        emit BudgetFrozen(block.timestamp);
    }
    
    function unfreezeBudget() external onlyOwner {
        budgetFrozen = false;
        emit BudgetUnfrozen(block.timestamp);
    }
    
    function createRequisitionOrder(
        bytes32 _region,
        uint256 _amount,
        uint256 _compensationPerUnit
    ) external onlyOwner whenNotPaused budgetNotFrozen returns (uint256) {
        require(_compensationPerUnit >= MIN_COMPENSATION_RATE, "Compensation below minimum");
        
        uint256 regionProduction = productionOracle.getRegionProduction(_region);
        require(regionProduction > 0, "No production data for region");
        
        uint256 maxAllowedRequisition = (regionProduction * MAX_REQUISITION_PERCENTAGE) / 100;
        uint256 alreadyRequisitioned = regionRequisitioned[_region];
        
        require(
            alreadyRequisitioned + _amount <= maxAllowedRequisition,
            "Exceeds maximum requisition percentage"
        );
        
        uint256 totalCost = _amount * _compensationPerUnit;
        require(budgetSpent + totalCost <= requisitionBudget, "Exceeds budget");
        
        require(
            laborCompensation.ensureCompensationFunded(totalCost),
            "Compensation not funded"
        );
        
        orderCounter++;
        requisitionOrders[orderCounter] = RequisitionOrder({
            region: _region,
            amount: _amount,
            compensationPerUnit: _compensationPerUnit,
            timestamp: block.timestamp,
            authorizedBy: msg.sender,
            executed: false,
            cancelled: false
        });
        
        regionRequisitioned[_region] += _amount;
        budgetSpent += totalCost;
        
        emit RequisitionOrderCreated(orderCounter, _region, _amount);
        return orderCounter;
    }
    
    function executeRequisition(uint256 _orderId, address _farmer) external whenNotPaused {
        RequisitionOrder storage order = requisitionOrders[_orderId];
        require(!order.executed, "Order already executed");
        require(!order.cancelled, "Order cancelled");
        
        uint256 compensation = order.amount * order.compensationPerUnit;
        farmerCompensationOwed[_farmer] += compensation;
        
        order.executed = true;
        
        laborCompensation.distributeCompensation(_farmer, compensation);
        
        emit RequisitionExecuted(_orderId, _farmer, compensation);
        emit CompensationDistributed(_farmer, compensation);
    }
    
    function cancelRequisitionOrder(uint256 _orderId) external onlyOwner {
        RequisitionOrder storage order = requisitionOrders[_orderId];
        require(!order.executed, "Order already executed");
        require(!order.cancelled, "Order already cancelled");
        
        order.cancelled = true;
        regionRequisitioned[order.region] -= order.amount;
        budgetSpent -= (order.amount * order.compensationPerUnit);
    }
    
    function pauseRequisitions() external onlyAuthorized {
        requisitionsPaused = true;
        emit RequisitionsPaused(block.timestamp);
    }
    
    function resumeRequisitions() external onlyOwner {
        require(requisitionsPaused, "Not paused");
        
        uint256 totalProduction = productionOracle.getTotalProduction();
        require(totalProduction >= 2000000, "Production too low to resume");
        
        requisitionsPaused = false;
        emit RequisitionsResumed(block.timestamp);
    }
    
    function getRequisitionStatus(bytes32 _region) external view returns (
        uint256 production,
        uint256 requisitioned,
        uint256 maxAllowed,
        bool canRequisition
    ) {
        production = productionOracle.getRegionProduction(_region);
        requisitioned = regionRequisitioned[_region];
        maxAllowed = (production * MAX_REQUISITION_PERCENTAGE) / 100;
        canRequisition = !requisitionsPaused && !budgetFrozen && requisitioned < maxAllowed;
    }
    
    function emergencyCompensation(address[] calldata _farmers, uint256[] calldata _amounts) 
        external onlyOwner {
        require(_farmers.length == _amounts.length, "Array mismatch");
        
        for (uint256 i = 0; i < _farmers.length; i++) {
            farmerCompensationOwed[_farmers[i]] += _amounts[i];
            laborCompensation.distributeCompensation(_farmers[i], _amounts[i]);
            emit CompensationDistributed(_farmers[i], _amounts[i]);
        }
    }
}