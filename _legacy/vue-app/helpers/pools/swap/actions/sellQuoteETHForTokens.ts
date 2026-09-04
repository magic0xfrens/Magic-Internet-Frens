import {
  writeContractHelper,
  simulateContractHelper,
  waitForTransactionReceiptHelper,
} from "@/helpers/walletClienHelper";
import type { Address } from "viem";
import BlastMimSwapRouterAbi from "@/abis/BlastMimSwapRouter";

export type SellQuoteETHForTokensPayload = {
  payableAmount: bigint;
  lp: Address;
  to: Address;
  minimumOut: bigint;
  deadline: bigint;
};

export const sellQuoteETHForTokens = async (
  swapRouterAddress: Address,
  payload: SellQuoteETHForTokensPayload
) => {
  const { payableAmount, lp, to, minimumOut, deadline } = payload;

  const { request } = await simulateContractHelper({
    address: swapRouterAddress,
    abi: BlastMimSwapRouterAbi,
    functionName: "sellQuoteETHForTokens",
    args: [lp, to, minimumOut, deadline],
    value: payableAmount,
  });

  const hash = await writeContractHelper(request);

  return await waitForTransactionReceiptHelper({ hash });
};
