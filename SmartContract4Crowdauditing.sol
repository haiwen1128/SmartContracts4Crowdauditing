pragma solidity ^0.4.18;

// SPDX-License-Identifier: SimPL-2.0

// Crowd Manage Smart Contract, denoted as CrowdManage
// Audit Task Smart Contract, denoted as ATContract

contract CrowdManage {
    uint public onlineCounter = 0;

    enum AuditorState { Offline, Online, Await, Busy}

    struct Auditor {
        bool registered;              // true: this auditor has registered.
        uint index;                   // the index of the auditor in the crowd, if it is registered

        AuditorState state;           // the state of the auditor in the crowd

        address ATAddr;               // the address of ATSC
        uint confirmTime;             // confirm the select in the state of Await. Otherwise, reputation -10.
        int8 reputation;
    }

    mapping(address => Auditor) crowdManage;
    address[] public auditorAddrs;     // the address pool of auditors

    struct SelectionInfo {
        bool valid;
        uint curBlkNum;   // the current block number 
        uint auditorNeed; // the number of needed auditors
        uint Random1;     // the random number comes from DO (Client)
        uint Random2;     // the random number comes from Service provider
    }

    mapping (address => SelectionInfo) ATContracts; // record the selected auditor's address 

    // record the provider _who, generates a ATSC contract of address _contractAddr at time _time
    event AuditorTask_Gen (address indexed _who, uint _time, address _contractAddr);

    // record the auditor _who selected for the contract _frowhom
    event AuditorSelected(address indexed _who, uint _index, address _forWhom);

    // check whether the auditor has already registered into crowd
    modifier checkRegister(address _register) {
        require(!crowdManage[_register].registered);
        _;
    }

    // check whether the auditor has registered
    modifier checkAuditor(address _auditor) {
        require(!crowdManage[_auditor].registered);
        _;
    }

    ////check whether it is a valid ATSC contract
    modifier checkATContract(address _atsc){
        require(ATContracts[_atsc].valid);
        _;
    }

    /**
     * Interface of Service Provider (SP)  
     * SP generate a ATSC contract
     */
    function genAuditorTaskContract() public returns (address) {
        address newAuditorTaskContract = new AuditTask(this, msg.sender, 0x0);
        ATContracts[newAuditorTaskContract].valid = true;
        AuditorTask_Gen(msg.sender, now, newAuditorTaskContract);
        return newAuditorTaskContract;
    }
    
    /**
     * Interface of Auditor 
     * check whether a AuditTask Smart Contract is valid
     */
    function validateAuditTask(address _AuditTask) public view returns (bool) {
        if(ATContracts[_AuditTask].valid)
            return true;
        else 
            return false;
    }

    /**
     * Interface of Client 
     * This is for the normal auditor to register as a witness into the pool
     */
    function register() public checkRegister(msg.sender) {
        crowdManage[msg.sender].index =  auditorAddrs.push(msg.sender) - 1;
        crowdManage[msg.sender].state = AuditorState.Offline;
        crowdManage[msg.sender].reputation = 100;
        crowdManage[msg.sender].registered = true;
    }
    
    /**
     * Interface of Contract
     * ATSC submit a auditor selection request.
     */
    function request (uint _auditorNeed, uint _random1, uint _random2) public checkATContract(msg.sender) returns (bool success) {
        ATContracts[msg.sender].auditorNeed = _auditorNeed;
        ATContracts[msg.sender].Random1 = _random1;
        ATContracts[msg.sender].Random2 = _random2;
        return true;
    } 
    
    /**
     * Interface of Contract
     * Request for a selection of _N witnesses. The _provider and _client must not be selected.
     */
    function unbiasedSelection(uint _N, uint _random1, uint _random2, address _provider, address _client) public checkATContract(msg.sender) returns (bool success) {
        require(ATContracts[msg.sender].curBlkNum != 0);
        require(onlineCounter >= _N+2);
        // require(onlineCounter > 10 * N);  //Used in more credible situation
        
        uint seed = _random1 + _random2;
        uint adtCounter = 0;
        while(adtCounter < _N) {
            address sAddr = auditorAddrs[seed % auditorAddrs.length];
            if(crowdManage[sAddr].state == AuditorState.Online 
            && crowdManage[sAddr].reputation > 0
            && sAddr != _provider 
            && sAddr != _client) {
                crowdManage[sAddr].state = AuditorState.Await;
                crowdManage[sAddr].confirmTime = now + 5 minutes;  // 5 minutes for the confirm of auditor in crowd 
                crowdManage[sAddr].ATAddr = msg.sender;
                AuditorSelected(sAddr, crowdManage[sAddr].index, msg.sender);
                onlineCounter --;
                adtCounter++;
            }
            seed = (uint)(keccak256(uint(seed)));
        }
        
        ATContracts[msg.sender].curBlkNum = 0;
        
        return true;
    }
    
    /**
     * Interface of Contract
     * Await auditor calls the AT Contract and confirm the selection
     */
    function confirm(address _await) public checkAuditor(_await) checkATContract(msg.sender) returns (bool) {
        
        // auditor in crowd has not reached the confirmation time.
        require(now < crowdManage[_await].confirmTime);
        
        // the state of auditor need to be Await.
        require(crowdManage[_await].state == AuditorState.Await);
        
        // only the audit task contrack can select it.
        require(crowdManage[_await].ATAddr == msg.sender);
        
        // change the state of auditor from await to busy.
        crowdManage[_await].state = AuditorState.Busy;
        
        return true;
    }
    
    /**
     * Interface of Contract
     * Audit Task contract ends and auditors calls the Interface from the contract to release the Busy auditors.
     * If the reputation smaller than 0, the auditor will be turned off.
     */
    function release(address _auditor) public checkAuditor(_auditor) checkATContract(msg.sender) {
        
        // only when the state is Busy
        require(crowdManage[_auditor].state == AuditorState.Busy);
        
        // on the AT Contract can calls this function
        require(crowdManage[_auditor].ATAddr == msg.sender); 
        
        // chage the state of auditor
        if(crowdManage[_auditor].reputation <= 0) {
            crowdManage[_auditor].state = AuditorState.Offline;
        } else {
            crowdManage[_auditor].state = AuditorState.Online;
            onlineCounter ++;
        }
    }
    
    /**
     * Interface of Contract
     * Decrease the reputation value
     */
    function reputationDecrease(address _auditor, int8 _repValue) public checkAuditor(_auditor) checkATContract(msg.sender) {
        // the reputation Decreased should be > 0
        require(_repValue > 0);
        
        // only the Audit Task constact can operate this function
        require(crowdManage[_auditor].ATAddr == msg.sender);
        
        crowdManage[_auditor].reputation -= _repValue;
    }
    
    /**
     * Interface of Auditor
     * Reject the selection to be await. Due to the ATCantract is not walid or someother thing.
     */
    function reject() public checkAuditor(msg.sender) {
        
        // only reject when the state in Await
        require(crowdManage[msg.sender].state == AuditorState.Await);
        
        // only reject when the time in confirmTime 
        require(now < crowdManage[msg.sender].confirmTime);
        
        // change the state from await to online
        crowdManage[msg.sender].state == AuditorState.Online;
        
        onlineCounter++;
    }
    
    /**
     * Interface of Auditor
     * Reverse its own state to Online after the confirmation deadline. But need to reduece the reputation.
     */
    function reverse() public checkAuditor(msg.sender) {
        
        // only when the confirmTime end 
        require(now > crowdManage[msg.sender].confirmTime);
        
        // only when the state is Await
        require(crowdManage[msg.sender].state == AuditorState.Await);
        
        // decrease the reputation
        crowdManage[msg.sender].reputation -= 10;
        
        // change the state according to reputation
        if(crowdManage[msg.sender].reputation <= 0) {
            crowdManage[msg.sender].state = AuditorState.Offline;
        } else {
            crowdManage[msg.sender].state = AuditorState.Online;
            onlineCounter++;
        }
    }
    
    /**
     * Interface of Auditor
     * turnOn the state to Online to wait for selection.
     */
    function turnOn() public checkAuditor(msg.sender) {
        
        // only when the state is Offline
        require(crowdManage[msg.sender].state == AuditorState.Offline); 
        
        // only when the reputation > 0
        require(crowdManage[msg.sender].reputation > 0);
        
        crowdManage[msg.sender].state = AuditorState.Online;
    }
    
    /**
     * Interface of Auditor
     * turnOff the state to Offline to avoid selection.
     */
    function turnOff() public checkAuditor(msg.sender) {
        
        // only when the state is online
        require(crowdManage[msg.sender].state == AuditorState.Online); 
        
        crowdManage[msg.sender].state = AuditorState.Offline;
    }
    
    /**
     * Interface of AuditorState
     * Used for auditor to check the state of some values.
     */
    function checkState(address _auditor) public view returns (CrowdManage.AuditorState, int8, uint, address) {
        return (crowdManage[_auditor].state, crowdManage[_auditor].reputation, crowdManage[_auditor].confirmTime, crowdManage[_auditor].ATAddr);
    }
}

