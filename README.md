# CS425-Senior-Project
Kyle Kaiser, Kobe Kaiser, Miles Rasmussen 
UNR senior project


Project is a self-hosted cloud server than runs off of a raspberry pi or other home device. 
Would allow for a non-technical person to use with minimal setup to create the cloud server
and connect their other devices. 

Current flow:
once all the code is downloaded on an ubuntu server, run "sudo initialSetup/install.sh" to 
install Nextcloud and Tailscale. Immediately after this, nextcloud is up and running with a 
default account on http://localhost:8080 and is accessible on LAN. 

running "sudo initialSetup/configure-tailscale.sh" brings user to tailscale login page. 
Once done, the server is connected to users personal tailnet at mycloud.[tailscaleID].ts.net
and now Nextcloud can be accessed from any device with tailscale

INSTRUCTIONS TO RUN FOR PROTOTYPE:
1. On the server VM, navigate to the initialSetup folder and run: sudo bash install.sh to install and start required services.

2. Navigate to the server folder and run: sudo env HOST=0.0.0.0 node server.js to start the backend.

3. Get the server's IP using: hostname -I (will return something like 10.0.2.3)

4. On the client VM, open the browser (tested on mozilla), and navigate to http://"server's ip address":3000

5. Follow the setup wizard to create an admin account by entering a username and password (i've been super busy so I haven't implemented the correct password requirements), password need to have uppercase, lowercase, special symbol and be more than 8 characters.

6. After creating the account, the user will be redirected to the dashboard. Click Open Files to access Nextcloud and log in using the newly created credentials.

7. The user can log out of the dashboard and log back in using the same creds.

Note: The server and client must be connected to the same network, and Nextcloud must be configured to trust the server's IP address.