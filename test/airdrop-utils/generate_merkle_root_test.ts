import fs from "fs";
import path from "path";
import { solidityPackedKeccak256 } from "ethers";
import { MerkleTree } from "merkletreejs";
import keccak256 from "keccak256";
import dotenv from "dotenv";

dotenv.config();
export function getMerkleRoot(network: any) {
  let json: string | Buffer;
  const env = process.env.NODE_ENV;
  try {
    json = fs.readFileSync(
      path.join(__dirname, `/${env}.${network}.user-airdrop-info-test.json`)
    );
  } catch (err) {
    json = "{}";
  }
  const addresses = JSON.parse(String(json));
  const elements = addresses.userInfo.map((x: any) => {
    return solidityPackedKeccak256(
      ["address", "uint256"],
      [x.address, x.amount]
    );
  });
  console.log("List encode leaf data: ", elements);
  const merkleTree = new MerkleTree(elements, keccak256, { sort: true });
  // Generate the root
  const root = merkleTree.getHexRoot();
  const data = JSON.parse(`{"${root}": ""}`);
  data[root] = addresses[network] || {};
  /**
   * Generate a JSON file with a hierarchy from root => hash(leaf) => proofs(leaf)
   * 
   * [root] {
   *    [leaf] {
   *        [proofs]
   *    }
   * }
   */
  elements.forEach((element: any) => {
    data[root][element] = merkleTree.getHexProof(element);
  });
  fs.writeFileSync(
    path.join(__dirname, `/${env}.${network}-test-output.json`),
    JSON.stringify(data, null, "    ")
  );
}

getMerkleRoot("goerli");
