pragma solidity ^0.4.16;
import './api.sol';
import './strings.sol';

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * function, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;
  
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender account. 
   */
  constructor() public {
    owner = msg.sender;
  }

  /** 
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /** 
   * @dev Allow the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) public onlyOwner() {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }
}

/**
 * @title Blacksheep
 * @dev The Blacksheep contract has functionality for admin to add multiple questions and answer and other options like intitial_start_date, no_of_days_submit, no_of_days_commit, no_of_days_before_result, no_of_days_result_active in contract. user can vote for questions and win ether.
 */
contract Blacksheep is Ownable {
  using strings for *;
  DateTimeAPI private dateTimeUtils;
  
  event logTransfer(address from, address to, uint amount);
  event logQuestionInfo(string info, uint q_id);
  event logQuestionCycle(string info, uint q_id);
  event logQuestionCycleCommit(string info, uint[] q_id);
  event logBoolEvent(string info, bool _condition);

  uint public TOTAL_NofQUESTIONS = 1; // total count of questions updated each time admin updates questions db.
  uint public CYCLE_ID = 1; // total count of questions cycle each time result is calculated.
  uint public _totalWithdrawableAmount = 0; // total count of questions cycle each time result is calculated.
  
  enum Status { submitted, committed, failedcommit, resultdeclared } // submitted, committed, failedcommit, resultdeclared
  
  mapping (address => uint) public userBalance;
  
  struct Question {
    string QuestionText; // question
    string Answers; // "lorem ipsum, lorem ipsum"
    uint AnswerCount; // number of options avaliable
    uint NofAnswersLimit; // number of user can attemp question
    uint IntitialStartDate; // First time start date 1528191889
    uint NofDays_Submit; // 6 i.e.x sec
    uint NofDays_Commit; // 2
    uint NofDays_BeforeResult; // 1
    uint NofDays_RepeatAfterResult; // 20
    uint RepeatCount; // number of time question repeat
    uint Cost; // cost of question in kwei
    uint repeatFlag;
  }
  
  // QUESTIONS: array of Question, where QID is assumed to be an integer....0,1,2....
  // Each Question is added to "QUESTIONS" from the Admin be calling a writeable SC method addQuestions(QueStr as string)
  mapping (uint => Question) public QUESTIONS;
  
  struct QuestionCycle {
    uint CID; // CID is cycle ID
    uint QID; // QID is question ID
    uint currentStartDate; //Current new start date, First time it is same as intitialStartDate, updated by result-declaration
    uint currentSubmitEndDate; // Updated when question first triggered
    uint currentCommitDateStart;
    uint currentCommitDateEnd;
    uint currentResultDate;
    uint nextStartDate;
    address[] usersAnswered; // array of UIDs who attempted the Que {UIDs... }
    address[] usersCommitted; // array of UIDs who committed the Que {UIDs... }
    string[] committedAnswerTexts; //array of committed answer texts
    uint NofAnswersGiven;
    uint NofAnswersLimit;
    bool rewardCalculated;
    string winningAnswer;
  }
  
  // The addQuestions method not only adds each question to the "QUESTIONS" array, but also adds the same Question to the 
  // "CURRENT_Questions" array with the appropriate dates. 
  // So every question will be in the CURRENT_Questions array with the current or upcoming dates setup and will be used
  // to maintain UIDs of users answering the question.
  // uint is QID of QUESTIONS
  mapping (uint => QuestionCycle) public CURRENT_Questions;
  
  struct UserAnswer {
    Status status;
    address sender;
    uint submittedDate;
    uint committedDate;
    uint resultDate;
    string answer;
  }
  
  // uint is QID of QUESTIONS
  mapping(uint => UserAnswer) public QIDAnswers; // Question wise Answers (persumably for one user)
  
  // Per User answer data
  struct UserAnswers {
    Status status;
    uint UserSubmittedQuestions; // CID submitted by one User
    uint UserCommittedQuestions; // CID committed by one User
    uint submittedDate;
    uint committedDate;
    uint resultDate;
    string answer;
    bool submitted;
    bool committed;
  }
  
  mapping(address => UserAnswers[]) public CURRENT_UserAnswers; //All questions answered by each user
  
  constructor(address _address) public {
    dateTimeUtils = DateTimeAPI(_address);
  }
  
  function addQuestions (
    string _QuestionText,
    string _Answers,
    uint _AnswerCount,
    uint _NofAnswersLimit,
    uint _IntitialStartDate,
    uint _NofDays_Submit,
    uint _NofDays_Commit,
    uint _NofDays_BeforeResult,
    uint _NofDays_RepeatAfterResult,
    uint _RepeatCount,
    uint _Cost
  ) public onlyOwner returns (bool success) {
    //require(bytes(_QuestionText).length > 0 && bytes(_Answers).length > 0,  "Values cannot be blank");  
    QUESTIONS[TOTAL_NofQUESTIONS].QuestionText = _QuestionText;
    QUESTIONS[TOTAL_NofQUESTIONS].Answers = _Answers;
    QUESTIONS[TOTAL_NofQUESTIONS].AnswerCount = _AnswerCount;
    QUESTIONS[TOTAL_NofQUESTIONS].NofAnswersLimit = _NofAnswersLimit;
    QUESTIONS[TOTAL_NofQUESTIONS].IntitialStartDate = _IntitialStartDate;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_Submit = _NofDays_Submit;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_Commit = _NofDays_Commit;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_BeforeResult = _NofDays_BeforeResult;
    QUESTIONS[TOTAL_NofQUESTIONS].NofDays_RepeatAfterResult = _NofDays_RepeatAfterResult;
    QUESTIONS[TOTAL_NofQUESTIONS].RepeatCount = _RepeatCount;
    QUESTIONS[TOTAL_NofQUESTIONS].Cost = _Cost;
    QUESTIONS[TOTAL_NofQUESTIONS].repeatFlag = 1;
    
    addQuestionCycle(CYCLE_ID, TOTAL_NofQUESTIONS);
    
    return true;
  }
  
  function addQuestionCycle(
    uint _cid,
    uint _qid
  ) internal onlyOwner returns(bool success) {
    require(_cid != 0 && _qid != 0, "Values cannot be blank");  
    CURRENT_Questions[_cid].CID = _cid;
    CURRENT_Questions[_cid].QID = _qid;
    CURRENT_Questions[_cid].currentStartDate = QUESTIONS[_qid].IntitialStartDate;
    CURRENT_Questions[_cid].currentSubmitEndDate = CURRENT_Questions[_cid].currentStartDate + QUESTIONS[_qid].NofDays_Submit;
    CURRENT_Questions[_cid].currentCommitDateStart = CURRENT_Questions[_cid].currentSubmitEndDate;
    CURRENT_Questions[_cid].currentCommitDateEnd = CURRENT_Questions[_cid].currentCommitDateStart + QUESTIONS[_qid].NofDays_Commit;
    CURRENT_Questions[_cid].currentResultDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[_qid].NofDays_BeforeResult;
    CURRENT_Questions[_cid].nextStartDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[_qid].NofDays_BeforeResult + QUESTIONS[_qid].NofDays_RepeatAfterResult;
     
    CURRENT_Questions[_cid].NofAnswersLimit = QUESTIONS[_qid].NofAnswersLimit;
            
    TOTAL_NofQUESTIONS++;
    CYCLE_ID++;
    return true;
  }
    
  function getCountOfActiveQuestions() public view returns(uint[]) {
    uint[] memory active_question = new uint[](getActiveQuestionCount());
    uint counter = 0;
    for (uint i = 1; i < CYCLE_ID; i++) {
      if (checkIfUserAlreadyAnswered(i) && CURRENT_Questions[i].currentStartDate <= now && CURRENT_Questions[i].currentSubmitEndDate >= now && CURRENT_Questions[i].usersAnswered.length < CURRENT_Questions[i].NofAnswersLimit) {
        active_question[counter] = CURRENT_Questions[i].CID;
        counter++;
      }
    }
    return active_question;
  }
    
  function getActiveQuestionCount() internal view returns(uint) {
    uint count = 1;
    for (uint i = 1; i < CYCLE_ID; i++) {
      if (checkIfUserAlreadyAnswered(i) && CURRENT_Questions[i].currentStartDate <= now && CURRENT_Questions[i].currentSubmitEndDate >= now && CURRENT_Questions[i].usersAnswered.length < CURRENT_Questions[i].NofAnswersLimit) {
        count++;
      }
    }
    return count;
  }
    
  function getQuestionForSubmit(uint _cid) public view returns(uint, uint, uint, uint, string, string, uint, uint) {
    if (checkIfUserAlreadyAnswered(_cid) && CURRENT_Questions[_cid].currentStartDate <= now && CURRENT_Questions[_cid].currentSubmitEndDate >= now && CURRENT_Questions[_cid].usersAnswered.length < CURRENT_Questions[_cid].NofAnswersLimit) {
        uint _index = CURRENT_Questions[_cid].QID;
      return (
        CURRENT_Questions[_cid].CID,
        CURRENT_Questions[_cid].QID,
        CURRENT_Questions[_cid].currentSubmitEndDate,
        CURRENT_Questions[_cid].currentCommitDateEnd,
        QUESTIONS[_index].QuestionText,
        QUESTIONS[_index].Answers,
        QUESTIONS[_index].AnswerCount,
        QUESTIONS[_index].Cost
      );
    }
  }
    
  function checkIfUserAlreadyAnswered(uint _cid) internal view returns(bool) {
    for (uint i = 1; i <= CURRENT_Questions[_cid].usersAnswered.length; i++) {
      if (CURRENT_Questions[_cid].usersAnswered[i-1] == msg.sender) {
        return false;
      }
    }
    return true;
  }
    
  function submitAnswer(uint _cid, uint _current_qid, string _encryptedAns) public payable returns (bool success) {
    require(msg.value == QUESTIONS[_current_qid].Cost, "Provide required amount to submit answer.");
    require(validateValidQuestionId(_cid, _current_qid), "Invaild Question Id");
    require(validateNofAnswersLimit(_cid), "Limit of Number of Users already reached");
    require(validateQuestionForSubmit(_cid), "Not a valid Question anymore"); // Checks if question is a valid question for sumbit as of now
    require(!validateIfUserSubmitted(_cid), "Already submitted ans for this question");
    
    UserAnswers memory userAnswer;
    userAnswer.status = Status.submitted;
    userAnswer.UserSubmittedQuestions = _cid;
    userAnswer.submittedDate = now;
    userAnswer.answer = _encryptedAns;
    userAnswer.submitted = true;
    
    CURRENT_UserAnswers[msg.sender].push(userAnswer);
    
    CURRENT_Questions[_cid].usersAnswered.push(msg.sender);
    CURRENT_Questions[_cid].NofAnswersGiven++;
    
    return true;
  }
    
  function validateValidQuestionId(uint _cid, uint _qid) internal view returns(bool) {
    if (CURRENT_Questions[_cid].QID == _qid) {
      return true;
    } else {
      return false;
    }
  }
    
  function validateNofAnswersLimit(uint _cid) internal view returns(bool) {
    if (CURRENT_Questions[_cid].NofAnswersGiven >= CURRENT_Questions[_cid].NofAnswersLimit) {
      return false;
    } else {
      return true;
    }
  }
    
  function validateQuestionForSubmit(uint _cid) internal view returns(bool) {
    if (CURRENT_Questions[_cid].currentStartDate <= now && CURRENT_Questions[_cid].currentSubmitEndDate >= now) {
      return true;
    } else {
      return false;
    }
  }
    
  function getQuestionForCommit() public view returns(uint[]) {
    uint[] memory submittedQuestions = new uint[](getCountForQuestionCommit());
    uint counter = 0;

    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      uint cid = CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions;
      if (!CURRENT_UserAnswers[msg.sender][i].committed && now < CURRENT_Questions[cid].currentCommitDateEnd) {
        submittedQuestions[counter] = CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions;
        counter++;
      }
    }
    return submittedQuestions;
  }
    
  function getCountForQuestionCommit() internal view returns(uint) {
    uint count = 1;
    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      if (!CURRENT_UserAnswers[msg.sender][i].committed) {
        count++;
      }
    }
    return count;
  }
    
  function getQuestionDetailsForCommit(uint _cid) public view returns (uint, uint, uint, uint, string, string, uint) {
    if (validateIfUserSubmitted(_cid) && !validateIfUserCommitted(_cid)) {
      uint _index = CURRENT_Questions[_cid].QID;
      return (
        CURRENT_Questions[_cid].CID,
        CURRENT_Questions[_cid].QID,
        CURRENT_Questions[_cid].currentCommitDateStart,
        CURRENT_Questions[_cid].currentCommitDateEnd,
        QUESTIONS[_index].QuestionText,
        CURRENT_UserAnswers[msg.sender][getCommitIndexOfCurrentUser(_cid)].answer,
        getCommitIndexOfCurrentUser(_cid)
      );
    }
  }
    
  function getCommitIndexOfCurrentUser(uint _cid) internal view returns(uint) {
    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      if (CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions == _cid) {
        return i;
      }
    }
  }
    
  function validateQuestionForCommit(uint _cid) public view returns (bool) {
    if (CURRENT_Questions[_cid].currentCommitDateStart <= now && CURRENT_Questions[_cid].currentCommitDateEnd >= now) {
      return true;
    } else {
      return false;
    }
  }
    
  function validateIfUserSubmitted(uint _cid) internal view returns (bool) {
    for (uint i = 0; i < CURRENT_Questions[_cid].usersAnswered.length; i++) {
      if (CURRENT_Questions[_cid].usersAnswered[i] == msg.sender) {
        return true;
      }
    }
    return false;
  }
    
  function validateIfUserCommitted(uint _cid) internal view returns (bool) {
    for (uint i = 0; i < CURRENT_Questions[_cid].usersCommitted.length; i++) {
      if (CURRENT_Questions[_cid].usersCommitted[i] == msg.sender) {
        return true;
      }
    }
    return false;
  }
    
  function commitAnswer(uint _index, uint _cid, uint _qid, string _ans) public returns (bool success) {
    require(validateIfUserSubmitted(_cid), "Question needs to be submitted first.");
    require(!validateIfUserCommitted(_cid), "Answer already committed.");
    require(validateQuestionForCommit(_cid), "User is commiting before or after commit date interval");
        
    UserAnswers memory userAnswer = CURRENT_UserAnswers[msg.sender][_index];
    userAnswer.status = Status.committed;
    userAnswer.UserCommittedQuestions = _qid;
    userAnswer.committedDate = now;
    userAnswer.answer = _ans;
    userAnswer.committed = true;
    
    CURRENT_UserAnswers[msg.sender][_index] = userAnswer;
    
    CURRENT_Questions[_cid].usersCommitted.push(msg.sender);
    CURRENT_Questions[_cid].committedAnswerTexts.push(_ans);
    
    return true;
  }

  function getCycleIdsForQuestionSummary() public view returns(uint[]) {
    uint[] memory summary_questions = new uint[](getCountForReward());
    uint counter = 0;
    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      uint _curr_cid = CURRENT_UserAnswers[msg.sender][i].UserCommittedQuestions;
      if (CURRENT_UserAnswers[msg.sender][i].submitted && CURRENT_UserAnswers[msg.sender][i].committed) {
        summary_questions[counter] = CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions;
        counter++;
      }
    }
    return summary_questions;
  }
    
  function getCountForReward() internal view returns(uint) {
    uint counter = 1;
    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      uint _curr_cid = CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions;
      if (CURRENT_Questions[_curr_cid].currentResultDate <= now) {
        if (CURRENT_UserAnswers[msg.sender][i].submitted && CURRENT_UserAnswers[msg.sender][i].committed) {
          counter++;
        }
      }
    }
    return counter;
  }
    
  function getSummaryOfWinningQuestion(uint _cid) public view returns(uint, string, string) {
    uint winning_cycleID;
    string memory reward_calculation; 
    string memory user_answer; 
    for (uint i = 0; i < CURRENT_UserAnswers[msg.sender].length; i++) {
      if (CURRENT_UserAnswers[msg.sender][i].submitted && CURRENT_UserAnswers[msg.sender][i].committed && CURRENT_UserAnswers[msg.sender][i].UserSubmittedQuestions == _cid) {
        if (!CURRENT_Questions[_cid].rewardCalculated && calculateResult(
          _cid,
          QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
          QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
          CURRENT_UserAnswers[msg.sender][i].answer) == 2
        ) {
          winning_cycleID = _cid;
          reward_calculation = "false_Claim";
          user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
          // reward_calculation = CURRENT_Questions[_cid].rewardCalculated;
        } else if (!CURRENT_Questions[_cid].rewardCalculated && calculateResult(
          _cid,
          QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
          QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
          CURRENT_UserAnswers[msg.sender][i].answer) == 1) {
            winning_cycleID = _cid;
            reward_calculation = "false_Claim Refund";
            user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
        } else if (!CURRENT_Questions[_cid].rewardCalculated && calculateResult(
          _cid,
          QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
          QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
          CURRENT_UserAnswers[msg.sender][i].answer) == 0) {
            winning_cycleID = _cid;
            reward_calculation = "true_Lost";
            user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
        }else if(CURRENT_Questions[_cid].rewardCalculated){
          if (calculateResult(
            _cid,
            QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
            QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
            CURRENT_UserAnswers[msg.sender][i].answer) == 2
          ) {
            winning_cycleID = _cid;
            reward_calculation = "true_Rewarded";
            user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
            // reward_calculation = CURRENT_Questions[_cid].rewardCalculated;
          } else if (calculateResult(
            _cid,
            QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
            QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
            CURRENT_UserAnswers[msg.sender][i].answer) == 1) {
              winning_cycleID = _cid;
              reward_calculation = "true_Refunded";
              user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
          } else if (calculateResult(
            _cid,
            QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
            QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
            CURRENT_UserAnswers[msg.sender][i].answer) == 0) {
              winning_cycleID = _cid;
              reward_calculation = "true_Lost";
              user_answer = CURRENT_UserAnswers[msg.sender][i].answer;
          }
        } 
      }
    }
    return (winning_cycleID, reward_calculation, user_answer);
  }

  function returnWinningDetails(uint _cid) public view returns(string, string, uint, bool, string) {
    bool canClaimResult;
    if(CURRENT_Questions[_cid].currentResultDate < now){
      canClaimResult = false;
    }else{
      canClaimResult = true;
    }
    return (
      CURRENT_Questions[_cid].winningAnswer,
      QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
      CURRENT_Questions[_cid].currentResultDate,
      canClaimResult,
      QUESTIONS[CURRENT_Questions[_cid].QID].QuestionText
    );
  }

  function returnWinningAns(uint _cid) public view returns(string) {
    string[] memory answersArray = new string[](QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount);
    uint[] memory answerCountArray = new uint[](QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount);
    string[] memory commitAnsText = CURRENT_Questions[_cid].committedAnswerTexts;
        
    var s = QUESTIONS[CURRENT_Questions[_cid].QID].Answers.toSlice();
    var delim = "_".toSlice();
    for (uint i = 0; i < QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount; i++) {
      answersArray[i] = s.split(delim).toString();
      answerCountArray[i] = 0;
    }
    
    for (uint j = 0; j < answersArray.length; j++) {
      for (uint k = 0; k < commitAnsText.length; k++) {
        if (compareStrings(answersArray[j], commitAnsText[k])) {
          answerCountArray[j] += 1;
        }
      }
    }
    
    if (findIndexOf(answerCountArray, 0) > -1) {
      for (j = 0; j < answerCountArray.length; j++) {
        if(answerCountArray[j] == 0){
          return answersArray[j];
        }
      }
    } else {
      if (checkIfMinorityHasDuplicates(answerCountArray, findMinCount(answerCountArray, 0))) {
        return "No_Winning_Ans";
      } else {
        return answersArray[findIndexOfMinority(findMinCount(answerCountArray, 0), answersArray.length, answerCountArray)];
      }
    }
  }
    
  function calculateResult(uint _cid, uint _ansCount, string _answers, string _userAns) internal view returns(uint) {
    string[] memory answersArray = new string[](_ansCount);
    uint[] memory answerCountArray = new uint[](_ansCount);
    string[] memory commitAnsText = CURRENT_Questions[_cid].committedAnswerTexts; // all given answer by users.
   
    var s = _answers.toSlice();
    var delim = "_".toSlice();
    for (uint i = 0; i < _ansCount; i++) {
      answersArray[i] = s.split(delim).toString();
      answerCountArray[i] = 0;
    }
    
    for (uint j = 0; j < answersArray.length; j++) {
      for (uint k = 0; k < commitAnsText.length; k++) {
        if (compareStrings(answersArray[j], commitAnsText[k])) {
          answerCountArray[j] += 1;
        }
      }
    }
    
    // 0 - do not show
    // 1 - claim refund
    // 2 - claim reward
    if (findIndexOf(answerCountArray, 0) > -1) {
      return 0;
    } else {
      if (checkIfMinorityHasDuplicates(answerCountArray, findMinCount(answerCountArray, 0))) {
        return 1;
      } else {
        if (compareStrings(answersArray[findIndexOfMinority(findMinCount(answerCountArray, 0), answersArray.length, answerCountArray)], _userAns)) {
          CURRENT_Questions[_cid].winningAnswer = answersArray[findIndexOfMinority(findMinCount(answerCountArray, 0), answersArray.length, answerCountArray)];
          return 2;
        } else {
          CURRENT_Questions[_cid].winningAnswer = answersArray[findIndexOfMinority(findMinCount(answerCountArray, 0), answersArray.length, answerCountArray)];
          return 0;
        }
      }
    }
  }
  
  function findMinCount(uint[] _array, uint minCount) internal pure returns(uint) {
      uint min_count = 0;
      uint min_check = _array[0];
      for (uint i = 0; i < _array.length; i++) {
        if (_array[i] > 0) {
            if(_array[i] <= min_check){
              min_check = _array[i];
              min_count = _array[i];
            }
        //   break;
        }
      }
      return min_count;
  }

  function getWithrawableAmount() public onlyOwner view returns(uint) {
    return _totalWithdrawableAmount;
  }

  function findIndexOfMinority(uint minCount, uint _ansArraylength, uint[] _ansCountArray) internal pure returns(uint) {
    uint ans_index = 0;
    for (uint i = 0; i < _ansArraylength; i++) {
      if (_ansCountArray[i] <= minCount) {
        minCount = _ansCountArray[i];
        ans_index = i;
      }
    }
    return ans_index;
  }
  
  function checkIfMinorityHasDuplicates(uint[] _array, uint value) internal pure returns (bool) {
    uint count = 0;
    for (uint i = 0; i < _array.length; i++) {
      if (_array[i] == value) {
        count++;
      }
    }
    return (count > 1) ? true : false;
  }
  
  function hasDuplicates(uint[] _array) internal pure returns(bool) {
      uint[] memory valueSoFar = new uint[](_array.length);
      for (uint i = 0; i < _array.length; ++i) {
          if (findIndexOf(valueSoFar, _array[i]) != -1) return true;
          valueSoFar[i] = _array[i];
      }
      return false;
  }
  
  function findIndexOf(uint[] values, uint value) internal pure returns(int) {
      for (int i = 0; i < int(values.length); i++) {
          if (values[uint(i)] == value) return i;
      }
      return -1;
  }
    
  function compareStrings(string a, string b) public view returns(bool) {
    return keccak256(a) == keccak256(b);
  }
    
  function claimReward(uint _cid) public returns(bool) {
    require(!CURRENT_Questions[_cid].rewardCalculated, "Reward already calculated for this question.");
    uint rewardDistributed = 0;
    for (uint i = 0; i < CURRENT_Questions[_cid].usersCommitted.length; i++) {
      address _userAddress = CURRENT_Questions[_cid].usersCommitted[i];
      for (uint j = 0; j < CURRENT_UserAnswers[_userAddress].length; j++) {
        if (CURRENT_UserAnswers[_userAddress][j].submitted && CURRENT_UserAnswers[_userAddress][j].committed && CURRENT_UserAnswers[_userAddress][j].UserSubmittedQuestions == _cid) {
          if (calculateResult(
            _cid,
            QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
            QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
            CURRENT_UserAnswers[_userAddress][j].answer) == 2
          ) {
            uint doubleAmount = QUESTIONS[CURRENT_Questions[_cid].QID].Cost * 2;
            CURRENT_Questions[_cid].rewardCalculated = true;
            CURRENT_UserAnswers[_userAddress][j].resultDate = now;
            CURRENT_UserAnswers[_userAddress][j].status = Status.resultdeclared;
            _userAddress.transfer(doubleAmount);
            userBalance[_userAddress] += doubleAmount;
            rewardDistributed += doubleAmount;
            emit logTransfer(address(this), _userAddress, doubleAmount);
          } else if(calculateResult(
            _cid,
            QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount,
            QUESTIONS[CURRENT_Questions[_cid].QID].Answers,
            CURRENT_UserAnswers[_userAddress][j].answer) == 1) {
              uint amount = QUESTIONS[CURRENT_Questions[_cid].QID].Cost;
              CURRENT_Questions[_cid].rewardCalculated = true;
              CURRENT_UserAnswers[_userAddress][j].resultDate = now;
              CURRENT_UserAnswers[_userAddress][j].status = Status.resultdeclared;
              _userAddress.transfer(amount);
              rewardDistributed += amount;
              emit logTransfer(address(this), _userAddress, amount);
            }
        }
      }
    }

    if(CURRENT_Questions[_cid].usersAnswered.length > 0) {
      _totalWithdrawableAmount += (CURRENT_Questions[_cid].usersAnswered.length * QUESTIONS[CURRENT_Questions[_cid].QID].Cost) - rewardDistributed;
    }
    
    if (QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag < QUESTIONS[CURRENT_Questions[_cid].QID].RepeatCount) {
      addQuestionToCycle(CYCLE_ID, CURRENT_Questions[_cid].QID, _cid);
      QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag += 1;
    }
    
    return true;
  }

  function getContractBalance() public onlyOwner view returns(uint) {
    return address(this).balance;
  }

  function getUserBalance() public view returns(uint) {
    return userBalance[msg.sender];
  }

  function getQuestionSubmittedByAdmin(uint _i) public view onlyOwner returns(uint, string, uint, uint, uint, string, uint) {
      if (CURRENT_Questions[_i].currentResultDate < now && !CURRENT_Questions[_i].rewardCalculated) {
        return (
          CURRENT_Questions[_i].CID,
          QUESTIONS[CURRENT_Questions[_i].QID].QuestionText,
          QUESTIONS[CURRENT_Questions[_i].QID].Cost,
          QUESTIONS[CURRENT_Questions[_i].QID].RepeatCount,
          CURRENT_Questions[_i].currentStartDate,
          calculateResultAdmin(_i),
          CURRENT_Questions[_i].QID
        );
      } else {
        if (!CURRENT_Questions[_i].rewardCalculated) {
          return (
            CURRENT_Questions[_i].CID,
            QUESTIONS[CURRENT_Questions[_i].QID].QuestionText,
            QUESTIONS[CURRENT_Questions[_i].QID].Cost,
            QUESTIONS[CURRENT_Questions[_i].QID].RepeatCount,
            CURRENT_Questions[_i].currentStartDate,
            "false_Distribute Reward",
            CURRENT_Questions[_i].QID
          ); 
        } else if(CURRENT_Questions[_i].rewardCalculated && QUESTIONS[CURRENT_Questions[_i].QID].repeatFlag == QUESTIONS[CURRENT_Questions[_i].QID].RepeatCount){
          return (
            CURRENT_Questions[_i].CID,
            QUESTIONS[CURRENT_Questions[_i].QID].QuestionText,
            QUESTIONS[CURRENT_Questions[_i].QID].Cost,
            QUESTIONS[CURRENT_Questions[_i].QID].RepeatCount,
            CURRENT_Questions[_i].currentStartDate,
            "false_NoAction",
            CURRENT_Questions[_i].QID
          );
        }
      }
    }

  function calculateResultAdmin(uint _cid) public view returns(string) {
    string[] memory answersArray = new string[](QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount);
    uint[] memory answerCountArray = new uint[](QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount);
    string[] memory commitAnsText = CURRENT_Questions[_cid].committedAnswerTexts;
    uint minCount = 0;
    
    var s = QUESTIONS[CURRENT_Questions[_cid].QID].Answers.toSlice();
    var delim = "_".toSlice();
    for (uint i = 0; i < QUESTIONS[CURRENT_Questions[_cid].QID].AnswerCount; i++) {
      answersArray[i] = s.split(delim).toString();
      answerCountArray[i] = 0;
    }
    
    for (uint j = 0; j < answersArray.length; j++) {
      for (uint k = 0; k < commitAnsText.length; k++) {
        if (compareStrings(answersArray[j], commitAnsText[k])) {
          answerCountArray[j] += 1;
        }
      }
    }
    
    if (findIndexOf(answerCountArray, 0) > -1) {
      if (QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag < QUESTIONS[CURRENT_Questions[_cid].QID].RepeatCount) {
        QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag += 1;
        return "next_Start Next Cycle";
      } else {
        return "false_NoAction";
      }
    } else {
      if (checkIfMinorityHasDuplicates(answerCountArray, findMinCount(answerCountArray, minCount))) {
        return "true_Issue Refund";
      } else {
        return "true_Distribute Reward";
      }
    }
  }
  
  function issueRefundByAdmin(uint _cid) public onlyOwner returns(bool) {
    require(!CURRENT_Questions[_cid].rewardCalculated, "Reward already calculated for this question.");
    uint rewardDistributed = 0;
    for (uint i = 0; i < CURRENT_Questions[_cid].usersCommitted.length; i++) {
      address _userAddress = CURRENT_Questions[_cid].usersCommitted[i];
      for (uint j = 0; j < CURRENT_UserAnswers[_userAddress].length; j++) { 
        if (CURRENT_UserAnswers[_userAddress][j].submitted && CURRENT_UserAnswers[_userAddress][j].committed && CURRENT_UserAnswers[_userAddress][j].UserSubmittedQuestions == _cid) {
          uint amount = QUESTIONS[CURRENT_Questions[_cid].QID].Cost;
          CURRENT_Questions[_cid].rewardCalculated = true;
          CURRENT_UserAnswers[_userAddress][j].resultDate = now;
          CURRENT_UserAnswers[_userAddress][j].status = Status.resultdeclared;
          _userAddress.transfer(amount);
          rewardDistributed += amount;
        //   userBalance[_userAddress] += amount;
          emit logTransfer(address(this), _userAddress, amount);
        }
      }
    }
    if(CURRENT_Questions[_cid].usersAnswered.length > 0) {
      _totalWithdrawableAmount += (CURRENT_Questions[_cid].usersAnswered.length * QUESTIONS[CURRENT_Questions[_cid].QID].Cost) - rewardDistributed;
    }
    
    if (QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag < QUESTIONS[CURRENT_Questions[_cid].QID].RepeatCount) {
      addQuestionToCycle(CYCLE_ID, CURRENT_Questions[_cid].QID, _cid);
      QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag += 1;
    }
    
    return true;
  }
  
  function getCurrentQuestionDetails(uint _cycle_id) public view returns(address[], address[]) {
    return (CURRENT_Questions[_cycle_id].usersAnswered, CURRENT_Questions[_cycle_id].usersCommitted);
  }

  function endQuestionCycle(uint _cid) public returns (bool) {
    require(QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag == QUESTIONS[CURRENT_Questions[_cid].QID].RepeatCount, "Cycle still left  or completed");
    CURRENT_Questions[_cid].rewardCalculated = true;
    QUESTIONS[CURRENT_Questions[_cid].QID].repeatFlag += 1;
    if(CURRENT_Questions[_cid].usersAnswered.length > 0) {   
      _totalWithdrawableAmount += (CURRENT_Questions[_cid].usersAnswered.length * QUESTIONS[CURRENT_Questions[_cid].QID].Cost);
    }
    return true;
  }
  
  function addQuestionToCycle(uint _cid, uint _qid, uint _current_cid) internal returns (bool) {
    CURRENT_Questions[_cid].CID = _cid;
    CURRENT_Questions[_cid].QID = _qid;
    
    if (CURRENT_Questions[_current_cid].nextStartDate < now) {
      CURRENT_Questions[_cid].currentStartDate = now;
    } else {
      CURRENT_Questions[_cid].currentStartDate = CURRENT_Questions[_current_cid].nextStartDate;    
    }
    
    CURRENT_Questions[_cid].currentSubmitEndDate = CURRENT_Questions[_cid].currentStartDate + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_Submit;
    CURRENT_Questions[_cid].currentCommitDateStart = CURRENT_Questions[_cid].currentSubmitEndDate;
    CURRENT_Questions[_cid].currentCommitDateEnd = CURRENT_Questions[_cid].currentCommitDateStart + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_Commit;
    CURRENT_Questions[_cid].currentResultDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_BeforeResult;
    CURRENT_Questions[_cid].nextStartDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_BeforeResult + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_RepeatAfterResult;
    CURRENT_Questions[_cid].NofAnswersLimit = QUESTIONS[CURRENT_Questions[_current_cid].QID].NofAnswersLimit;
    //QUESTIONS[CURRENT_Questions[_current_cid].QID].RepeatCount -= 1;
    
    CYCLE_ID++;
    return true;
  }
  
  function startNextCycle(uint _cid, uint _current_cid) public onlyOwner returns (bool) {
    require(QUESTIONS[CURRENT_Questions[_current_cid].QID].repeatFlag < QUESTIONS[CURRENT_Questions[_current_cid].QID].RepeatCount, "Already added to cycle.");
    require(!CURRENT_Questions[_current_cid].rewardCalculated, "Reward already calculated for this question.");
    CURRENT_Questions[_cid].CID = _cid;
    CURRENT_Questions[_cid].QID = CURRENT_Questions[_current_cid].QID;
    
    if (CURRENT_Questions[_current_cid].nextStartDate < now) {
      CURRENT_Questions[_cid].currentStartDate = now;
    } else {
      CURRENT_Questions[_cid].currentStartDate = CURRENT_Questions[_current_cid].nextStartDate;    
    }
    
    CURRENT_Questions[_cid].currentSubmitEndDate = CURRENT_Questions[_cid].currentStartDate + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_Submit;
    CURRENT_Questions[_cid].currentCommitDateStart = CURRENT_Questions[_cid].currentSubmitEndDate;
    CURRENT_Questions[_cid].currentCommitDateEnd = CURRENT_Questions[_cid].currentCommitDateStart + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_Commit;
    CURRENT_Questions[_cid].currentResultDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_BeforeResult;
    CURRENT_Questions[_cid].nextStartDate = CURRENT_Questions[_cid].currentCommitDateEnd + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_BeforeResult + QUESTIONS[CURRENT_Questions[_current_cid].QID].NofDays_RepeatAfterResult;
    CURRENT_Questions[_cid].NofAnswersLimit = QUESTIONS[CURRENT_Questions[_current_cid].QID].NofAnswersLimit;
    QUESTIONS[CURRENT_Questions[_current_cid].QID].repeatFlag += 1;
    //QUESTIONS[CURRENT_Questions[_current_cid].QID].RepeatCount -= 1;
    CURRENT_Questions[_current_cid].rewardCalculated = true;

    if(CURRENT_Questions[_current_cid].usersAnswered.length > 0) {   
      _totalWithdrawableAmount += (CURRENT_Questions[_current_cid].usersAnswered.length * QUESTIONS[CURRENT_Questions[_current_cid].QID].Cost);
    }
    
    CYCLE_ID++;
    return true;
  }
  
  function withdrawAmount(uint amount) public onlyOwner returns(bool) {
    require(amount <= _totalWithdrawableAmount, "amount is greater than withdrawable amount.");
    _totalWithdrawableAmount = _totalWithdrawableAmount - amount;
    owner.transfer(amount);
    return true;
  }
}
