//username and password validation for account
function validateAccount(username, password, confirmPassword){
    //username validation
    if (username.trim().length === 0) {
        return "A username is required.";
    }

    //password validation (requires uppercase, lowercase, special char, and >= 8)
    if (password.length < 8 ||
        !/[A-Z]/.test(password) ||
        !/[a-z]/.test(password) ||
        !/[^a-zA-Z0-9]/.test(password)){
            return "Password requires an uppercase letter, lowercase letter, special character, and must be at least 8 characters long.";
        }

        if(password !== confirmPassword){
            return "Passwords do not match.";
        }

        return "";
    }

    
    if (typeof module !== "undefined"){
        module.exports = { validateAccount };
    }