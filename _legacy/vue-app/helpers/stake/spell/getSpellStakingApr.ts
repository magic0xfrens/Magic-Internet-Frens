import axios from "axios";

export const getFrenStakingApr = async (): Promise<{
  sFrenApr: string;
  mFrenApr: string;
}> => {
  try {
    const response = await axios.get(import.meta.env.VITE_APP_FREN_APR_URL);

    return {
      sFrenApr: response.data.apr,
      mFrenApr: response.data.apr,
    };
  } catch (error) {
    console.log("Get Fren Staking Apr Error:", error);
    return {
      sFrenApr: "N/A",
      mFrenApr: "N/A",
    };
  }
};