// Audit Task Smart Contract (ATSC)
contract AuditTask {

    enum State { Init, Active, Cmt, Reveal, Completed }
    State public ATState;
    
    uint DataState; // 1 means that data is normal, 0 means that data is abnormal, 2 means that the data status has not been decided

    CrowdManage public cm;

    string public ATServiceDetail = "";
    
    // Time limitation of Two-Stage submission.
    uint public SubmitTime = 0;            // the begin time of the two-stage submission
    uint public CmtWindow = 2 minutes;     // the commitment window of two-stage submission.
    uint public RevealWindow = 3 minutes;  // the reveal window of two-stage submission.
    uint public CmtCounter = 0;
 
    uint public CompensationFee = 500 finney;  //0.5 ether
    uint public ServiceFee = 1 ether;
    uint public ServiceDuration = 10 minutes;  
    uint public ServiceEnd = 0;

    uint public AF4Nornal = 1 finney;          // the fee for the auditor if the data is normal.
    uint public AF4Abnormal = 5*AF4Nornal;      // the fee for the auditor if the data is abnormal.
    uint public PunishWhenAbnormal = 2 finney;  // punishment for the wrong result (normal) when data is abnormal
    uint public PunishWhenNormal = 1 finney;    // punishment for the wrong result (abnormal) when data is normal
    
    uint VoteFee = 0;                     // the fee for auditor to report there audit results.
    
    
    uint public AuditorNumber = 3;               // the number of auditors in AC
    uint public ConfirmNumRequired = 2;          // M: This is a number to indicate how many auditor needed to confirm the dicision

    uint SharedFee = (AuditorNumber * AF4Abnormal) / 2; 
    uint ReportTimeWin = 2 minutes;   // the time window for waiting all the witnesses to report a audit results
    uint ReportTimeBegin = 0;
    uint ConfirmNormalCount = 0;
    uint ConfirmAbnormalCount = 0;
    
    uint SharedBalance = 0;           //this is the balance to reward the AC auditors

    uint AcceptTimeWin = 2 minutes;   // the time window for waiting the client to accept this AT contract, otherwise the state of AT is transferred to Completed
    uint AcceptTimeEnd = 0;

    address public Client;
    uint ClientBalance = 0;
    uint CPrepayment = ServiceFee + SharedFee;

    address public Provider;
    uint ProviderBalance = 0;
    uint PPrepayment = SharedFee;
    
    uint Random1 = 0;
    uint Random2 = 0;
    
    address [] public auditorCommittee;  // This is the auditor committee

    struct AuditorAccount {
        bool selected;   // the auditor is or not selected
        uint dataState;  // The data states: true, false
        uint balance;    // the balance of the auditor
        uint cmt;        // the cmt in two-stage submission.
    }
    mapping(address => AuditorAccount) auditors;
    
    // this is the log of state of Audit Task 
    event ATStateChanged(address indexed _who, uint _time, State _newState);
    
    // this is the log of the report
    event ATIntegrityRep(address indexed _auditor, uint _time, uint _roundID);
    

    function AuditTask (CrowdManage _cManage, address _provider, address _client) public {
        Provider = _provider;
        Client = _client;
        cm = _cManage;
    }
    
    /**
     * The following functions are used for setting parameters instead of default ones
     */
    modifier checkState(State _state) {
        require(ATState == _state);
        _;
    }
    
    modifier checkProvider() {
        require(msg.sender == Provider);
        _;
    }
    
    modifier checkClient() {
        require(msg.sender == Client);
        _;
    }
    
    modifier checkMoney(uint _money) {
        require(msg.value == _money);
        _;
    }
    
    /**
     * check whether the sender is a legal auditor in the auditor committee
     */
    modifier checkAuditor() {
        require(auditors[msg.sender].selected);
        _;
    }
    
    modifier checkTimeIn(uint _endTime) {
        require (now < _endTime);
        _;
    }
    
    modifier checkCmtTime() {
        require(now < SubmitTime + CmtWindow);
        _;
    }
    
    modifier checkRevealTime() {
        require(SubmitTime + CmtWindow < now);
        require(now < SubmitTime + CmtWindow + RevealWindow);
        _;
    }
    
    modifier checkTimeOut(uint _endTime) {
        require(now > _endTime);
        _;
    }
    
    modifier checkBalance() {
        require(ClientBalance > 0);
        for (uint i = 0; i < auditorCommittee.length; i++) {
            require(auditors[auditorCommittee[i]].balance == 0);
        }
        _;
    }
    
    /**
     * check whether the result is efficiency
     */
    function setResult (uint _result, uint _random) public checkState(State.Cmt) checkRevealTime checkAuditor {
        require((uint)(keccak256(uint(_result + _random))) == auditors[msg.sender].cmt);
        auditors[msg.sender].dataState = _result;
    }
    
    /**
     * the uni is Szabo = 0.001 finney
     */
    function setCompensationFee(uint _compensationFee) public checkState(State.Init) checkProvider{
        require(_compensationFee > 0);
        uint oneUnit = 1 szabo;
        CompensationFee = _compensationFee*oneUnit;
    }
    
    function setServiceFee (uint _serviceFee) public checkState(State.Init) checkProvider {
        require(_serviceFee > 0);
        uint oneUint = 1 szabo;
        ServiceFee = _serviceFee*oneUint;
    }
    
    function setAuditorFee (uint _auditorFee) public checkState(State.Init) checkProvider {
        require(_auditorFee > 0);
        uint oneUint = 1 szabo;
        VoteFee = _auditorFee * oneUint;
    }
    
    // the unit is minutes
    function setServiceTime (uint _serviceDuration) public checkState(State.Init) checkProvider {
        require(_serviceDuration > 0);
        uint oneUnit = 1 minutes;
        ServiceDuration = _serviceDuration*oneUnit;
    }
    /**
     * The auditor number in AC, which is 'N'
     */
    function setACNumber(uint _acNumber)public checkState(State.Init) checkProvider {
        require(_acNumber > 2);
        require(_acNumber > auditorCommittee.length);
        AuditorNumber = _acNumber;
    }
    /**
     * The auditor number which need to report and be used to comfirm the decision, which is 'M'
     */
    function setConfirmNumber (uint _confirmNumber) public checkState(State.Init) checkProvider {
        // N/2 < M < N
        require(_confirmNumber > (AuditorNumber / 2));
        require(_confirmNumber < AuditorNumber);
        ConfirmNumRequired = _confirmNumber;
    }
    
    /**
     * Interface of Provider
     * set submitTime, cmtWindow, revealWindow of the two-stage submission  
     */
    function setSubmitTime (uint _submitTime) public checkState(State.Init) checkProvider {
        SubmitTime = _submitTime;
    }
    
    function setCmtWindow (uint _cmtWindow) public checkState(State.Init) checkProvider {
        CmtWindow = _cmtWindow;
    }
    
    function setRevealWindow (uint _revealWindow) public checkState(State.Init) checkProvider {
        RevealWindow = _revealWindow;
    }
    
    /**
     * set the client address
     */
    function setClient (address _client) public checkState(State.Init) checkProvider {
        Client = _client;
    }
    
    /**
     * SP publishes the audit detail
     */
    function publishAuditService(string _serviceDetail) public checkState(State.Init) checkProvider {
        ATServiceDetail = _serviceDetail;
    } 
      
    /**
     * SP sets up the AT Contract and wait for client to accept
     */ 
    function setupATContract() public payable checkState(State.Init) checkProvider checkMoney(PPrepayment) {
        require(AuditorNumber == auditorCommittee.length);
        ProviderBalance += msg.value;
        ATState = State.Init;
        AcceptTimeEnd = now + AcceptTimeWin;
        ATStateChanged(msg.sender, now, State.Init);
    }
    
    function concelAudit() public checkState(State.Completed) checkProvider checkTimeOut(AcceptTimeEnd) {
        if (ProviderBalance > 0) {
            msg.sender.transfer(ProviderBalance);
            ProviderBalance = 0;
        }
        ATState = State.Init;
    }
     
    /**
     * client accept the AT contract
     */
    function ConfirmAudit() public payable checkState(State.Init) checkClient checkTimeIn(AcceptTimeEnd) checkMoney(CPrepayment) {
        require(AuditorNumber == auditorCommittee.length);
        ClientBalance += msg.value;
        ATState = State.Active;
        ATStateChanged(msg.sender, now, State.Active);
        ServiceEnd = now + ServiceDuration;
        
        // transfer serviceFee from client to ProviderBalance
        ProviderBalance += ServiceFee;
        ClientBalance += ServiceFee;
        
        // setup the SharedBalance
        ProviderBalance -= SharedFee;
        ClientBalance -= SharedFee;
        SharedBalance += SharedFee*2;
    }
    
    /**
     * Interface of Client
     * Reset the audiotr state, who complete the report
     */
    function resetAuditor() public checkState(State.Active) checkClient checkTimeIn(ServiceEnd) {
        
        // the contract runs a while
        require(ReportTimeBegin != 0);
        
        // some auditors reported, the data is normal
        require(now > ReportTimeBegin + ReportTimeBegin);
        
        for (uint i = 0; i < auditorCommittee.length; i++) {
            if(auditors[auditorCommittee[i]].dataState == 0) {
                auditors[auditorCommittee[i]].dataState = 2;
                SharedBalance += auditors[auditorCommittee[i]].balance; //penalty
                auditors[auditorCommittee[i]].balance = 0;
                auditors[auditorCommittee[i]].cmt = 0;
                
                // the reputation of the auditor decreases by 1
                cm.reputationDecrease(auditorCommittee[i], 1);
            }
        }
        
        ConfirmAbnormalCount = 0;
        ConfirmNormalCount = 0;
        ReportTimeBegin = 0;
    }
    
    /**
     * Interface of auditor
     * submitCmt
     */
    function auditorSubmitCmt(uint _cmt) public checkAuditor checkCmtTime {
        
        // avoid a auditor sub cmt twice.
        if (auditors[msg.sender].cmt == 0) {
            auditors[msg.sender].cmt = _cmt;
        }
        
        CmtCounter++;
        
        // we set the number in our test.
        if(CmtCounter >= AuditorNumber -1) {
            ATState = State.Cmt;
            ATStateChanged (msg.sender, now, State.Cmt);
        }
    }
    
    /**
     * Interface of auditor
     * Reveal the result
     */
    function auditorSubmitResults(uint _result, uint _random) public checkState(State.Cmt) checkTimeIn(ServiceEnd) checkMoney(VoteFee) checkAuditor checkRevealTime {
        
        // one auditor submitted the cmt but not submit result twice;
        if(auditors[msg.sender].cmt != 0 && auditors[msg.sender].dataState == 2) {
            setResult(_result, _random);
        }
        
        if (auditors[msg.sender].dataState == 1) {   // data is abnormal
            ConfirmNormalCount++;
            if(ConfirmNormalCount >= ConfirmNumRequired) {
                ATState = State.Reveal;
                DataState = 1;
                ATStateChanged(msg.sender, now, State.Reveal);
            } 
        } else if (auditors[msg.sender].dataState == 0) {
            ConfirmAbnormalCount++;
            if(ConfirmAbnormalCount >= ConfirmNumRequired) {
                ATState = State.Reveal;
                DataState = 0;
                ATStateChanged(msg.sender, now, State.Reveal);
            } 
        }
        ATIntegrityRep(msg.sender, now, ServiceEnd);
        
        if(ATState == State.Reveal) {
            for(uint i = 0; i < auditorCommittee.length; i++) {
                if(DataState == 0 && auditors[auditorCommittee[i]].dataState == 0) {
                    auditors[auditorCommittee[i]].balance += VoteFee;
                } else if (DataState == 1 && auditors[auditorCommittee[i]].dataState == 1) {
                    auditors[auditorCommittee[i]].balance += VoteFee;
                }
            }
        }
    }
    
    /**
     * client end the AT contract and withdraw its compensation
     */
    function clientEndATandWithdraw() public checkState(State.Reveal) checkClient {
        ServiceEnd = now;
        
        if (now < ReportTimeBegin + ReportTimeWin) {
            ReportTimeBegin = now - ReportTimeWin;
        }
        
        for (uint i = 0; i < auditorCommittee.length; i++) {
            if(DataState == 1) {
                if(auditors[auditorCommittee[i]].dataState == 1) {
                    auditors[auditorCommittee[i]].balance += AF4Nornal;
                    SharedBalance -= AF4Nornal;
                } else {
                    auditors[auditorCommittee[i]].balance -= PunishWhenNormal;
                    SharedBalance += PunishWhenNormal;
                    cm.reputationDecrease(auditorCommittee[i], 1);
                } 
            } else if (DataState == 0) {
                if(auditors[auditorCommittee[i]].dataState == 0) {
                    auditors[auditorCommittee[i]].balance += AF4Abnormal;
                    SharedBalance -= AF4Abnormal;
                } else {
                    auditors[auditorCommittee[i]].balance -= PunishWhenAbnormal;
                    SharedBalance += PunishWhenAbnormal;
                    cm.reputationDecrease(auditorCommittee[i], 1);
                } 
            }
        }
        
        ClientBalance += CompensationFee;
        ProviderBalance -= CompensationFee;
        
        if(SharedBalance > 0) {
            ClientBalance += (SharedBalance/2);
            ProviderBalance += (SharedBalance/2);
        }
        
        SharedBalance = 0;
        
        ATState = State.Completed;
        ATStateChanged(msg.sender, now, State.Completed);
        
        if(ClientBalance > 0) {
            msg.sender.transfer(ClientBalance);
            ClientBalance = 0;
        }
    }
    
    function clinetWithdraw() public checkState(State.Completed) checkTimeOut(ServiceEnd) checkClient {
        require(ClientBalance > 0);
        msg.sender.transfer(ClientBalance);
        ClientBalance = 0;
    }
    
    function providerWithdraw() public checkState(State.Completed) checkTimeOut(ServiceEnd) checkProvider {
        require(ProviderBalance > 0); 
        msg.sender.transfer(ProviderBalance);
        ProviderBalance = 0;
    }
    
    /**
     * Interface of Provider
     */
    function providerEndATandWithdraw() public checkState(State.Active) checkTimeOut(ServiceEnd) checkProvider {
        for (uint i = 0; i < auditorCommittee.length; i++) {
            if(DataState == 1) {
                if(auditors[auditorCommittee[i]].dataState == 1) {
                    auditors[auditorCommittee[i]].balance += AF4Nornal;
                    SharedBalance -= AF4Nornal;
                } else {
                    auditors[auditorCommittee[i]].balance -= PunishWhenNormal;
                    SharedBalance += PunishWhenNormal;
                    cm.reputationDecrease(auditorCommittee[i], 1);
                } 
            } else if (DataState == 0) {
                if(auditors[auditorCommittee[i]].dataState == 0) {
                    auditors[auditorCommittee[i]].balance += AF4Abnormal;
                    SharedBalance -= AF4Abnormal;
                } else {
                    auditors[auditorCommittee[i]].balance -= PunishWhenAbnormal;
                    SharedBalance += PunishWhenAbnormal;
                    cm.reputationDecrease(auditorCommittee[i], 1);
                } 
            }
        }
        
        if(SharedBalance > 0) {
            ClientBalance += (SharedBalance / 2);
            ProviderBalance += (SharedBalance / 2);
        }
        SharedBalance = 0;
        ATStateChanged(msg.sender, now, State.Completed);
        
        if(ProviderBalance > 0) {
            msg.sender.transfer(ProviderBalance);
            ProviderBalance = 0;
        }
    }
    
    function auditorWithdraw() public checkState(State.Completed) checkTimeOut(ServiceEnd) checkAuditor {
        require(auditors[msg.sender].balance > 0);
        msg.sender.transfer(auditors[msg.sender].balance);
        auditors[msg.sender].balance = 0;
    }
    
    /**
     * restart AT contract without restarting the CrowdManage part
     */
    function retartAudit() public payable checkState(State.Completed) checkTimeOut(ServiceEnd) checkProvider checkBalance checkMoney(PPrepayment) {
        require(AuditorNumber == auditorCommittee.length);
        
        // reset all the related values
        ConfirmAbnormalCount = 0;
        ConfirmNormalCount = 0;
        ReportTimeBegin = 0;
        
        for (uint i=0; i < auditorCommittee.length; i++) {
            auditors[auditorCommittee[i]].cmt = 0;
            auditors[auditorCommittee[i]].dataState = 2;
        }
        
        ProviderBalance = msg.value;
        ATState = State.Init;
        AcceptTimeEnd = now + AcceptTimeWin;
        ATStateChanged(msg.sender, now, State.Init);
    } 
    
    /**
     * all auditors in the committee. Go back to the start state.
     */
    function resetAuditTask() public checkState(State.Completed) checkTimeOut(ServiceEnd) checkProvider checkBalance {
        
        // in case there are some unexpected errors happen, provider can withdraw all the money back anyway
        if(address(this).balance > 0) {
            msg.sender.transfer(address(this).balance);
        }   
        // reset all the related values
        ConfirmAbnormalCount = 0;
        ConfirmNormalCount = 0;
        ReportTimeBegin = 0;
        
        //reset the witness committee
        for(uint i = 0 ; i < auditorCommittee.length ; i++){
            cm.release(auditorCommittee[i]);
            delete auditors[auditorCommittee[i]];
        }
        
        delete auditorCommittee;
        
        ATState = State.Init;
        ATStateChanged(msg.sender, now, State.Init);
    }
    
    function requestSelection() public checkProvider returns (bool seccess) {
        require(cm.request(AuditorNumber, Random1, Random2));
        return true;
    }
    
    function selectFromCrowd(uint _N) public checkProvider returns (bool success) {
        require(AuditorNumber > auditorCommittee.length);
        require(AuditorNumber - auditorCommittee.length >= _N);
        require(Client != 0x0);
        require(cm.unbiasedSelection(_N, Random1, Random2, Provider, Client));
        return true;
    }
    
    function getCommitteeCount() public view returns (uint) {
        return auditorCommittee.length;
    }
    
    function auditorConfirm() public returns (bool) {
        require(!auditors[msg.sender].selected);
        
        require(msg.sender != Provider);
        require(msg.sender != Client);
        
        require(cm.confirm(msg.sender));
        auditorCommittee.push(msg.sender);
        auditors[msg.sender].selected = true;
        
        return true;
    }
    /**
     * the auditor has the right to leave the AT contract in following scenarios
     * 1. As long as not in the state of 'Active', "CMt" or 'Reveal'
     * 2. If it is the state of 'Init', the time should be out of the 'AcceptTimeEnd'
     */
    function auditorRelease() public checkAuditor {
        require(ATState != State.Active);
        
        require((ATState == State.Init && now > AcceptTimeEnd ) || ATState == State.Completed);
        
        uint index = auditorCommittee.length;
        for (uint i = 0; i < auditorCommittee.length; i++) {
            if (auditorCommittee[i] == msg.sender) {
                index = i;
            }
        }
        require(index != auditorCommittee.length);
        
        auditorCommittee[index] = auditorCommittee[auditorCommittee.length - 1];
        auditorCommittee.length--;
        delete auditors[msg.sender];
        cm.release(msg.sender);
    }  
}
