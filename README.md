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

