# payment-channel-congestion

A payment channel is an instantiation of a state channel that allows two parties
to transact off-chain to avoid high transaction fees and latency. One weakness
in current payment channels is that they are susceptible to execution fork
attacks, where an attacker can make a withdrawal using the (old) state in the
smart contract. When the network is under congestion, the honest party will see
no incentive to dispute such a withdrawal if the cost to send the dispute
transaction cost more than what they would get back from a successful dispute.
This work presents a new way to construct payment channels that would help
mitigate these types of attacks, by having the party making the withdrawal put
up a deposit that would be used to compensate the party making the dispute if
that dispute is successful.
