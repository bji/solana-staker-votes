#!/bin/bash

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

echo
echo "Stake weights have been captured into stakes.csv"
echo
