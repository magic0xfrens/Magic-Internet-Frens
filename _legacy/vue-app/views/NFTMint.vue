<template>
  <div class="nft-mint-view">
    <div class="nft-header">
      <h1 class="title">MiFREN NFT</h1>
      <p class="description">Mint your Magic Internet Fren companion NFT</p>
    </div>

    <div class="nft-content">
      <div class="nft-preview">
        <img
          src="@/assets/images/mif/PlebFren.svg"
          alt="MiFREN NFT"
          class="nft-image"
        />
      </div>

      <div class="mint-panel">
        <div class="mint-info">
          <div class="info-row">
            <span class="label">Price</span>
            <span class="value">0.001 BTC</span>
          </div>
          <div class="info-row">
            <span class="label">Total Supply</span>
            <span class="value">10,000</span>
          </div>
          <div class="info-row">
            <span class="label">Minted</span>
            <span class="value">0 / 10,000</span>
          </div>
        </div>

        <button class="mint-button" disabled>
          Coming Soon
        </button>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: "NFTMint",
};
</script>

<style lang="scss" scoped>
.nft-mint-view {
  max-width: 900px;
  margin: 0 auto;
  padding: 120px 15px 40px;
}

.nft-header {
  text-align: center;
  margin-bottom: 40px;
}

.title {
  font-family: "Prompt", sans-serif;
  font-size: 36px;
  font-weight: 700;
  background: linear-gradient(90deg, #F7931A, #FFD700);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  margin-bottom: 8px;
}

.description {
  color: rgba(255, 255, 255, 0.6);
  font-size: 16px;
}

.nft-content {
  display: flex;
  gap: 32px;
  align-items: flex-start;
}

.nft-preview {
  flex: 1;
  border-radius: 16px;
  border: 1px solid rgba(247, 147, 26, 0.15);
  background: linear-gradient(146deg, rgba(0, 10, 35, 0.07) 0%, rgba(247, 147, 26, 0.05) 101.49%);
  backdrop-filter: blur(12.5px);
  padding: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.nft-image {
  max-width: 100%;
  max-height: 400px;
}

.mint-panel {
  flex: 1;
  border-radius: 16px;
  border: 1px solid rgba(247, 147, 26, 0.15);
  background: linear-gradient(146deg, rgba(0, 10, 35, 0.07) 0%, rgba(247, 147, 26, 0.05) 101.49%);
  backdrop-filter: blur(12.5px);
  padding: 24px;
}

.mint-info {
  margin-bottom: 24px;
}

.info-row {
  display: flex;
  justify-content: space-between;
  padding: 12px 0;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);

  .label {
    color: rgba(255, 255, 255, 0.6);
  }

  .value {
    color: #fff;
    font-weight: 600;
  }
}

.mint-button {
  width: 100%;
  height: 48px;
  border-radius: 12px;
  border: none;
  background: linear-gradient(90deg, #F7931A, #FFD700);
  color: #0c0f1c;
  font-family: "Poppins", sans-serif;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.2s;

  &:hover {
    opacity: 0.9;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

@media (max-width: 768px) {
  .nft-content {
    flex-direction: column;
  }
}
</style>
