//this unit test verifies: 
//createAdministrator() succesfully creates an admin account,
//administratorExists() confirms the account file was created,
//verifyAministrator() verifies correct admin credentials

const test = require("node:test"); //defines unit test
const assert = require("node:assert/strict"); //check result
const fs = require("node:fs/promises");
const os = require("node:os"); //find computers temporary directory
const path = require("node:path");

async function setupTestEnviornment() {
    //make temp folder for test
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "account-test-"));

    //find the original account.js file
    const sourceFile = path.join(__dirname, "../server/accounts.js");

    //copy original into temp for isolated test
    const testFile = path.join(tempDir, "account.js");
    await fs.copyFile(sourceFile, testFile);

    //load copy
    const accounts = require(testFile);

    return { accounts, tempDir };
}

//unit tests

//test account creation and account existence after creation
test("Creates an administrator account successfully", async() => {
    const { accounts, tempDir } = await setupTestEnviornment();

    try{
        const result = await accounts.createAdministrator(
            "testadmin",
            "Testpassword123!"
        );

        assert.equal(result, "Administrator account created");

        //check to make sure the account exists
        const exists = await accounts.administratorExists();

        assert.equal(exists, true);
    } finally{
        await fs.rm(tempDir, { recursive: true, force: true }); //delete all files in the test dir
    }
});

//test admin credentials
test("Verify admin credentials", async() => {
    const { accounts, tempDir } = await setupTestEnviornment();

    try{
        //create test admin
        await accounts.createAdministrator(
            "testadmin",
            "Testpassword123!"
        );

        //verify creds
        const valid = await accounts.verifyAdministrator(
            "testadmin",
            "Testpassword123!"
        );

        assert.equal(valid, true);

        //verify incorrect creds gets rejected
        const invalid = await accounts.verifyAdministrator(
            "testadmin",
            "Badpassword123!"
        );

        assert.equal(invalid, false);
    } finally{
        await fs.rm(tempDir, { recursive: true, force: true }); //delete test files
    }
});