// Function to create a new Nextcloud user account

// take a username and password as inputs
async function createUser(username, password) {

    // check that a username and password were provided
    // if either is missing, stop the function and display an error
    if (!username || !password) {
        throw new Error("Username and password are required");
    }

    // get nextcloud server URL and admin credentials
    // these values are stored as environment variables for security
    const nextcloudURL = process.env.NEXTCLOUD_URL;
    const adminUser = process.env.NEXTCLOUD_ADMIN_USER;
    const adminPassword = process.env.NEXTCLOUD_ADMIN_PASSWORD;


    // check that the server information exists
    if (!nextcloudURL || !adminUser || !adminPassword) {
        throw new Error("Nextcloud server configuration is missing");
    }

    // send an HTTP request to nextcloud to create the user
    const response = await fetch(`${nextcloudURL}/ocs/v1.php/cloud/users`,
    {
        method: "POST",
        headers: 
        {
            // tell nextcloud this is an API request
            "OCS-APIRequest": "true",

            // use admin cridentials to authenticate the request
            "Authorization": "Basic " + Buffer.from(`${adminUser}:${adminPassword}`).toString("base64"),

            // ask nextcloud to retrun its response in JSON format
            "Accept": "application/json"
        },

        // send the new user's username and password
        body: new URLSearchParams({ userid: username, password: password })   
    });

    // convert nextcoulds json repsonse into a javascript object
    // so that we can check whether the account was created successfully
    const result = await response.json();

    // response.ok checks whether the HTTP request was successfull
    // statuscode 100 checks whether nextcloud completed teh operation
    if (!response.ok || Number(result.ocs?.meta?.statuscode) !== 100) {
        throw new Error(result.ocs?.meta?.message || "User creation failed");
    }

    return "User created successfully";

}

module.exports = { createUser };