const accountForm = document.getElementById("account-form");
const errorMessage = document.getElementById("error-message");

const accountStep = document.getElementById("account-step");

const installStep = document.getElementById("install-step");
const installBackButton = document.getElementById("install-back-button");
const installButton = document.getElementById("install-button");
const installStatus = document.getElementById("install-status");
const summaryUsername = document.getElementById("summary-username");

accountForm.addEventListener("submit", function(event){

    event.preventDefault();

    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value;
    const confirmPassword = document.getElementById("confirm-password").value;

    errorMessage.textContent = "";

    const validationError = validateAccount(username, password, confirmPassword);

    if(validationError){
        errorMessage.textContent = validationError;

        return;
    }
    
    summaryUsername.textContent = username;

    accountStep.hidden = true;
    installStep.hidden = false;

});

installBackButton.addEventListener("click", function(){
    installStep.hidden = true;
    accountStep.hidden = false;
});

installButton.addEventListener("click", async function(){
    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value;

    installButton.disabled = true;
    installBackButton.disabled = true;

    installStatus.textContent = "Creating administrator account...";

    try{
        const response = await fetch("/api/setup", {
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

        if(!response.ok) {
            throw new Error(result.error || "Account creation failed.");
        }

        installStatus.textContent = result.message;

        //redirect to dashboard after successful creation
        window.location.href = "/dashboard";
    } catch(error){
        installStatus.textContent = error.message;
        installButton.disabled = false;
        installBackButton.disabled = false;
    }
});

const nextcloudLink = document.getElementById("nextcloud-link");

nextcloudLink.href = `${window.location.protocol}//${window.location.hostname}:8080`;