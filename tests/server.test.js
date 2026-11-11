const test = require("node:test");
const assert = require("node:assert/strict");
const server = require("../server/server");

//unit test to make sure user is logged in to access information
test("Unauthenticated users cannot access information", async() => {
    //start serevre on a temporary port
    await new Promise(resolve => {
        server.listen(0, "127.0.0.1", resolve);
    });

    try{
        const port = server.address().port;

        //request account info withnout a session cookie
        const response = await fetch(`http://127.0.0.1:${port}/api/me`);

        const result = await response.json();

        //verify the server rejects the req
        assert.equal(response.status, 401);
        assert.equal(result.error, "Not authenticated");
    } finally{
        //stop server after test
        await new Promise((resolve, reject) => {
            server.close(error => error ? reject(error) : resolve());
        });
    }
});