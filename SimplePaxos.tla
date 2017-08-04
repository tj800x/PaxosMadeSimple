-------------------------------- MODULE SimplePaxos -------------------------

(***************************************************************************)
(* A formalization of the algorithm described in the paper "Paxos Made     *)
(* Simple", by Leslie Lamport.                                             *)
(*                                                                         *)
(* We specify how commands get chosen but not how learners learn a chosen  *)
(* value.                                                                  *)
(***************************************************************************)

EXTENDS Naturals, FiniteSets, TLC, Library

(***************************************************************************)
(* We consider a set of processes P, each of which plays both the roles of *)
(* proposer and acceptor (we do not specify learners and how they may      *)
(* learn chosen values).                                                   *)
(***************************************************************************)
CONSTANTS 
    P, \* The set of processes. 
    C \* The set of commands.

(***************************************************************************)
(* The variables of the spec.  See TypeInvariant for the expected values   *)
(* of those variables and comments.                                        *)
(***************************************************************************)
VARIABLES
    proposalNumber,
    numbersUsed,
    proposed,
    accepted,
    lastPromise,
    network,
    chosen
    
(***************************************************************************)
(* We assume that proposal numbers start at 1 and we will use 0 to         *)
(* indicate special conditions.                                            *)
(***************************************************************************)
ProposalNum == Nat \ {0}

Proposal == [command : C, number: ProposalNum]

Msg(type, Payload) == [type : {type}, payload : Payload]

(***************************************************************************)
(* Msgs is the set of messages that process can send.  We do not model     *)
(* explicitely the source and destination of messages and assume that      *)
(* every process sees the entire state of the network.  For example, a     *)
(* process will know that a prepare-reponse message is a response to its   *)
(* prepare message by looking at the propoal number in the messages.       *)
(***************************************************************************)
Msgs == 
    [   type : {"prepare"}, 
        number : ProposalNum ] 
    \cup
    [   type : {"prepare-response"}, 
        highestAccepted: Proposal \cup {<<>>}, \* we use <<>> to indicate that no proposal was ever accepted. 
        number: ProposalNum, 
        from: P ] 
    \cup
    [   type: {"propose"},
        proposal : Proposal ]

TypeInvariant ==
    \A p \in P :
        /\  proposalNumber[p] \in ProposalNum \cup {0} \* The current proposal number of process p.
        /\  proposed[p] \in BOOLEAN \* Did p make a proposal for its current proposal number?
        /\  numbersUsed[p] \in SUBSET ProposalNum \* All the proposal numbers ever used by p up to this point.
        /\  accepted[p] \in Proposal  \cup {<<>>} \* The last proposal that p has accepted.
        /\  lastPromise[p] \in ProposalNum \cup {0} \* The last promise made by p.
        /\  network \in SUBSET Msgs \* A set of messages.
        /\  chosen \in SUBSET C

Init == 
    /\  proposalNumber = [p \in P |-> 0]
    /\  proposed = [p \in P |-> FALSE]
    /\  numbersUsed = [p \in P |-> {}]
    /\  accepted = [p \in P |-> <<>>]
    /\  lastPromise = [p \in P |-> 0]
    /\  network = {}
    /\  chosen = {}
    
(***************************************************************************)
(* The proposer p starts the prepare phase by chosing a new proposal       *)
(* number and asking all the acceptors not to accept proposals with a      *)
(* lower number and to report the highest proposal that they have          *)
(* accepted.                                                               *)
(*                                                                         *)
(* Two different proposers never use the same proposal numbers.            *)
(*                                                                         *)
(* Note that a proposer can start a new prepare phase with a greater       *)
(* proposal number at any time.                                            *)
(***************************************************************************)
Prepare(p) == \E n \in ProposalNum :
    /\  n > proposalNumber[p]
    /\  \A q \in P : n \notin numbersUsed[q]
    /\  proposalNumber' = [proposalNumber EXCEPT ![p] = n]
    /\  proposed' = [proposed EXCEPT ![p] = FALSE]
    /\  network' = network \cup {[type |-> "prepare", number |-> n]}
    /\  numbersUsed' = [numbersUsed EXCEPT ![p] = @ \cup {n}]
    /\  UNCHANGED <<accepted, lastPromise,  chosen>>

PrepareReponse(p) == 
    /\  \E m \in network :
            /\  m.type = "prepare"
            /\  m.number > lastPromise[p]
            /\  lastPromise' = [lastPromise EXCEPT ![p] = m.number]
            /\  network' = network \cup {[
                    type |-> "prepare-response",
                    from |-> p, 
                    highestAccepted |-> accepted[p], 
                    number |-> m.number ]}
    /\  UNCHANGED <<proposalNumber, accepted, proposed, numbersUsed, chosen>>

MajoritySets == {Q \in SUBSET P : Cardinality(Q) > Cardinality(P) \div 2}

HighestProposal(proposals) == 
    CHOOSE p \in proposals :
        /\  \A q \in proposals : p # q => p.number > q.number

IsPrepareResponse(p, m) ==
    /\  m.type = "prepare-response"
    /\  m.number = proposalNumber[p]

