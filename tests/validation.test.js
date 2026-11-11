const test = require("node:test");
const assert = require("node:assert/strict");

const { validateAccount } = require("../webpage/setupWizard/validation");

//unit test to validate admin creds
test("Validates admin account credentials", () => {
    //valid creds
    const valid = validateAccount(
        "testadmin",
        "Testpassword123!",
        "Testpassword123!"
    );

    assert.equal(valid, "");

    //missing username
    const missingUsername = validateAccount(
        "",
        "Testpassword123!",
        "Testpassword123!"
    );

    assert.equal(missingUsername, "A username is required.");

    //password doesn't meet requirements
    const invalidPassword = validateAccount(
        "testadmin",
        "password123",
        "password123"
    );

    assert.equal(invalidPassword, "Password requires an uppercase letter, lowercase letter, special character, and must be at least 8 characters long.");

    //passwords aren't matching
    const passwordMismatch = validateAccount(
        "testadmin",
        "Testpassword123!",
        "Password123!"
    );

    assert.equal(passwordMismatch, "Passwords do not match.");
});