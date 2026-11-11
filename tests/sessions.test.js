const test = require("node:test");
const assert = require("node:assert/strict");

const {
    createSession,
    getSession,
    deleteSession
} = require("../server/sessions");

//unit test
test("Creates, verifies, and deletes an admin session", () => {
    //create session for test admin
    const token = createSession("testadmin");

    //check to make sure a token was created
    assert.equal(typeof token, "string");

    //check to make sure the session exists
    const session = getSession(token);
    assert.equal(session.username, "testadmin");

    //delete the session (logout button)
    deleteSession(token);

    //check to verify the session closed
    assert.equal(getSession(token), null);
});