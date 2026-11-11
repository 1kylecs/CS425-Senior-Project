const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

//unit test

//test normal behaviour
test("Dashboard displays admin username", async() => {
    const elements = {};

    function getElement(id){
        if (!elements[id]){
            elements[id] = {
                textContent: "",
                disabled: false,
                href: "",
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
                protocol: "http:",
                hostname: "localhost",
                href: "/dashboard"
            }
        },
        fetch: async () => ({
            ok: true,
            json: async() => ({
                username: "testadmin"
            })
        })
    };

    const scriptPath = path.join(
        __dirname,
        "../webpage/dashboard.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    //wait for dashboard req to finish
    await vm.runInContext("loadDashboard()", context);

    //verify the admin info is displayed
    assert.equal(getElement("username").textContent, "testadmin");
    assert.equal(getElement("server-status").textContent, "Online");
});

//test unauthrozied access
test("Dashboard redirects unauthorized users to login", async() => {
    const elements = {};

    function getElement(id){
        if (!elements[id]){
            elements[id] = {
                textContent: "",
                disabled: false,
                href: "",
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
                protocol: "http:",
                hostname: "localhost",
                href: "/dashboard"
            }
        },
        fetch: async () => ({
            ok: false,
        })
    };

    const scriptPath = path.join(
        __dirname,
        "../webpage/dashboard.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    //wait for dashboard req to finish
    await vm.runInContext("loadDashboard()", context);

    //verify the user is redirected to login page
    assert.equal(context.window.location.href, "/login");
});