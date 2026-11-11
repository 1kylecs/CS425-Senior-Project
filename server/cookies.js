//helper function to retrieve session token from requests cookies
function getSessionToken(req){
    const cookies = req.headers.cookie || "";

    const sessionCookie = cookies.split(";").find(cookie =>
        cookie.trim().startsWith("session=")
    );

    if (!sessionCookie) {
        return null;
    }

    return sessionCookie.trim().substring("session=".length);
}

module.exports = { getSessionToken };