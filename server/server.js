const http = require("node:http");

const fs = require("node:fs");
const path = require("node:path");
const webpageFolder = path.join(__dirname, "../webpage");
const fsPromise = require("node:fs/promises");

const { 
    createAdministrator,
    verifyAdministrator,
    administratorExists
} = require("./accounts");
const { 
    createSession, 
    getSession, 
    deleteSession 
} = require("./sessions");
const { 
    createNextcloudAdministrator,
    checkNextcloud
} = require("./nextcloud");

//helper function to retrieve session token from requests cookies
function getSessionToken(req) {
    const cookies = req.headers.cookie || "";

    const sessionCookie = cookies.split(";").find(cookie =>
        cookie.trim().startsWith("session=")
    );

    if (!sessionCookie) {
        return null;
    }

    return sessionCookie.trim().substring("session=".length);
}

const server = http.createServer(async (req, res) => {

    //check to see if frontend requested admin setup
    if (req.method === "POST" && req.url === "/api/setup") {

        let body = "";

        //recieve info sent by frontend
        req.on("data", chunk => {
            body += chunk;
        });

        //when info is recieved
        req.on("end", () => {
            try {
                const { username, password } = JSON.parse(body);

                //check for provided credentials
                if (typeof username !== "string" || typeof password !== "string" || username.trim().length === 0 || password.length < 8) {
                    res.writeHead(400, {
                        "Content-Type": "application/json"
                    });

                    res.end(JSON.stringify({
                        error: "A username and password with at least 8 characters are required."
                    }));
                    return;
                }
                createNextcloudAdministrator(username.trim(), password)
                    .then(() => {
                        //create the dashboard admin after nextcloud suceeds
                        return createAdministrator(username.trim(), password);
                    })
                    .then((message) => {
                        //automaticaly log in hte new admin
                        const token = createSession(username.trim());

                        res.writeHead(200, {
                            "Content-Type": "application/json",
                            "Set-Cookie": `session=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400`
                        });

                        res.end(JSON.stringify({
                            message: message
                        }));
                    })
                    .catch((error) => {
                        const accountExists = error.message === "An admin account already exists." ||
                            error.code === "EEXIST"; //EEXIST = file already exists

                        res.writeHead(accountExists ? 409 : 500, {
                            "Content-Type": "application/json"
                        });

                        res.end(JSON.stringify({
                            error: accountExists
                                ? "An administrator account already exists."
                                : "Could not create an administrator account."
                        }));
                    });
            } catch (error) {

                console.error("Administrator setup error:", error);

                res.writeHead(400, {
                    "Content-Type": "application/json"
                });

                res.end(JSON.stringify({
                    error: "Invalid administrator setup request."
                }));
            }
        });

        return;
    }

    //check if frontend requested admin login
    if (req.method === "POST" && req.url === "/api/login") {

        let body = "";

        //recieve login info from frontend
        req.on("data", chunk => {
            body += chunk;
        });

        req.on("end", async () => {
            try {
                const { username, password } = JSON.parse(body);

                console.log("Login request received:", {
                    username: username,
                    passwordProvided: typeof password === "string"
                });

                //validate provided info
                if (typeof username !== "string" ||
                    typeof password !== "string" ||
                    username.trim().length === 0 ||
                    password.length === 0
                ) {
                    res.writeHead(400, {
                        "Content-Type": "application/json"
                    });

                    res.end(JSON.stringify({
                        error: "Username and password are required"
                    }));

                    return;
                }

                //verify credentials against stored admin account
                const valid = await verifyAdministrator(username.trim(), password);

                if (!valid) {
                    res.writeHead(401, {
                        "Content-Type": "application/json"
                    });

                    res.end(JSON.stringify({
                        error: "Invalid username or password"
                    }));

                    return;
                }

                //create session after succesful login
                const token = createSession(username.trim());

                //Set-Cookie remembers the token
                res.writeHead(200, {
                    "Content-Type": "application/json",
                    "Set-Cookie": `session=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400`
                });

                res.end(JSON.stringify({
                    message: "Login successful"
                }));

            } catch (error) {
                console.error("Administrator login error:", error);

                res.writeHead(500, {
                    "Content-Type": "application/json"
                });

                res.end(JSON.stringify({
                    error: "Could not process request"
                }));
            }
        });

        return;
    }

    if (req.method === "POST" && req.url === "/api/logout") {
        const token = getSessionToken(req);

        if (token) {
            deleteSession(token);
        }

        //remove the browsers session cookie
        res.writeHead(200, {
            "Content-Type": "application/json",
            "Set-Cookie": "session=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0"
        });

        res.end(JSON.stringify({
            message: "Logged out successfully"
        }));

        return;
    }

    //check whether or not the current user is logged in
    if (req.method === "GET" && req.url === "/api/me") {
        const token = getSessionToken(req);
        const session = getSession(token);

        if (!session) {
            res.writeHead(401, {
                "Content-Type": "application/json"
            });

            res.end(JSON.stringify({
                error: "Not authenticated"
            }));

            return;
        }

        res.writeHead(200, {
            "Content-Type": "application/json"
        });

        res.end(JSON.stringify({
            username: session.username
        }));

        return;
    }

    const loginFiles = {
        "/login": "login.html",
        "/login.css": "login.css",
        "/login.js": "login.js",
        "/dashboard": "dashboard.html",
        "/dashboard.css": "dashboard.css",
        "/dashboard.js": "dashboard.js"
    };

    //only allow authenticated admins to access dashboard
    if (req.method === "GET" && req.url === "/dashboard") {
        const token = getSessionToken(req);
        const session = getSession(token);

        if (!session) {
            res.writeHead(302, {
                "Location": "/login"
            });

            res.end();

            return;
        }
    }

    if (req.method === "GET" && loginFiles[req.url]) {
        const filePath = path.join(webpageFolder, loginFiles[req.url]);

        try {
            const content = await fsPromise.readFile(filePath);

            const contentType = filePath.endsWith(".css")
                ? "text/css"
                : filePath.endsWith(".js")
                    ? "application/javascript"
                    : "text/html";

            res.writeHead(200, {
                "Content-Type": contentType
            });

            res.end(content);
        } catch (error) {
            res.writeHead(404);
            res.end("File not found");
        }

        return;
    }

    //decide which page to display when visiting the server
    if (req.method === "GET" && (req.url === "/" || req.url === "/index.html")) {
        try {
            const accountExists = await administratorExists();

            //if no admin account exists, run the setup wizard
            if (!accountExists) {
                req.url = "/index.html";
            }
            else {
                const token = getSessionToken(req);
                const session = getSession(token);

                //admin already exists, redirect to the dashboard/login
                res.writeHead(302, {
                    "Location": session ? "/dashboard" : "/login"
                });

                res.end();

                return;
            }
        } catch (error) {
            console.error("Could not check admin account", error);

            res.writeHead(500);
            res.end("Could not determine server setup status");

            return;
        }
    }

    const files = {
        "/": ["index.html", "text/html"],
        "/index.html": ["index.html", "text/html"],
        "/style.css": ["style.css", "text/css"],
        "/script.js": ["script.js", "text/javascript"]
    };

    const requestedFile = files[req.url];

    if (req.method === "GET" && requestedFile) {
        const filePath = path.join(
            __dirname,
            "..",
            "initialSetup",
            "setupWizard",
            requestedFile[0])

        fs.readFile(filePath, (error, data) => {
            if (error) {
                res.writeHead(500);
                res.end("Could not load webpage.");
                return;
            }

            res.writeHead(200, {
                "Content-Type": requestedFile[1]
            });

            res.end(data);
        });

        return;
    }

    res.writeHead(404);
    res.end("Not found");
});

const HOST = process.env.HOST || "127.0.0.1";

server.listen(3000, HOST, () => {
    console.log(`Backend running at http://${HOST}:3000`);
});