SendProposal(p, c) ==
    network' = network \cup {[
        type |-> "propose",
        proposal |-> [
            command |-> c,
            number |-> proposalNumber[p] ]]}

(***************************************************************************)
(* The set of highest accepted proposals found in the prepare-response     *)
(* messages sent by the members of Q in response to the last prepare       *)
(* message of process p.                                                   *)
(***************************************************************************)
HighestAccepted(p, Q) ==
    {m.highestAccepted : m \in {m \in network :
        /\  IsPrepareResponse(p,m)
        /\  m.from \in Q
        /\  m.highestAccepted # <<>>}}

(***************************************************************************)
(* A proposer can propose a command if it has not already done so for its  *)
(* current proposal number and if it has received reponses to its prepare  *)
(* message from a majority of acceptors.                                   *)
(***************************************************************************)
Propose(p) == 
    /\  proposed[p] = FALSE \* Don't let p propose different values with the same proposal number.
    /\  \E Q \in MajoritySets :   
            /\  \A q \in Q : \E m \in network :
                    /\  IsPrepareResponse(p,m)
                    /\  m.from = q
            /\  LET proposals == HighestAccepted(p, Q)
                IN  IF  proposals # {}
                    THEN    LET c == HighestProposal(proposals).command
                            IN  /\  SendProposal(p, c)
                                /\  proposed' = 
                                        [proposed EXCEPT ![p] = TRUE]
                    ELSE
                        \E c \in C :
                            /\  SendProposal(p, c)
                            /\  proposed' = 
                                        [proposed EXCEPT ![p] = TRUE]
    /\  UNCHANGED <<proposalNumber, accepted, lastPromise, numbersUsed,  chosen>> 
          
        
IsChosen(c, acc) ==
    \E Q \in MajoritySets : \E n \in ProposalNum : \A q \in Q :
        /\  acc[q] # <<>>
        /\  acc[q].command = c
        /\  acc[q].number = n \* new conjunct, without which P3b and Agreement where violated.
         
(***************************************************************************)
(* An acceptor accepts a proposal.  A Stackoverflow answer claims that     *)
(* after accepting a command, p should not accept new commands that have a *)
(* lower number.  However this is wrong: an acceptor can safely vote for a *)
(* value in a round higher than its current round and without joining that *)
(* higher round.                                                           *)
(* `^\url{http://stackoverflow.com/questions/29880949/contradiction-in-lamports-paxos-made-simple-paper}^' *)
(***************************************************************************)   
Accept(p) ==
    /\  \E m \in network :
            /\  m.type = "propose"
            /\  m.proposal.number \geq lastPromise[p]
            /\  lastPromise' = lastPromise \* Here we do not update lastPromise.
            /\  accepted' = [accepted EXCEPT ![p] = m.proposal]
            /\  IF IsChosen(m.proposal.command, accepted)
                THEN chosen' = chosen \cup {m.proposal.command}
                ELSE UNCHANGED chosen
    /\  UNCHANGED  <<network, proposalNumber, proposed, numbersUsed>>

Next == \E p \in P :
    \/  Prepare(p)
    \/  PrepareReponse(p)
    \/  Propose(p)
    \/  Accept(p)

(***************************************************************************)
(* Agreement says that if a command is chosen, then no different command   *)
(* can be chosen at a later time.                                          *)
(*                                                                         *)
(* One might be tempted to add the fact that IsChosen(c, accepted) must be *)
(* stable, like below.  However the algorithm violates this property.      *)
(* This is however not a problem: it may prevent learners to learn about a *)
(* chosen value without triggering a new proposal.  In practice the same   *)
(* problem happens with crashes (which are not modeled here), and Lamport  *)
(* addresses it in section 2.3.                                            *)
(*                                                                         *)
(* WrongAgreement ==                                                       *)
(*     \A c \in C : [](IsChosen(c, accepted) =>                            *)
(*         /\  (\A d \in C : d # c => [](\neg IsChosen(d, accepted)))      *)
(*         /\  []IsChosen(c, accepted))                                    *)
(***************************************************************************)
Agreement == 
    \A c \in C : [](IsChosen(c, accepted) => 
        (\A d \in C : d # c => [](\neg IsChosen(d, accepted))))
        
(***************************************************************************)
(* The P3b property of "Byzantine Paxos by Refinement".  This property     *)
(* does not hold! This is probably a problem with the definition of        *)
(* IsChosen.                                                               *)
(***************************************************************************)
HighestNumbered(proposals) ==
    Max(proposals, LAMBDA p1,p2 : p1.number <= p2.number)

P3b ==
    \A c \in C : [](IsChosen(c, accepted) =>
        []( \A Q \in MajoritySets : 
                LET acceptedInQ == {prop \in {accepted[q] : q \in Q} : prop # <<>>}
                IN  \/ acceptedInQ = {}
                    \/ HighestNumbered(acceptedInQ).command = c ))
        
=============================================================================
\* Modification History
\* Last modified Fri Aug 04 16:07:50 PDT 2017 by nano
\* Created Sat Aug 29 17:37:33 EDT 2015 by nano
