const { expect } = require("chai");

describe("Match", function() {
  it("Should return the new greeting once it's changed", async function() {
    const Match = await ethers.getContractFactory("Match");
    const match = await Match.deploy('123', '123');
    
    await match.deployed();
    
    // const tx =  await match.getDataApi('1235', '0x6c00000000000000000000000000000000000000000000000000000000000000')
    const tx = await match.createMarket(123433, 1, [12345, 33233], 3332323);
    let receipt = await tx.wait();
    const event = receipt?.events?.filter((e) => e.event == 'CreatedMarket')
    console.log(event[0].args.hashMarket);
    const tx2 = await match.getDataApi('1235', event[0].args.hashMarket);
    let receipt2 = await tx2.wait();
    const event2 = receipt2?.events?.filter((e) => e.event == 'Lala')
    console.log(event2[0].args.time.toString())
  });
});
