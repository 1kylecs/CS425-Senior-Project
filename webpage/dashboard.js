const usernameDisplay = document.getElementById("username");
const serverStatus = document.getElementById("server-status");
const logoutButton = document.getElementById("logout-button");
const filesLink = document.getElementById("files-link");

//check if the admin is logged in
async function loadDashboard() {
    try{
        const response = await fetch("/api/me");

        if (!response.ok) {
            window.location.href = "/login";
            return;
        }

        const data = await response.json();

        //display admin username
        usernameDisplay.textContent = data.username;

        //if backend responds server is running
        serverStatus.textContent = "Online";
    } catch(error) {
        serverStatus.textContent = "Unable to connect";
    }
}

//log out when logout button is clicked
logoutButton.addEventListener("click", async() => {
    logoutButton.disabled = true;

    try {
        await fetch("/api/logout", {
            method: "POST"
        });

        window.location.href = "/login";
    } catch(error) {
        alert("Could not log out, try again");
        logoutButton.disabled = false;
    }
});

//set nextcloud url based on the servers address
if (filesLink) {
    filesLink.href = `${window.location.protocol}//${window.location.hostname}:8080`;
}

//run when dashbaord loads
loadDashboard();