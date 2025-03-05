#!/bin/bash

function create_key_file ()
{
    local filename=$1
    local prefix=$2

    if [ -z "$prefix" ]; then
        solana-keygen new --no-bip39-passphrase -s -o $filename
    else
        solana-keygen grind --starts-with $prefix:1 -o $filename
    fi
}

# Exit on error, for example if keygen fails
set -e

echo
echo "This script will emit files into the current directory.  This may overwrite"
echo "files you already have of the same name.  It is best to run this script in"
echo "a new directory to avoid any problems.  The current directory is:"
pwd

while true; do
    echo
    echo -n "Would you like to proceed [Y/n]? "
    
    read result
    echo

    result=${result:0:1}

    if [ "$result" = "n" -o "$result" = "N" ]; then
        exit 0
    fi

    if [ -n "$result" -a "$result" != "y" -a "$result" != "Y" ]; then
        echo "Please answer Yes or No."
    else
        break
    fi
done

vote_account=
while [ -z "$vote_account" ]; do
    echo
    echo "What is the vote account pubkey for the vote account for which voting"
    echo "is being set up?"
    echo
    echo -n "Vote account pubkey? "
    read vote_account
done

echo "What RPC server should be used?  For testing purposes, you could use"
echo "'d' for devnet or 't' for testnet, or even 'l' if you are running"
echo "your own development cluster.  Or you could specify a custom RPC URL"
echo "here.  If you accept the default of 'm', then the standard mainnet"
echo "RPC URL will be used."
echo
echo -n "RPC URL [m]? "

read rpc_url
echo

if [ -z "$rpc_url" ]; then
    rpc_url=m
fi

echo "A token mint will be created from which vote tokens will be minted.  If you"
echo "want this token mint to have a specific prefix, you can specify it here."
echo "Such a prefix could help your voters identify your vote tokens, but is not"
echo "necessary.  Keep in mind that the key takes exponentially longer to"
echo "generate as the prefix length grows; prefixes more than 4 characters long"
echo "are not recommended.  If no prefix is provided, the token mint will be"
echo "generated randomly."
echo
echo -n "Token mint prefix [none]? "

read token_mint_prefix
echo

echo "A system account will be created to receive Yes votes.  If you want this"
echo "account to have a specific prefix, you can specify it here.  Such a prefix"
echo "could help your voters identify the Yes vote account, but is not necessary."
echo "Keep in mind that the key takes exponentially longer to generate as the"
echo "prefix length grows; prefixes more than 4 characters long are not"
echo "recommended.  If no prefix is provided, the token mint will be generated"
echo "randomly."
echo
echo -n "Yes vote account prefix [none]? "

read yes_account_prefix
echo

echo "A system account will be created to receive No votes.  If you want this"
echo "account to have a specific prefix, you can specify it here.  Such a prefix"
echo "could help your voters identify the No vote account, but is not necessary."
echo "Keep in mind that the key takes exponentially longer to generate as the"
echo "prefix length grows; prefixes more than 4 characters long are not"
echo "recommended.  If no prefix is provided, the token mint will be generated"
echo "randomly."
echo
echo -n "No vote account prefix [none]? "

read no_account_prefix
echo

echo "A system account will be created to receive Abstain votes.  If you want"
echo "this account to have a specific prefix, you can specify it here.  Such"
echo "a prefix could help your voters identify the Abstain vote account, but"
echo "is not necessary.  Keep in mind that the key takes exponentially longer"
echo "to generate as the prefix length grows; prefixes more than 4 characters"
echo "long are not recommended.  If no prefix is provided, the token mint will"
echo "be generated randomly."
echo
echo -n "Abstain vote account prefix [none]? "

read abstain_account_prefix

fee_payer=
while [ -z "$fee_payer" ]; do
    echo
    echo "A fee payer will be needed to fund the on-chain operations of this"
    echo "script.  Please provide the key file for a Solana system account"
    echo "with at least 1 SOL to be used as the fee payer account."
    echo
    echo -n "Fee payer keypair? "
    read fee_payer
done

echo

create_key_file token_mint.json "$token_mint_prefix"
create_key_file yes_vote_account.json "$yes_account_prefix"
create_key_file no_vote_account.json "$no_account_prefix"
create_key_file abstain_vote_account.json "$abstain_account_prefix"

echo
echo "A system account will now be created for each of the Yes, No, and"
echo "Abstain vote tallies."

echo

solana -u $rpc_url -k $fee_payer transfer yes_vote_account.json 0.001 --allow-unfunded-recipient
solana -u $rpc_url -k $fee_payer transfer no_vote_account.json 0.001 --allow-unfunded-recipient
solana -u $rpc_url -k $fee_payer transfer abstain_vote_account.json 0.001 --allow-unfunded-recipient

