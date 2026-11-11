//tests the setup wizard
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const { validateAccount } = require("../webpage/setupWizard/validation");

//unit tests

//test 1
test("Valid credentials advance to the installation step", () => {
    const elements = {};

    function getElement(id){
        if (!elements[id]) {
            elements[id] = {
                value: "",
                textContent: "",
                hidden: false,
                disabled: false,
                href: "",
                addEventListener(event, callback) {
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
                hostname: "localhost"
            }
        },

        validateAccount
    };

    const scriptPath = path.join(
        __dirname,
        "../webpage/setupWizard/script.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    getElement("username").value = "testadmin";
    getElement("password").value = "Testpassword123!";
    getElement("confirm-password").value = "Testpassword123!";

    getElement("account-form").submit({
        preventDefault() {}
    });

    assert.equal(getElement("account-step").hidden, true);
    assert.equal(getElement("install-step").hidden, false);
    assert.equal(getElement("summary-username").textContent, "testadmin");
    assert.equal(getElement("error-message").textContent, "");
});

//test 2, test invalid creds
test("Invalid credentials prevent advancing", () => {
    const elements = {};

    function getElement(id){
        if (!elements[id]) {
            elements[id] = {
                value: "",
                textContent: "",
                hidden: false,
                disabled: false,
                href: "",
                addEventListener(event, callback) {
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
                hostname: "localhost"
            }
        },

        validateAccount
    };

    const scriptPath = path.join(
        __dirname,
        "../webpage/setupWizard/script.js"
    );

    const script = fs.readFileSync(scriptPath, "utf8");

    vm.runInNewContext(script, context);

    //create invalid creds
    getElement("username").value = "testadmin";
    getElement("password").value = "password123";
    getElement("confirm-password").value = "password123";

    getElement("account-step").hidden = false;
    getElement("install-step").hidden = true;

    //submit the form
    getElement("account-form").submit({
        preventDefault() {}
    });

    //verify the setup wizard doesnt advance
    assert.equal(getElement("account-step").hidden, false);
    assert.equal(getElement("install-step").hidden, true);

    //verify an error message appears
    assert.match(
        getElement("error-message").textContent,
        /Password requires an uppercase letter, lowercase letter, special character, and must be at least 8 characters long./
    )

})