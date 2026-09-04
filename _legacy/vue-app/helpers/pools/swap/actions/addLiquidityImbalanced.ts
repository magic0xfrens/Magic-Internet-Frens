import {
    writeContractHelper,
    simulateContractHelper,
    waitForTransactionReceiptHelper,
} from "@/helpers/walletClienHelper";
import type { Address } from "viem";
import BlastMimSwapRouterAbi from "@/abis/BlastMimSwapRouter";

export const addLiquidityImbalanced = async (
    swapRouterAddress: Address,
    payload: any
) => {

    const { request } = await simulateContractHelper({
        address: swapRouterAddress,
        abi: BlastMimSwapRouterAbi,
        functionName: "addLiquidityImbalanced",
        args: [payload],
    });

    const hash = await writeContractHelper(request);
    return await waitForTransactionReceiptHelper({ hash });
};
