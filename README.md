
# Solana Staker Voting

This repo contains a script that will set up a "staker vote" on behalf of a Solana validator.

This is accomplished by creating a new token mint and then issuing tokens from that mint, one
per lamport to the validator's current stakers.  Each withdraw authority will receive tokens
in proportion to the sum total of lamports they have actively staked with the validator.

A Yes, No, and Abstain system account will be created as the destination target for
transferring vote tokens.  Vote tokens transferred to these addresses should be considered
as votes for the corresponding option.

# Usage

1. Determine what it is you want your stakers to vote on, and how you want to communicate to
   them about the vote.  You will want to exercise all communication channels that you have
   available to you that could alert your stakers to the vote.  You should probably write up
   a description of the vote, its purpose, how it will work, and when it will start and end,
   and make this information available to your stakers.

2. Wait until it is the epoch in which you want the vote to start. You have to wait until that
   epoch because the set of active stakers will be determined at the start of that epoch.
   If you want to avoid stake entering or leaving in order to influence your vote, you can
   set up the vote before announcing it.

3. Run the setup_vote.sh script to actually set up the vote.  Because it is best run from
   an empty directory, you might consider doing something like this (assuming your current
   working directory is this repo's directory, i.e. the directory containing this README.md
   file):

   $ mkdir vote-1234
   $ cd vote-1234
   $ ../setup_vote.sh

   The setup_vote.sh script will step you through the process.  It might not be a bad idea
   to do a test run on devnet or testnet (you can choose which cluster you use when the
   script prompts you for the RPC URL), just so you can understand the process.

   BE SURE TO SAVE ALL THE FILES IN THIS DIRECTORY.  These include keypair files that you
   must retain in order to be able to complete tallying the votes.

4. Alert your voters that the vote has started.  Make sure they understand how to find their
   vote tokens (they will be in their stake account withdraw authority wallet, and have
   a token mint that matches the mint that was created by the script).

5. If you want to see a tally of the votes at any time, you can use commands like:

   $ spl-token -u $RPC_URL balance --owner yes_vote_account.json token_mint.json

6. When the vote is over, you can freeze the vote tally accounts so that no more votes
   can be cast:

   $ spl-token -u $RPC_URL freeze --mint-address token_mint.json yes_vote_account.json
   $ spl-token -u $RPC_URL freeze --mint-address token_mint.json no_vote_account.json
   $ spl-token -u $RPC_URL freeze --mint-address token_mint.json abstain_vote_account.json

   Then you can check the token balances of those accounts to see the final vote tallies.

   Keep in mind that the total vote tokens distributed is available by looking at the
   token mint in a block explorer and checking the "Current Supply".
