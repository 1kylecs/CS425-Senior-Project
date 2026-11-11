# CS425-Senior-Project
Kyle Kaiser, Kobe Kaiser, Miles Rasmussen 
UNR senior project


Project is a self-hosted cloud server than runs off of a raspberry pi or other home device. 
Would allow for a non-technical person to use with minimal setup to create the cloud server
and connect their other devices. 

INSTRUCTIONS TO RUN FOR PROTOTYPE:
1. On the server VM, navigate to the initialSetup folder and run: sudo bash install.sh to install and start required services.

2. Get the server's IP using: hostname -I (will return something like 10.0.2.3)

4. On the client VM, open the browser (tested on mozilla), and navigate to http://"server's ip address":3000

5. Follow the setup wizard to create an admin account by entering a username and password (i've been super busy so I haven't implemented the correct password requirements), password need to have uppercase, lowercase, special symbol and be more than 8 characters.

6. After creating the account, the user will be redirected to the dashboard. Click Open Files to access Nextcloud and log in using the newly created credentials.

7. The user can log out of the dashboard and log back in using the same creds.

Note: The server and client must be connected to the same network, and Nextcloud must be configured to trust the server's IP address.

To enable Tailscale:
1. Run initialSetup/configure-tailscale.sh
2. Sign into tailscale account at the given URL
3. If success, will display the new tailscale URL for nextcloud
4. Sign in from another device. 
