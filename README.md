## openab-hivehome
Integration of Hive Heating controls with openHAB

Based on original work by smar, expanded with permission
Original readme: https://community.openhab.org/t/hive-thermostat-british-gas-tutorial/36371
credit user smar: https://community.openhab.org/u/smar/summary

Overview
--------
The Hive Heating controls system, originally introduced by British Gas is now available online to all, and in Ireland through local providers. This set of scripts and config is intended to get some basic integration into openHAB. It may some day be re-written in java, for now the work started by smar is sufficient for my purposes.

Note that these scripts are based on information from http://www.smartofthehome.com/2016/05/hive-rest-api-v613, where the author describes the key steps necessary to connect to the Hive API. This could of course change at anytime as these are all unofficial!

Overview
--------
Using your Hive userid/password, you can log in to the Hive servers and get data from your Hive thermostat in JSON format. This data will be quite large, and include all sorts of things that you probably aren't interested in.

One of the important things to note in this JSON data is that there are a number of nodes. Each node represents internal devices in your Hive echosystem: this includes the hub, any thermostats or receivers etc. The first task is to identify the nodes of interest - currently only those that control heating or water. In the future, these will be updated to include lighting and should be extendible for any other interest.

Basic How-To
------------
Note: these steps assume you have a working Hive and OpenHAB system and are reasonably familar with configuration of both.
	
	1. Copy the contents of the scripts directory to your intended destination. The core scripts can run from any machine - openHAB or elsewhere. The default bundle loosly assumes the common openHAB structure, but of course may be changed as desired.  The default bundle also contains optional, sample openhab config for a 2 heat and 1 water zone system. The bundle includes: 
		./scripts						- contains the main logic to retrieve and parse data
			hive.config.sample 	- the sample config file.
			hiveToOpenHAB.sh		- the main script to optain data and update openHAB.
			<other>.sh				- contained as reference, still very much under development
		./items
			hive.items				- items required for a sample 2 heat and 1 water zone system
		./rules
			hive.rules				- schedule and enable manual executions of data script.
		./sitemaps
			hive.sitemap				- display all data and enable manual execution.
	 
	2. Copy the sample config file to hive.config, and populate the fields with your known data - hive username/password and openhab configuration details. If you only have one zone, or no water nodes those fields can be ignored or removed.
	 
	3. Make sure all the files with .sh extension are executable (chmod +x *.sh)
	4. Scripts require jq. Install it on your system with the relevant command. eg: sudo apt-get install jq

	5. If you don't know your node Ids, run the script with the -getIDS option: "./hiveToOpenHAB.sh -getIDs". If your login details have been correctly entered in the config file, this will get your data and save to a formatted file called nodes.jsn. This file is then parsed, to output the nodes of interest. 
	
    6. Put the node IDs of the relevant devices from the previous step into the hive.config file from step 2.

    7. Configure openhab items as needed - either with the included items file for openhab or by updating the hive.config with your openhab variable names. Once in place executing ./hiveToOpenHAB.sh should now retrieve and populate openHAB with the relevant data.
    
    8. verbose and debug configuration options may be useful to help testing your configuration. the simpliest is -v: eg: ./hiveToOpenHAB.sh -v OR ./hiveToOpenHAB.sh -getIDs -v
    
    9. Now that the core functionality is in place, you probably want to schedule the update. this can be done any number of ways. The included rules file enables openhab scheduling and management - by default updating every 15 minutes.
    
    10. Other scripts are included, but as of yet untested from the original release: eg MQTT; boosting and set thermostat. These will be refactored over time.

I hope others find this useful, and thanks to the original work by smar.