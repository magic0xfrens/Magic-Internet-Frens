#!/usr/bin/env bash
set -e
R=https://ethereum-sepolia-rpc.publicnode.com
TL=0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3
REG=0x3FD7649FcF3aF0CB511E625e7d868d98bb85D7D4
DEP=0xc94400e90bb652afa02740bff50824e14069c133
Z=0x0000000000000000000000000000000000000000000000000000000000000000
ARM=0x06e7b8db   # armEmergency()

echo "1/2 scheduling armEmergency through the timelock (180s delay)..."
cast send $TL "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $REG 0 $ARM $Z $Z 180 \
  --rpc-url $R --account deployer --from $DEP

echo "waiting out the 180s timelock delay..."
sleep 190

echo "2/2 executing..."
cast send $TL "execute(address,uint256,bytes,bytes32,bytes32)" \
  $REG 0 $ARM $Z $Z \
  --rpc-url $R --account deployer --from $DEP

echo
echo "emergencyReadyAt (unix) = $(cast call $REG 'emergencyReadyAt()(uint256)' --rpc-url $R | tail -1)"
echo "That is now + 48h. After it passes, emergencyWithdrawLP(1) recovers the 6.8882 ETH to the timelock."
