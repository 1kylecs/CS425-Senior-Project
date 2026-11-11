const crypto = require("node:crypto");

//store active sessions in mem
const sessions = new Map();

//sessions default expiriy time (24 hrs), 24 hours * 60 minutes * 60 seconds * 1000ms
const SESSION_DURATION = 24 * 60 * 60 * 1000;

function createSession(username){
    const token = crypto.randomBytes(32).toString("hex");

    const session = {
        username: username,
        expiresAt: Date.now() + SESSION_DURATION
    };

    sessions.set(token, session);

    return token;
}

//check whether or not a session exists
function getSession(token){
    if (!token){
        return null;
    }

    const session = sessions.get(token);

    if (!session){
        return null;
    }

    //remove expired sessions
    if (Date.now() >= session.expiresAt) {
        sessions.delete(token);
        return null;
    }

    return session;
}

//delete session when the admin logs out
function deleteSession(token){
    return sessions.delete(token);
}

module.exports = {
    createSession,
    getSession,
    deleteSession
};