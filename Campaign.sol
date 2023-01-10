// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CodeCrownd {

    event NewCampaign(uint id, address indexed creator, uint minimum);
    event NewRequest(uint id, string description, address recipient, uint value);
    event Refund(uint id, address indexed caller, uint amount);
    event Cancel(uint id);
    event ClaimRequest(uint id);
    event CancelRequest(uint id, uint pledge);

    struct Campaign {
        mapping(uint => Request) requests;
        uint requestsCount;
        address manager;
        uint minimumContribution;
        mapping(address => bool) approvers;
        uint approversCount;
        bool active;
        uint pledged;
        uint approvalCount;
        mapping(address => bool) approvals;
        bool inClaimProcess;
        bool claimed;
        bool inCancelProcess;
        uint id;
    }

    struct Request {
        string description;
        uint valueR;
        address recipient;
        bool complete;
        uint approvalCount;
        mapping(address => bool) approvals;
        uint id;
    }

    mapping(uint => Campaign) public campaigns;
    uint public campaignCount;
    address public codeScript;
    mapping(uint => mapping(address => uint)) public pledgedAmount;
    ERC20 public immutable token;
    address public contractAddress;

    modifier restricted(uint _idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        require(msg.sender == campaign.manager, "You are not the manager of this campaign!");
        _;
    }

    constructor(address ownerCodeScript, ERC20 _token) {
        codeScript = ownerCodeScript;
        token = _token;
        contractAddress = address(this);
    }

    function createCampaign(uint _minimum) public {
        campaignCount += 1;
        Campaign storage newCampaign = campaigns[campaignCount]; 
        newCampaign.manager= msg.sender;
        newCampaign.minimumContribution= _minimum;
        newCampaign.approversCount= 0;
        newCampaign.active= true;
        newCampaign.id = campaignCount;
        emit NewCampaign(newCampaign.id, msg.sender, _minimum);
    }

    function contribute(uint _idCampaign,  uint _amount) public payable {
        Campaign storage campaign = campaigns[_idCampaign];
        require(_amount > campaign.minimumContribution, "You have to contribute the minimum value");
        require(campaign.manager != msg.sender, "Sorry but you can't contribute to your own campaign");
        require(!campaign.inCancelProcess, "This campaing is in cancel process");
        require(campaign.active, "Campaign is not active");

        campaign.approvers[msg.sender] = true;
        pledgedAmount[_idCampaign][msg.sender] += _amount;
        campaign.pledged += _amount;
        campaign.approversCount++;
        token.transferFrom(msg.sender, address(this), _amount);
    }

    function createCancelCampaignRequest(uint _idCampaign) external restricted(_idCampaign){
        Campaign storage campaign = campaigns[_idCampaign];
        campaign.inCancelProcess = true;
        emit CancelRequest(_idCampaign, campaign.pledged);
    }

    function cancelCampaign(uint _idCampaign) external restricted(_idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        require(campaign.inCancelProcess, "You have to initialize the cancel request first");
        require(campaign.active, "Campaign is not active");
        require(campaign.pledged == 0,"Campaing istill have founds in it, please refound all before deleting");
        require(campaign.manager == msg.sender, "Only the owner can delete the campaign");
        campaign.active = false;
        
        delete campaigns[_idCampaign];
        emit Cancel(_idCampaign);
    }

    function refund(uint _idCampaign) external {
        Campaign storage campaign = campaigns[_idCampaign];
        require(campaign.active, "Campaign is not active!");
        require(campaign.approvers[msg.sender], "You can only refound if you are a contributor!");

        uint contributorBalance = pledgedAmount[_idCampaign][msg.sender];
        pledgedAmount[_idCampaign][msg.sender] = 0;
        campaign.pledged = campaign.pledged - contributorBalance;
        token.transfer(msg.sender, contributorBalance);

        emit Refund(_idCampaign, msg.sender, contributorBalance);
    }

    function createRequest(string memory description, uint value, address recipient, uint _idCampaign) public restricted(_idCampaign) { 
        Campaign storage campaign = campaigns[_idCampaign];
        campaign.requestsCount += 1;
        Request storage newRequest = campaign.requests[campaign.requestsCount];
        newRequest.description = description;
        newRequest.valueR = value;
        newRequest.recipient= recipient;
        newRequest.complete= false;
        newRequest.approvalCount= 0;
        newRequest.id = campaign.requestsCount;
        campaign.requests[newRequest.id];
        emit NewRequest(campaign.requestsCount, description, recipient, value);
    }

    function approveRequest(uint _idRequest, uint _idCampaign) public {
        Campaign storage campaign = campaigns[_idCampaign];
        require(campaign.approvers[msg.sender],"You have to contribute first!");
        require(campaign.manager != msg.sender, "You can't approve your own request");
        Request storage request = campaign.requests[_idRequest];
        require(!request.approvals[msg.sender],"You aleredy aproved this request!");
        require(!request.complete, "This request has alredy been close");

        request.approvals[msg.sender] = true;
        request.approvalCount++;
    }

    function finalizeRequest(uint _idRequest, uint _idCampaign) public restricted(_idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        Request storage request = campaign.requests[_idRequest];

        require(request.approvalCount > (campaign.approversCount / 2), "This request is not accepted to be finalized");
        require(!request.complete,"This request has alredy been close");
        require(campaign.pledged >= request.valueR,"You have to first collect that amount of tokens in your campaign");

        request.complete = true;
        campaign.pledged = campaign.pledged - request.valueR;
        token.transfer(request.recipient, request.valueR);
    }

    function cancelRequest(uint _idRequest, uint _idCampaign) external restricted(_idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        Request storage request = campaign.requests[_idRequest];
        require(!request.complete, "Request already finalized");
            
        delete campaign.requests[_idRequest];
        emit Cancel(_idRequest);
    }

    function createClaimRequest(uint _idCampaign) public restricted(_idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        campaign.inClaimProcess = true;
        emit ClaimRequest(_idCampaign);
    }

    function approveClaimRequest(uint _idCampaign) public {
        Campaign storage campaign = campaigns[_idCampaign];
        require(campaign.approvers[msg.sender],"You have to contribute first!");
        require(!campaign.approvals[msg.sender],"You aleredy aproved this claim request!");
        require(campaign.inClaimProcess, "This campaign is not trying to be claimed");
        require(!campaign.claimed, "This campaign has alredy been claimed");
        require(campaign.manager != msg.sender, "You can't approve your own request");

        campaign.approvals[msg.sender] = true;
        campaign.approvalCount++;
    }

    function finalizeClaimRequest(uint _idCampaign) public restricted(_idCampaign) {
        Campaign storage campaign = campaigns[_idCampaign];
        require(campaign.approvalCount > (campaign.approversCount / 2), "This campaign is not accepted to be claimed");
        require(!campaign.claimed, "This campaign has alredy been claimed");
        require(campaign.inClaimProcess, "This campaign is not trying to be claimed");
        campaign.pledged = 0;
        campaign.claimed = true;
        campaign.active = false;
        campaign.inClaimProcess = false;
        token.transfer(campaign.manager, campaign.pledged);
    }

    function getRequetsInfoFromACampaign(uint _idRequest, uint _idCampaign) public view returns(string memory, uint, address, bool, uint, uint) {
        Campaign storage campaign = campaigns[_idCampaign];
        Request storage request = campaign.requests[_idRequest];
        return ( request.description,
            request.valueR,
            request.recipient,
            request.complete,
            request.approvalCount,
            request.id
        );
    }
    
}
