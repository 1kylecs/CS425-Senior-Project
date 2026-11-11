const test = require("node:test");
const assert = require("node:assert/strict");

const { createNextcloudAdministrator } = require("../server/nextcloud");

//unit test, checks for invalid usernames
test("Rejects invalid Nextcloud usernames", async() => {
    //try creating an admin with an invalid username
    await assert.rejects(
        createNextcloudAdministrator(
            "invalid username@*", 
            "Testpassword123!"
        ),
            /Invalid Nextcloud username/
        );
});