echo "A token mint will now be created for your vote tokens."
echo

spl-token create-token -u $rpc_url --fee-payer $fee_payer --mint-authority $fee_payer --decimals 0 --enable-freeze token_mint.json

echo
echo "Capturing stakers and their stake weights ..."

# Fetch current epoch
EPOCH=$((`solana -u $rpc_url slot`/432000))

# If epoch could not be fetched, exit with an error
if [ -z "$EPOCH" ]; then
    echo "ERROR: Failed to detect current epoch"
    exit 1
fi

# Fetch all stake accounts for a given vote account
# Then filter out stake accounts with activationEpoch == $EPOCH or deactivationEpoch != $EPOCH
# (Explanation: We do not want stake accounts with activationEpoch == $EPOCH; these are stake accounts that
#  are currently activating and thus don't count as active stake.  And we also do not want stake accounts with
#  deactivationEpoch < $EPOCH, because those are stake accounts that were once active but have since been
#  deactivated and are thus not active stake.  Note that if deactivationEpoch == $EPOCH, that's fine, because
#  that means that the stake is currently active but is deactivating.  That stake still gets to vote because it
#  was active at the time that the vote tabulation was made.)
# Then for each unique withdrawer, sum the account balances
declare -A withdrawer_stakes
while read withdrawer; do
    read stake
    withdrawer_stakes[$withdrawer]=$((${withdrawer_stakes[$withdrawer]}+$stake))
done < <(
solana -u $rpc_url stakes --output=json "$vote_account" |
    jq -r ".[]|select(.activationEpoch<$EPOCH)|select(.deactivationEpoch==null or .deactivationEpoch==$EPOCH)|.withdrawer,.accountBalance"
)

# Print out the withdrawer balances in the form expected by solana-tokens, then sort the result so that the
# ordering is deterministic
echo "recipient,amount" > stakes.csv
for key in ${!withdrawer_stakes[@]}; do
    echo "$key,${withdrawer_stakes[$key]}"
done | sort >> stakes.csv

# Sum up all the lamports in stakes.csv and mint that many vote tokens
TOTAL_LAMPORTS=`grep -v "recipient,amount" stakes.csv | awk -F "," '{ sum += $2 } END { print sum }'`

echo
echo "Creating associated token accounts for the vote tally accounts"
echo

spl-token create-account --owner ./yes_vote_account.json --fee-payer $fee_payer -u $rpc_url ./token_mint.json
spl-token create-account --owner ./no_vote_account.json --fee-payer $fee_payer -u $rpc_url ./token_mint.json
spl-token create-account --owner ./abstain_vote_account.json --fee-payer $fee_payer -u $rpc_url ./token_mint.json

echo
echo "Minting $TOTAL_LAMPORTS vote tokens"

spl-token create-account --owner $fee_payer --fee-payer $fee_payer -u $rpc_url ./token_mint.json
# Not sure why, but have to wait for tx to finalize here
SIGNATURE=`spl-token mint -u $rpc_url --fee-payer $fee_payer --mint-authority $fee_payer --recipient-owner $fee_payer ./token_mint.json $TOTAL_LAMPORTS | grep Signature | awk '{ print $2 }'`
while true; do
    if [ `solana -u $rpc_url confirm $SIGNATURE` = "Finalized" ]; then
        break
    fi
    echo "Waiting for tx $SIGNATURE to be finalized"
    sleep 1
done

# Detect the token account that the tokens were just minted into.  spl tools are just so hokey.
TOKEN_SOURCE_ADDRESS=`spl-token -u d address --token ./token_mint.json --owner $fee_payer --verbose | grep "^Associated" | awk '{ print $4 }'`

echo
echo "Distributing vote tokens from $TOKEN_SOURCE_ADDRESS"
echo

# Now distribute the tokens
solana-tokens distribute-spl-tokens -u $rpc_url --fee-payer $fee_payer --db-path ./solana-tokens.db --input-csv ./stakes.csv -o ./transaction_log.txt --from $TOKEN_SOURCE_ADDRESS --owner $fee_payer

echo
echo
echo

echo "Votes are now set up.  The vote token mint is token_mint.json."
echo
echo "A total of $TOTAL_LAMPORTS vote tokens were distributed."
echo
echo "Stakers may vote by sending their tokens to one of:"
echo "  Yes     -- yes_vote_account.json"
echo "  No      -- no_vote_account.json"
echo "  Abstain -- abstain_vote_account.json"
echo
