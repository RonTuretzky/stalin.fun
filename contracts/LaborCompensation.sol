// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract LaborCompensation {
    address public owner;
    address public holodomorPrevention;
    
    struct WorkerCompensation {
        uint256 baseWage;
        uint256 owedAmount;
        uint256 lastPayment;
        bool isActive;
        bool isDeported;
    }
    
    mapping(address => WorkerCompensation) public workerCompensation;
    mapping(address => bool) public authorizedPayers;
    
    uint256 public minimumWage;
    uint256 public compensationFund;
    bool public compensationFrozen;
    bool public deportationsPaused;
    
    uint256 public totalWorkersRegistered;
    uint256 public totalCompensationDistributed;
    
    event CompensationSet(address worker, uint256 wage);
    event CompensationFrozen(uint256 timestamp);
    event CompensationUnfrozen(uint256 timestamp);
    event PaymentDistributed(address worker, uint256 amount);
    event DeportationsPaused(uint256 timestamp);
    event DeportationsResumed(uint256 timestamp);
    event MinimumWageUpdated(uint256 newWage);
    event WorkerDeportationBlocked(address worker);
    event CompensationFundReplenished(uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyAuthorized() {
        require(
            msg.sender == owner || 
            msg.sender == holodomorPrevention ||
            authorizedPayers[msg.sender],
            "Not authorized"
        );
        _;
    }
    
    modifier notFrozen() {
        require(!compensationFrozen, "Compensation frozen");
        _;
    }
    
    modifier deportationsNotPaused() {
        require(!deportationsPaused, "Deportations paused");
        _;
    }
    
    constructor(uint256 _minimumWage) {
        owner = msg.sender;
        minimumWage = _minimumWage;
        deportationsPaused = false;
        compensationFrozen = false;
    }
    
    function setHolodomorPrevention(address _holodomorPrevention) external onlyOwner {
        holodomorPrevention = _holodomorPrevention;
    }
    
    function addAuthorizedPayer(address _payer) external onlyOwner {
        authorizedPayers[_payer] = true;
    }
    
    function setMinimumWage(uint256 _minimumWage) external onlyOwner notFrozen {
        require(_minimumWage > 0, "Invalid minimum wage");
        minimumWage = _minimumWage;
        emit MinimumWageUpdated(_minimumWage);
    }
    
    function registerWorker(address _worker, uint256 _baseWage) external onlyOwner notFrozen {
        require(_baseWage >= minimumWage, "Wage below minimum");
        require(!workerCompensation[_worker].isActive, "Worker already registered");
        
        workerCompensation[_worker] = WorkerCompensation({
            baseWage: _baseWage,
            owedAmount: 0,
            lastPayment: block.timestamp,
            isActive: true,
            isDeported: false
        });
        
        totalWorkersRegistered++;
        emit CompensationSet(_worker, _baseWage);
    }
    
    function setCompensation(address _worker, uint256 _wage) external onlyOwner notFrozen {
        require(_wage >= minimumWage, "Wage below minimum");
        require(workerCompensation[_worker].isActive, "Worker not registered");
        require(!workerCompensation[_worker].isDeported, "Worker deported");
        
        workerCompensation[_worker].baseWage = _wage;
        emit CompensationSet(_worker, _wage);
    }
    
    function freezeCompensation() external onlyAuthorized {
        compensationFrozen = true;
        emit CompensationFrozen(block.timestamp);
    }
    
    function unfreezeCompensation() external onlyOwner {
        compensationFrozen = false;
        emit CompensationUnfrozen(block.timestamp);
    }
    
    function calculateOwedAmount(address _worker) public view returns (uint256) {
        WorkerCompensation memory worker = workerCompensation[_worker];
        if (!worker.isActive || worker.isDeported) return 0;
        
        uint256 timeElapsed = block.timestamp - worker.lastPayment;
        uint256 periodsElapsed = timeElapsed / 30 days; // Monthly payments
        
        return worker.owedAmount + (worker.baseWage * periodsElapsed);
    }
    
    function distributePayments(address[] calldata _workers) external onlyAuthorized notFrozen {
        require(compensationFund > 0, "No funds available");
        
        for (uint256 i = 0; i < _workers.length; i++) {
            address worker = _workers[i];
            require(workerCompensation[worker].isActive, "Worker not active");
            require(!workerCompensation[worker].isDeported, "Worker deported");
            
            uint256 owed = calculateOwedAmount(worker);
            if (owed > 0 && compensationFund >= owed) {
                compensationFund -= owed;
                workerCompensation[worker].owedAmount = 0;
                workerCompensation[worker].lastPayment = block.timestamp;
                
                payable(worker).transfer(owed);
                totalCompensationDistributed += owed;
                
                emit PaymentDistributed(worker, owed);
            }
        }
    }
    
    function distributeCompensation(address _recipient, uint256 _amount) external onlyAuthorized {
        require(compensationFund >= _amount, "Insufficient funds");
        
        compensationFund -= _amount;
        payable(_recipient).transfer(_amount);
        totalCompensationDistributed += _amount;
        
        emit PaymentDistributed(_recipient, _amount);
    }
    
    function pauseDeportations() external onlyAuthorized {
        deportationsPaused = true;
        emit DeportationsPaused(block.timestamp);
    }
    
    function resumeDeportations() external onlyOwner {
        require(deportationsPaused, "Not paused");
        deportationsPaused = false;
        emit DeportationsResumed(block.timestamp);
    }
    
    function markForDeportation(address _worker) external onlyOwner deportationsNotPaused {
        require(workerCompensation[_worker].isActive, "Worker not active");
        
        uint256 owed = calculateOwedAmount(_worker);
        require(owed == 0, "Cannot deport with unpaid wages");
        
        workerCompensation[_worker].isDeported = true;
    }
    
    function blockDeportation(address _worker) external onlyAuthorized {
        require(workerCompensation[_worker].isActive, "Worker not active");
        require(workerCompensation[_worker].isDeported, "Not marked for deportation");
        
        workerCompensation[_worker].isDeported = false;
        emit WorkerDeportationBlocked(_worker);
    }
    
    function ensureCompensationFunded(uint256 _amount) external view returns (bool) {
        return compensationFund >= _amount;
    }
    
    function replenishCompensationFund() external payable {
        compensationFund += msg.value;
        emit CompensationFundReplenished(msg.value);
    }
    
    function emergencyPayment(address _worker) external onlyOwner {
        require(workerCompensation[_worker].isActive, "Worker not active");
        
        uint256 emergencyAmount = workerCompensation[_worker].baseWage;
        require(compensationFund >= emergencyAmount, "Insufficient funds");
        
        compensationFund -= emergencyAmount;
        payable(_worker).transfer(emergencyAmount);
        
        emit PaymentDistributed(_worker, emergencyAmount);
    }
    
    function getWorkerStatus(address _worker) external view returns (
        bool isActive,
        bool isDeported,
        uint256 baseWage,
        uint256 owedAmount,
        uint256 lastPayment
    ) {
        WorkerCompensation memory worker = workerCompensation[_worker];
        return (
            worker.isActive,
            worker.isDeported,
            worker.baseWage,
            calculateOwedAmount(_worker),
            worker.lastPayment
        );
    }
}