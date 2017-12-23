# openab-hivehome
integration for openhab with hive

## Original readme: https://community.openhab.org/t/hive-thermostat-british-gas-tutorial/36371
## credit user smar: https://community.openhab.org/u/smar/summary

A number of people have asked me via PM for how I connect to the British Gas Hive thermostat to openHAB. As such, here is a very brief set of notes and the scripts that I use, to help get any other Hive users started.

Note that these scripts are based on information from http://www.smartofthehome.com/2016/05/hive-rest-api-v613, where the author describes the key steps necessary to connect to the British Gas API for hive. This could of course change at anytime as these are all unofficial!

Also don't forget to change the extension on the attached file to zip, and then unzip the file.
Overview

Using your Hive userid/password, you can log in to the British Gas servers and get data from your Hive thermostat in JSON format. This data will be quite large, and include all sorts of things that you probably arent interested in.

One of the important things to note in this JSON data is that there are a number of nodes. Each node seems to be for various internal devices that your Hive is seeing. In my case, I am seeing 7 nodes in my data. You will have to figure out which of the nodes is for your heating (and which is for hot water, if you control your water from your hive as well). As an aside, there is a node for the water leaking sensor if you have this. However, my scripts do not currently support this.

Basic How-To
------------
	1. Modify the file config with your Hive login data, your openHAB server data and if you want to use mqtt, then your mqtt server data. If you don't know your hive node numbers and IDs, then leave these as is for now. If you do know them, then put them in here in their respective places and jump to step 8. If you have a combi-boiler, you will probably not have a node for your Water, so the node/receiver IDs for water can be ignored.

	2. Make sure all the files with .sh extension are executable (chmod +x *.sh)

    3. If you don’t know your node Ids, run the script nodes2JsnFile.sh. If your login details have been correctly entered in the config file, this will get your data and save to a file called nodes.jsn.

    4. Open the nodes.jsn file. It may be helpful to use something to prettify and format the JSON, so that it is easier to read. If your text editor does not do this, there are online sites available that do this. nodes

    5. Search for the exact text "temperature": including the quotation marks and the colon mark. It should only find one instance of this. The node that this is found in is your heating node. Scroll down slightly and you should see the  value. This is the id you need to enter in the RECEIVER_ID_HEATING parameter of the config file.
    temperature
    temperature.PNG779x506 43.3 KB

    6. Before moving on, scroll UP and count the node number that this ID is found in, starting at zero for the first node. In the screenshot below, you can see that my heating temperature reporting node is node 4.
    temperature 2

    7. If you have a hot water node, repeat the above step for your hot water node but this time searching for "stateHotWaterRelay":

    8. Put the node numbers and IDs from the previous steps into the config file from step 1.

    9. You can now get the data and post directly to openHAB via REST or to MQTT, using the respective scripts. If you post to openHAB, remember to change the item names to match yours in the hiveToOpenHAB.sh script.

    10. I have also included scripts for boosting and for setting the thermostat temperature. I don't use these much so am not sure how reliable they are, but they certainly worked when I first wrote the scripts (some time ago).

Hope this helps those of you looking to integrate Hive with openHAB!

EDIT: Sorry, I forgot to include the nodes2JsnFile.sh in the zip. I've attached it seperately now as with a .css extension to overcome the forum's limitaiton on filetypes that can be uploaded. Please rename/give permissions accordingly.
