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

# Sum up all the lamports in stakes.csv and mint that many vote tokens
TOTAL_LAMPORTS=`grep -v "recipient,amount" stakes.csv | awk -F "," '{ sum += $2 } END { print sum }'`

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

echo
echo "A total of $TOTAL_LAMPORTS vote tokens were distributed."
echo
