import { deployments, ethers, network } from "hardhat";
import { expect } from "chai";
import { NFTMarketplace, NFTMarketplace__factory } from "../../typechain";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  DECIMALS,
  INITIAL_ANSWER,
  developmentChains,
} from "../../helper-hardhat-config";

const token = (n: number) => {
  return ethers.utils.parseEther(n.toString());
};

const ether = token;

!developmentChains.includes(network.name)
  ? describe.skip
  : describe("NFT Marketplace", () => {
      let nftMarketplace: NFTMarketplace;
      let deployer: SignerWithAddress;
      let creator: SignerWithAddress;
      let buyer: SignerWithAddress;
      let seller: SignerWithAddress;
      let buyer1: SignerWithAddress;
      let seller1: SignerWithAddress;
      let accounts: SignerWithAddress[];
      let campaign, result: any;

      const royaltyFee = 10;
      const listingPrice = token(0.025);
      const contractFee = 2;
      const maxPurchasePerMinute = 1;
      const purchaseCooldownSeconds = 60;

      beforeEach(async () => {
        await deployments.fixture(["all"]);
        accounts = await ethers.getSigners();
        [deployer, creator, buyer, seller, buyer1, seller1] = accounts;

        const nftMarketplaceFactory = new NFTMarketplace__factory(deployer);

        nftMarketplace = await nftMarketplaceFactory.deploy();

        await nftMarketplace.deployed();
      });

      describe("Deployment", () => {
        it("should set the right listing price", async () => {
          expect(
            await nftMarketplace.connect(deployer.address).getListingPrice()
          ).to.equal(listingPrice);
        });

        it("should set the right royalty", async () => {
          expect(
            await nftMarketplace.connect(deployer.address).getRoyaltyFee()
          ).to.equal(royaltyFee);
        });
      });

      describe("Create Token", () => {
        describe("Success", () => {
          beforeEach(async () => {});
        });

        describe("Failure", () => {});
      });

      describe("Create Market Item", () => {
        describe("Success", () => {
          beforeEach(async () => {});
        });

        describe("Failure", () => {});
      });
    });
