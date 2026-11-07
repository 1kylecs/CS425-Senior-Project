const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

const accountFile = path.join(__dirname, "admin-account.json");

async function createAdministrator(username, password) {
    //check whether or not an admin account already exists
    try{
        await fs.access(accountFile);
        throw new Error("An admin account already exists.");
    } catch(error){
        if (error.code !== "ENOENT"){ //error no entry error
            throw error;
        }
    }

    //generate random salt for pw
    const salt = crypto.randomBytes(16).toString("hex");

    //hash the password
    const passwordHash = await new Promise((resolve, reject) => {
        crypto.scrypt(password, salt, 64, (error, derivedKey) =>{
            if (error) {
                reject(error);
                return;
            }

            resolve(derivedKey.toString("hex"));
        });
    });


    //store account info using password hash
    const account = {
        username : username,
        salt: salt,
        passwordHash: passwordHash
    };

    //"wx" prevents overwriting an existing account file
    await fs.writeFile(
        accountFile,
        JSON.stringify(account, null, 2),
        { flag: "wx", mode: 0o600 } //mode: 0o600 allows only the file owner to read and write on ubuntu
    );

    return "Administrator account created";

}

async function verifyAdministrator(username, password){
    //read the admin account file
    const data = await fs.readFile(accountFile, "utf8");

    //convert the JSON string to a js object
    const account = JSON.parse(data);

    //hash the provided pw using the stored salt
    const passwordHash = await new Promise((resolve, reject) => {
        crypto.scrypt(password, account.salt, 64, (error, derivedKey) => {
            if (error) {
                reject(error);
                return;
            }

            resolve(derivedKey);
        });
    });

    const storedHash = Buffer.from(account.passwordHash, "hex"); //convert store pw hash to a buffer

    //compare the username and pw hash
    const usernameMatches = username === account.username;

    const passwordMatches = storedHash.length === passwordHash.length &&
                            crypto.timingSafeEqual(storedHash, passwordHash);

    return usernameMatches && passwordMatches;

}

//check if an admin exists
async function administratorExists() {
    try {
        await fs.access(accountFile);
        return true;
    } catch(error) {
        if (error.code === "ENOENT") {
            return false;
        }

        throw error;
    }
}

module.exports = { 
    createAdministrator,
    verifyAdministrator,
    administratorExists
};