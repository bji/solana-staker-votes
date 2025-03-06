
# Solana Staker Voting

This repo contains a script that will set up a "staker vote" on behalf of a Solana validator.

This is accomplished by creating a new token mint and then issuing tokens from that mint, one
per lamport to the validator's current stakers.  Each withdraw authority will receive tokens
in proportion to the sum total of lamports they have actively staked with the validator.

A Yes, No, and Abstain system account will be created as the destination target for
transferring vote tokens.  Vote tokens transferred to these addresses should be considered
as votes for the corresponding option.

# Note about costs:

Creating the token mint and other associated accounts will require negligeable SOL on the
order of 0.01.

Each withdraw authority that will receive vote tokens will require one transaction and
thus for a validator with 3,000 unique stakers, the cost for this will total to 0.015 SOL.

# Prerequisites

You must have the solana command line installed.

# Usage

1. Determine what it is you want your stakers to vote on, and how you want to communicate to
   them about the vote.  You will want to exercise all communication channels that you have
   available to you that could alert your stakers to the vote.  You should probably write up
   a description of the vote, its purpose, how it will work, and when it will start and end,
   and make this information available to your stakers.

2. Set up the token mint and vote tally accounts.  Because it is best run from an empty
   directory, you might consider doing something like this (assuming your current working
   directory is this repo's directory, i.e. the directory containing this README.md file):
   
   ```
   $ mkdir vote-1234
   $ cd vote-1234
   $ ../setup_vote.sh
   ```
   
   BE SURE TO SAVE ALL THE FILES IN THIS DIRECTORY.  These include keypair files that you
   must retain in order to be able to complete tallying the votes.

   At this point the vote token mint and vote tally accounts have all been set up.  You
   can see the addresses of each using these commands:

   ```
   $ solana-keygen pubkey token_mint.json
   $ solana-keygen pubkey yes_vote_account.json
   $ solana-keygen pubkey no_vote_account.json
   $ solana-keygen pubkey abstain_vote_account.json
   ```

   You can begin preparing instructions for stakers to let them know how how they will
   vote using the tokens from the token mint, by sending those tokens to one of the
   vote tally accounts.


3. Wait until the epoch in which the vote token distribution is to be collected.  Then
   run the following command *from the directory that you ran setup_vote.sh*:

   ```
   $ ../collect_stakes.sh
   ```

   The resulting stake distribution list will be stored in stakes.csv.  You can make your
   stakers aware of this file and allow them time to analyze it and alert you to any
   inaccuracies they may believe are in this file.  There should be no issues, but it's
   best to give stake a chance to ensure that they agree with the vote token distribution.
   This mirrors the established SIMD voting process.

4. Wait until the epoch in which voting is to start.  Then distribute vote tokens using
   the stake distribution file that was gathered in step 3, by running the following
   command *from the directory that you ran setup_vote.sh and collect_stakes.sh in*:

   ```
   $ ../distribute_vote_tokens.sh
   ```

5. Alert your voters that the vote has started.  Make sure they understand how to find their
   vote tokens (they will be in their stake account withdraw authority wallet, and have
   a token mint that matches the mint that was created by the script).

6. If you want to see a tally of the votes at any time, you can use commands like:

   ```
   $ spl-token -u $RPC_URL balance --owner yes_vote_account.json token_mint.json
   ```

7. When the vote is over, you can freeze the vote tally accounts so that no more votes
   can be cast:

   ```
   $ spl-token -u $RPC_URL freeze --fee-payer $FEE_PAYER --freeze-authority $FEE_PAYER --mint-address token_mint.json `spl-token -u $RPC_URL address --token token_mint.json --owner yes_vote_account.json --verbose | grep "^Associated" | awk '{ print $4 }'`
   $ spl-token -u $RPC_URL freeze --fee-payer $FEE_PAYER --freeze-authority $FEE_PAYER --mint-address token_mint.json `spl-token -u $RPC_URL address --token token_mint.json --owner no_vote_account.json --verbose | grep "^Associated" | awk '{ print $4 }'`
   $ spl-token -u $RPC_URL freeze --fee-payer $FEE_PAYER --freeze-authority $FEE_PAYER --mint-address token_mint.json `spl-token -u $RPC_URL address --token token_mint.json --owner abstain_vote_account.json --verbose | grep "^Associated" | awk '{ print $4 }'`
   ```

   Then you can check the token balances of those accounts to see the final vote tallies.

   If you need to know the total supply of vote tokens that were issued, try this command:

   ```
   $ grep -v "recipient,amount" stakes.csv | awk -F "," '{ sum += $2 } END { print sum }'
   ```
