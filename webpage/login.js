const loginForm = document.getElementById("login-form");
const loginStatus = document.getElementById("login-status");
const loginButton = document.getElementById("login-button");

loginForm.addEventListener("submit", async(event) => {
    event.preventDefault();

    const username = document.getElementById("username").value;
    const password = document.getElementById("password").value;

    loginButton.disabled = true;
    loginStatus.textContent = "Logging in...";

    try {
        const response = await fetch("/api/login", {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                username: username,
                password: password
            })
        });

        const result = await response.json();

        if (response.ok) {
            loginStatus.textContent = "Login successful";

            //if login is ok, go to dashboard page
            window.location.href = "/dashboard";
        }
        else{
            loginStatus.textContent = result.error || "Incorrect username or password";
        }
    } catch(error) {
        loginStatus.textContent = "Could not connect to the server";
    } finally {
        loginButton.disabled = false;
    }
});