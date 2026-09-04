import {
  writeContractHelper,
  simulateContractHelper,
  waitForTransactionReceiptHelper,
} from "@/helpers/walletClienHelper";
import type { Address } from "viem";
import BlastMimSwapRouterAbi from "@/abis/BlastMimSwapRouter";

export type SellBaseETHForTokensPayload = {
  payableAmount: bigint;
  lp: Address;
  to: Address;
  minimumOut: bigint;
  deadline: bigint;
};

export const sellBaseETHForTokens = async (
  swapRouterAddress: Address,
  payload: SellBaseETHForTokensPayload
) => {
  const { payableAmount, lp, to, minimumOut, deadline } = payload;

  const { request } = await simulateContractHelper({
    address: swapRouterAddress,
    abi: BlastMimSwapRouterAbi,
    functionName: "sellBaseETHForTokens",
    args: [lp, to, minimumOut, deadline],
    value: payableAmount,
  });

  const hash = await writeContractHelper(request);

  return await waitForTransactionReceiptHelper({ hash });
};
