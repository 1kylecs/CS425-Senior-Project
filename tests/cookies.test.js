const test = require("node:test");
const assert = require("node:assert/strict");

const { getSessionToken } = require("../server/cookies");

test("Extracts the session token from a cookie", () => {
    //simulate browser req
    const req = {
        headers: {
            cookie: "theme=dark; session=testsession123; language=en"
        }
    };

    const token = getSessionToken(req);

    assert.equal(token, "testsession123");
});