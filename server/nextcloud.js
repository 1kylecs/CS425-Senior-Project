const { execFile, spawn } = require("node:child_process");
const { create } = require("node:domain");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

const developmentMode = process.env.NEXTCLOUD_MODE === "mock";

//check whethere nextcloud is running
async function checkNextcloud() {

    //simulate nextcloud during development
    if(developmentMode) {
        console.log("[MOCK] Checking Nextcloud stauts...");
        return true;
    }

    //check the real nextcloud docker container
    try {
        const { stdout } = await execFileAsync("docker", [
            "exec",
            "-u",
            "www-data",
            "nextcloud",
            "php",
            "occ",
            "status",
            "--output=json"
        ], { timeout: 10000 });

        const status = JSON.parse(stdout);

        return status.installed === true;
    } catch(error) {
        console.error("Nextcloud status check failed:", error.message);
        return false;
    }
}

async function createNextcloudAdministrator(username, password) {

    //simulate account creation during development
    if (developmentMode) {
        console.log(`[MOCK] Creating Nextcloud admin: ${username}`);
        return true;
    }

    //validate the username before passing it to Nextcloud
    if (!/^[a-zA-Z0-9_.-]+$/.test(username)) {
        throw new Error("Invalid Nextcloud username.");
    }

    //create the customer account in the existing Nextcloud container
    await new Promise((resolve, reject) => {
        const child = spawn("docker", [
            "exec",
            "-i",
            "-u", "www-data",
            "nextcloud",
            "sh", "-c",
            'IFS= read -r OC_PASS; export OC_PASS; exec php occ user:add --password-from-env "$1"',
            "sh",
            username
        ], {
            stdio: ["pipe", "pipe", "pipe"]
        });

        let stderr = "";

        child.stderr.on("data", chunk => {
            stderr += chunk.toString();
        });

        child.on("error", reject);

        child.on("close", code => {
            if (code === 0) {
                resolve();
            } else {
                reject(new Error(
                    `Nextcloud user creation failed (exit code ${code}): ${stderr}`
                ));
            }
        });

        //send the password through standard input
        child.stdin.end(password + "\n");
    });

    //give the customer administrator privileges
    await execFileAsync("docker", [
        "exec",
        "-u", "www-data",
        "nextcloud",
        "php", "occ",
        "group:adduser",
        "admin",
        username
    ], { timeout: 10000 });

    console.log(`Nextcloud administrator created: ${username}`);

    return true;
}

module.exports = { 
    checkNextcloud,
    createNextcloudAdministrator
};