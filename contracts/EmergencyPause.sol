// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPausable {
    function pauseSystem() external;
    function resumeSystem() external;
}

contract EmergencyPause {
    address public owner;
    IPausable public holodomorPrevention;
    
    struct PauseProposal {
        address initiator;
        uint256 initiatedAt;
        uint256 votesRequired;
        uint256 votesReceived;
        bool executed;
        string reason;
    }
    
    struct CircuitBreaker {
        uint256 threshold;
        bool triggered;
        uint256 triggeredAt;
        string condition;
    }
    
    mapping(uint256 => PauseProposal) public pauseProposals;
    mapping(uint256 => mapping(address => bool)) public pauseVotes;
    mapping(string => CircuitBreaker) public circuitBreakers;
    mapping(address => bool) public emergencyOperators;
    
    uint256 public proposalCounter;
    uint256 public pauseThreshold = 5; // Number of votes required
    uint256 public pauseDuration = 24 hours;
    uint256 public lastPauseTime;
    bool public systemPaused;
    
    string[] public circuitBreakerTypes = [
        "LOW_PRODUCTION",
        "HIGH_MORTALITY", 
        "MASS_DISPLACEMENT",
        "SUPPLY_SHORTAGE"
    ];
    
    event EmergencyPauseInitiated(uint256 proposalId, address initiator, string reason);
    event PauseVoteSubmitted(uint256 proposalId, address voter);
    event SystemPaused(uint256 timestamp, string reason);
    event SystemResumed(uint256 timestamp);
    event CircuitBreakerTriggered(string breakerType, uint256 timestamp);
    event CircuitBreakerReset(string breakerType, uint256 timestamp);
    event ThresholdUpdated(uint256 newThreshold);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }
    
    modifier onlyOperator() {
        require(emergencyOperators[msg.sender] || msg.sender == owner, "Not authorized");
        _;
    }
    
    modifier notPaused() {
        require(!systemPaused, "System already paused");
        _;
    }
    
    constructor(address _holodomorPrevention) {
        owner = msg.sender;
        holodomorPrevention = IPausable(_holodomorPrevention);
        
        // Initialize circuit breakers
        circuitBreakers["LOW_PRODUCTION"] = CircuitBreaker({
            threshold: 500000, // tonnes
            triggered: false,
            triggeredAt: 0,
            condition: "Production below critical threshold"
        });
        
        circuitBreakers["HIGH_MORTALITY"] = CircuitBreaker({
            threshold: 1000, // deaths per day
            triggered: false,
            triggeredAt: 0,
            condition: "Mortality rate exceeds threshold"
        });
        
        circuitBreakers["MASS_DISPLACEMENT"] = CircuitBreaker({
            threshold: 10000, // people displaced
            triggered: false,
            triggeredAt: 0,
            condition: "Mass displacement detected"
        });
        
        circuitBreakers["SUPPLY_SHORTAGE"] = CircuitBreaker({
            threshold: 30, // days of supply remaining
            triggered: false,
            triggeredAt: 0,
            condition: "Critical supply shortage"
        });
    }
    
    function addEmergencyOperator(address _operator) external onlyOwner {
        emergencyOperators[_operator] = true;
    }
    
    function removeEmergencyOperator(address _operator) external onlyOwner {
        emergencyOperators[_operator] = false;
    }
    
    function initiateEmergencyPause() external onlyOperator notPaused returns (uint256) {
        return _initiateEmergencyPause("Emergency pause initiated by operator");
    }
    
    function initiateEmergencyPause(string memory _reason) external onlyOperator notPaused returns (uint256) {
        return _initiateEmergencyPause(_reason);
    }
    
    function _initiateEmergencyPause(string memory _reason) internal returns (uint256) {
        proposalCounter++;
        
        pauseProposals[proposalCounter] = PauseProposal({
            initiator: msg.sender,
            initiatedAt: block.timestamp,
            votesRequired: pauseThreshold,
            votesReceived: 1,
            executed: false,
            reason: _reason
        });
        
        pauseVotes[proposalCounter][msg.sender] = true;
        
        emit EmergencyPauseInitiated(proposalCounter, msg.sender, _reason);
        
        if (pauseThreshold == 1) {
            _executePause(proposalCounter);
        }
        
        return proposalCounter;
    }
    
    function voteForPause(uint256 _proposalId) external onlyOperator {
        PauseProposal storage proposal = pauseProposals[_proposalId];
        require(proposal.initiatedAt > 0, "Invalid proposal");
        require(!proposal.executed, "Already executed");
        require(!pauseVotes[_proposalId][msg.sender], "Already voted");
        require(block.timestamp <= proposal.initiatedAt + 1 hours, "Voting period expired");
        
        pauseVotes[_proposalId][msg.sender] = true;
        proposal.votesReceived++;
        
        emit PauseVoteSubmitted(_proposalId, msg.sender);
        
        if (proposal.votesReceived >= proposal.votesRequired) {
            _executePause(_proposalId);
        }
    }
    
    function _executePause(uint256 _proposalId) internal {
        PauseProposal storage proposal = pauseProposals[_proposalId];
        require(!proposal.executed, "Already executed");
        
        proposal.executed = true;
        systemPaused = true;
        lastPauseTime = block.timestamp;
        
        holodomorPrevention.pauseSystem();
        
        emit SystemPaused(block.timestamp, proposal.reason);
    }
    
    function activateCircuitBreaker(string memory _breakerType, uint256 _currentValue) external onlyOperator {
        CircuitBreaker storage breaker = circuitBreakers[_breakerType];
        require(breaker.threshold > 0, "Invalid breaker type");
        require(!breaker.triggered, "Already triggered");
        
        if (_shouldTriggerBreaker(_breakerType, _currentValue)) {
            breaker.triggered = true;
            breaker.triggeredAt = block.timestamp;
            
            _initiateEmergencyPause(breaker.condition);
            
            emit CircuitBreakerTriggered(_breakerType, block.timestamp);
        }
    }
    
    function _shouldTriggerBreaker(string memory _breakerType, uint256 _value) internal view returns (bool) {
        CircuitBreaker memory breaker = circuitBreakers[_breakerType];
        
        if (keccak256(bytes(_breakerType)) == keccak256(bytes("LOW_PRODUCTION"))) {
            return _value < breaker.threshold;
        } else {
            return _value > breaker.threshold;
        }
    }
    
    function resetCircuitBreaker(string memory _breakerType) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[_breakerType];
        require(breaker.triggered, "Not triggered");
        require(block.timestamp >= breaker.triggeredAt + pauseDuration, "Cool-down period not met");
        
        breaker.triggered = false;
        breaker.triggeredAt = 0;
        
        emit CircuitBreakerReset(_breakerType, block.timestamp);
    }
    
    function resumeSystem() external onlyOwner {
        require(systemPaused, "System not paused");
        require(block.timestamp >= lastPauseTime + pauseDuration, "Pause duration not met");
        
        // Check all circuit breakers are reset
        for (uint256 i = 0; i < circuitBreakerTypes.length; i++) {
            require(!circuitBreakers[circuitBreakerTypes[i]].triggered, "Circuit breaker still active");
        }
        
        systemPaused = false;
        holodomorPrevention.resumeSystem();
        
        emit SystemResumed(block.timestamp);
    }
    
    function setThresholds(uint256 _pauseThreshold, uint256 _pauseDuration) external onlyOwner {
        require(_pauseThreshold > 0 && _pauseThreshold <= 10, "Invalid pause threshold");
        require(_pauseDuration >= 1 hours && _pauseDuration <= 7 days, "Invalid pause duration");
        
        pauseThreshold = _pauseThreshold;
        pauseDuration = _pauseDuration;
        
        emit ThresholdUpdated(_pauseThreshold);
    }
    
    function updateCircuitBreakerThreshold(string memory _breakerType, uint256 _newThreshold) external onlyOwner {
        CircuitBreaker storage breaker = circuitBreakers[_breakerType];
        require(breaker.threshold > 0, "Invalid breaker type");
        require(!breaker.triggered, "Cannot update while triggered");
        
        breaker.threshold = _newThreshold;
    }
    
    function getSystemStatus() external view returns (
        bool isPaused,
        uint256 pauseTime,
        uint256 timeUntilResume,
        uint256 activeProposals
    ) {
        isPaused = systemPaused;
        pauseTime = lastPauseTime;
        
        if (systemPaused && block.timestamp < lastPauseTime + pauseDuration) {
            timeUntilResume = (lastPauseTime + pauseDuration) - block.timestamp;
        } else {
            timeUntilResume = 0;
        }
        
        activeProposals = 0;
        for (uint256 i = 1; i <= proposalCounter; i++) {
            if (!pauseProposals[i].executed && 
                block.timestamp <= pauseProposals[i].initiatedAt + 1 hours) {
                activeProposals++;
            }
        }
    }
    
    function getCircuitBreakerStatus(string memory _breakerType) external view returns (
        uint256 threshold,
        bool triggered,
        uint256 triggeredAt,
        string memory condition
    ) {
        CircuitBreaker memory breaker = circuitBreakers[_breakerType];
        return (breaker.threshold, breaker.triggered, breaker.triggeredAt, breaker.condition);
    }
}