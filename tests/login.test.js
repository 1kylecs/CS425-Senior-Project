const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

//unit tests

//normal behaviour test
test("Successful login redirects user to dashboard", async () => {
    const elements = {};

        function getElement(id){
        if (!elements[id]){
            elements[id] = {
                textContent: "",
                disabled: false,
                value: "",
                addEventListener(event, callback){
                    this[event] = callback;
                }
            };
        }
        
        return elements[id];
    }

    const context = {
        document: {
            getElementById: getElement
        },
        window: {
            location: {
                href: "/login"
            }
        },
        fetch: async () => ({
            ok: true,
            json: async() => ({
                message: "Login successful"
            })
        })
    };

    const scriptPath = path.join(
        __dirname, "../webpage/login.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    //simulate entering credentials
    getElement("username").value = "testadmin";
    getElement("password").value = "Testpassword123!";

    //submit the login form
    await getElement("login-form").submit({
        preventDefault() {}
    });

    //verify successful login
    assert.equal(context.window.location.href, "/dashboard");
    assert.equal(getElement("login-status").textContent, "Login successful");
    assert.equal(getElement("login-button").disabled, false);
});

//test 2, invalid login creds
test("Invalid login displays error and prevents redirect to dashboard", async () => {
    const elements = {};

        function getElement(id){
        if (!elements[id]){
            elements[id] = {
                textContent: "",
                disabled: false,
                value: "",
                addEventListener(event, callback){
                    this[event] = callback;
                }
            };
        }
        
        return elements[id];
    }

    const context = {
        document: {
            getElementById: getElement
        },
        window: {
            location: {
                href: "/login"
            }
        },
        fetch: async () => ({
            ok: false,
            json: async() => ({
                error: "Incorrect username or password"
            })
        })
    };

    const scriptPath = path.join(
        __dirname, "../webpage/login.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    //simulate entering credentials
    getElement("username").value = "testadmin";
    getElement("password").value = "password123";

    //submit the login form
    await getElement("login-form").submit({
        preventDefault() {}
    });

    //verify error message appears
    assert.equal(
        getElement("login-status").textContent,
        "Incorrect username or password"
    );

    //verify the user stays on the login page
    assert.equal(context.window.location.href, "/login");

    //verify the user can retry
    assert.equal(getElement("login-button").disabled, false);
});