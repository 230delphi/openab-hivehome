#!/bin/bash
# original work from smar: https://community.openhab.org/t/hive-thermostat-british-gas-tutorial/36371
# based on api defined in http://www.smartofthehome.com/2016/05/hive-rest-api-v6/
# script to logon to hivehome, retrieve data and update openhab
#
# main configuration is contained within: ./hive.config (or as per $configFilename below)
# options here should not need to be changed for most cases...
scriptOpts=$@
configFilename="./hive.config"
errorFilename=hive-error.log
debugjson=debug.json

#default curl command
curlCmd="curl --silent -g"
# connect timeouts used with curl commands to OpenHab
openHabCurlOPTS="-k --connect-timeout 10 --max-time 30"
# connect timeouts used with curl commands to hive on Internet - allow longer.
hiveCurlOPTS="--cookie-jar cookie.jar --connect-timeout 30 --max-time 60"

# print help
function printHelp {
	echo "README.md";
	echo "-v : verbose debug to console";
	echo "-getIDs : get NodeIDs of devices of interest";
	exit 0;
}

# always log errors
function errorLog {
	echo "ERROR: $1" >> $errorFilename;
	echo "ERROR: $1";
}

#log messages if debug enabled
function debugLog {
	if [[ "$debug" == "true" ]]
	then
	echo "DEBUG: $1" >> $debugFilename
		if [[ "$verbose" == "true" ]]
		then
				echo "DEBUG: $1";
		fi
	fi	
}

# Test curl output [ cmd_response_code dest_url set_value description ]
function testCurlResponse {
		case $1 in
		    0)
		    	#success
		    	debugLog "${4}$3 :: success to: $2";
		    ;;
		    6)
		    	errorLog "${4}$3 :: Curl Error: Invalid URL: $2";
		    ;;
		    28)
		    	errorLog "${4}$3 :: Curl Error: request Timeout. consider adjusting --max-time or --connect-timeout: $2";
		    ;;
		    *)
				# unknown error
				errorLog "${4}$3 :: Curl Error: unknown: $i : $2";
		    ;;
		esac
}

# put the data in OpenHab
function putInOH {
	$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $2 $1
#TODO deal with value does not exist in openhab
	testCurlResponse $? $1 $2 $3
}

# pre checks to ensure env is ok
function doCheck {
	#check for jq
	if ! hash jq 2>/dev/null; then
		errorLog "jq is required to parse hive responses. try installing with sudo apt-get install jq"
		exit 1;
	fi
	#check for $configFilename
	DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	if [ ! -f ${DIR}/${configFilename} ]; then
		errorLog "Config file (${DIR}/${configFilename}) not found. Follow notes in readme.md on how to create"
		exit 1;
	fi
}

# initialize script/env and passed parameters
function doInit {
	cd $DIR
	source $configFilename
	if [ -f "./cookie.jar" ]; then
		rm ./cookie.jar
	fi
	debugLog "Parsing options: $scriptOpts"
	for i in $scriptOpts
	do
		case $i in
		    -h)
		    	printHelp;
		    ;;
		    -getIDs)
		    	getIDs=true;
		    ;;
		    -v)
		    	verbose=true;
		    	debug=true;
		    	debugLog "verbose enabled";
		    ;;
		    -testdata)
		    	usetestdata=true;
		    	testdata=$debugjson
		    ;;
			-testdata=*)
		    	usetestdata=true;
			    testdata="${i#*=}"
			    if [ ! -e $testdata ]; then
			    	errorLog "$testdata file does not exist";
			    	exit 1;
				fi
			    shift # past argument=value
			;;
		    *)
				# unknown option
				echo unknown option: $i
		    ;;
		esac
	done
}

# Login to hive and get session id.
function hiveLogin {
	#Login...
	session=`$curlCmd $hiveCurlOPTS -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
	testCurlResponse $? $HIVE_URL/auth/sessions "authentication - first attempt"
	if [ "$session" == "" ]; then
		debugLog "Create session failed; retry login."
		session=`$curlCmd $hiveCurlOPTS -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
	testCurlResponse $? $HIVE_URL/auth/sessions "authentication - final attempt"
	fi
	if [ "$session" == "" ]; then
		errorLog "Failed to login to Hive to get session.";
		exit 1;
	fi

	debugLog "echo Session: `echo $session | jq .`"
	sessionId=`echo $session | jq .sessions[].sessionId`
	#remove quotes from beginning/end
	sessionId="${sessionId%\"}"
	sessionId="${sessionId#\"}"
	debugLog "SessionID: $sessionId"
}

# get the data from hive using session id
function hiveGetData {
	if [ "$sessionId" == "" ]; then
		errorLog "unable to get Data - session not created.";
		exit 1;
	fi 
	
	infoNodes=`$curlCmd $hiveCurlOPTS -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
	testCurlResponse $? $HIVE_URL/nodes getData
	
	debugLog $infoNodes
	if [[ $debug == "true" ]]
	then
		echo $infoNodes | jq . > $debugjson
		debugLog "Logged formatted to $debugjson"
	fi
}
	
# logout
function hiveLogout {
	if [ "$sessionId" == "" ]; then
		errorLog "unable to logout - session not created.";
	exit 1;
	fi
	$curlCmd $hiveCurlOPTS -X DELETE -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'"  -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId"  "$HIVE_URL/auth/sessions/${sessionId}"
	testCurlResponse $? "$HIVE_URL/auth/sessions/${sessionId}" logout
}

# get the data from hive
function getData {
	hiveLogin;
	hiveGetData;
	hiveLogout;
}

#test that the data is good
function testData {
	if [ `echo $infoNodes|grep -c "NOT_AUTHORIZED"` -gt "0" ]; then
		errorLog "Request was not authenticated."
		exit 1;
	fi
	if [ "$infoNodes" == "" ]; then
		errorLog "Empty data"
		exit 1;
	fi
}

# identify heating,water and bulb nodes
function getNodeIDs {
	echo $infoNodes |jq . > nodes.jsn
	echo "Found thermostat node(s):"
	thermos=`echo $infoNodes | jq '.nodes[] | select((.attributes.temperature|length)>=1).id' | tr '\n' ' '`
	for i in $thermos
	do
		# as the names assigned to the thermostats appear to be arbitrary, we need to get the parent (receiver) name.
		parentid=`echo $infoNodes | jq ".nodes[] | select(.id==$i).parentNodeId"`
		parentname=`echo $infoNodes | jq ".nodes[] | select(.id==${parentid}).name"`
		echo "	$i associated with $parentname" 
	done
	echo "Recommended Heating config:"
	echo "	RECEIVER_IDs_HEATING=(`echo ${thermos}| sed -e 's/\"//g;'`)"
	echo
	echo "Found water node(s):"
	waters=`echo $infoNodes | jq '.nodes[] | select((.attributes.stateHotWaterRelay|length)>=1).id' | tr '\n' ' '`
	for i in $waters
	do
		parentid=`echo $infoNodes | jq ".nodes[] | select(.id==$i).parentNodeId"`
		parentname=`echo $infoNodes | jq ".nodes[] | select(.id==${parentid}).name"`
		echo "	$i associated with $parentname" 
	done
	echo "Recommended Water config:"
	echo "	RECEIVER_IDs_WATER=(`echo ${waters}| sed -e 's/\"//g;'`)"
	echo 
	echo "Found bulb node(s):"
	bulbs=`echo $infoNodes | jq '.nodes[] | select(.nodeType=="http://alertme.com/schema/json/node.class.light.json#").id' | tr '\n' ' '`
	for i in $bulbs
	do
		name=`echo $infoNodes | jq ".nodes[] | select(.id==$i).name"`
		echo "	$i named $name" 
	done
	echo "Recommended Bulb config:"
	echo "	BULB_IDs=(`echo ${bulbs}| sed -e 's/\"//g;'`)"
	echo 

	echo "Add the nodes of interest to the configuration file: $configFilename"
	echo
	exit 0
}

# get heating nodes data
function getHeatingNodes {
	for i in ${!RECEIVER_IDs_HEATING[@]} 
	do
		#echo $i/${#RECEIVER_IDs_HEATING[@];
		#process the output captured for each node listed, and push it into openhab.
		RECEIVER_ID_HEATING=${RECEIVER_IDs_HEATING[$i]};
		debugLog "=============================="
		debugLog "heating id:$i node: $RECEIVER_ID_HEATING"
		debugLog "=============================="
#TODO confirm this check
		if [ "$RECEIVER_ID_HEATING" == "" ]
		then
			errorLog "config error. No ID found in RECEIVER_IDs_HEATING. exiting";
			exit 1
		fi
		
		#retrieve data
		tIndoors=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.temperature.reportedValue' -r`
		target=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.targetHeatTemperature.reportedValue' -r`
		heatingStatus=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.stateHeatingRelay.reportedValue' -r`
		heatingMode=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeHeatCoolMode.reportedValue' -r`
		heatingASL=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeScheduleLock.reportedValue' -r`
		heatingASL_Target=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeScheduleLock.TargetValue' -r`

		#Prepare values
		if [ "$heatingASL_Target" != null  ]; then heatingASL=$heatingASL_Target; fi
		if [ "$heatingMode" == "HEAT" ]; then
			if [ "$heatingASL" == true ]; then heatingMode="MANUAL"; else heatingMode="SCHEDULE"; fi
		fi
		printf -v tIndoors "%.1f" "$tIndoors"
		printf -v target "%.1f" "$target"
		heatingModeValue=`echo $heatingMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/MANUAL/0/;s/OFF/0/;"`
	
		#'put' (i.e. update) to openhab server
		putInOH "$OPENHAB_SERVER/${ohThermostatTarget[$i]}/state" 	"$target"			"TargetTemp:"
		putInOH "$OPENHAB_SERVER/${ohThermostatTemp[$i]}/state" 	"$tIndoors"			"IndoorTemp:"
		putInOH "$OPENHAB_SERVER/${ohHeatingStatus[$i]}/state"		$heatingStatus		"HeatingStatus:"
		putInOH "$OPENHAB_SERVER/${ohHeatingMode[$i]}/state"		$heatingModeValue	"HeatingMode:$heatingMode: "
	done
	debugLog "OpenHab Heating Update Complete."	
}

# get the water Node data
function getWaterNodes {
	if [ ${#RECEIVER_IDs_WATER[@]} -eq 0 ]; then
		debugLog "no waterIDs contained in configuration RECEIVER_IDs_WATER: ${RECEIVER_IDs_WATER}"
	else
		for i in ${!RECEIVER_IDs_WATER[@]} 
		do
			#echo $i/${#RECEIVER_IDs_WATER[@];
			#process the output captured for each node listed, and push it into openhab.
			RECEIVER_ID_WATER=${RECEIVER_IDs_WATER[$i]};
			debugLog "=============================="
			debugLog "water id:$i node: $RECEIVER_ID_WATER"
			debugLog "=============================="
#TODO confirm this check
			if [ "$RECEIVER_ID_WATER" == "" ]
			then
				errorLog "config error. No ID found in RECEIVER_IDs_WATER. exiting";
				exit
			fi
			
			#retrieve data
			hotWaterStatus=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.stateHotWaterRelay.reportedValue' -r`
			hotWaterASL=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeScheduleLock.reportedValue' -r`
			hotWaterASL_Target=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeScheduleLock.targetValue' -r`
			hotWaterMode=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeHeatCoolMode.reportedValue' -r`
	
			#prepare values
			if [ "$hotWaterASL_Target" != null  ]; then hotWaterASL=$hotWaterASL_Target; fi
			if [ "$hotwaterMode" == "HEAT" ]; then
				if [ "$hotWaterASL" == true ]; then hotwaterMode="MANUAL"; else hotwaterMode="SCHEDULE"; fi
			fi
			hotWaterModeValue=`echo $hotWaterMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/OFF/0/;"`
	
			#'put' (i.e. update) to openhab server
			putInOH $OPENHAB_SERVER/${ohHotWaterStatus[$i]}/state "$hotWaterStatus"
			putInOH "$OPENHAB_SERVER/${ohHotwaterMode[$i]}/state" $hotWaterModeValue		
		done
		debugLog "OpenHab Water Update Complete."
	fi;	
}

# get the Bulb Node data
function getBulbNodes {
	if [ ${#BULB_IDs[@]} -eq 0 ]; then
		debugLog "no bulbID's contained in configuration BULB_IDs: ${BULB_IDs}"
	else
		for i in ${!BULB_IDs[@]} 
		do
			#process the output captured for each node listed, and push it into openhab.
			BULB_ID=${BULB_IDs[$i]};
			debugLog "=============================="
			debugLog "bulb id:$i node: $BULB_ID"
			debugLog "=============================="
#TODO confirm this check
			if [ "$BULB_ID" == "" ]
			then
				errorLog "config error. No ID found in BULB_ID. exiting";
				exit
			fi
	
			#retrieve data
			brightness=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.brightness.reportedValue' -r`		# 1-100 brightness
			propertyStatus=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.brightness.propertyStatus' -r` 	# "COMPLETE"
			state=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.state.reportedValue' -r` 					# "ON"
			presence=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.presence.reportedValue' -r`			# "PRESENT"
			RSSI=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.RSSI.reportedValue' -r`					# "-72 back, -52 front.."
			scheduleEnabled=`echo $infoNodes | jq --arg BULB_ID $BULB_ID '.nodes[] | select(.id == $BULB_ID).attributes.syntheticDeviceConfiguration.targetValue.enabled' -r` # "true"
			
			#prepare values
			modeValue=`echo $scheduleEnabled|sed "s/true/2/;s/null/0/;"`;
			#brightness is the last set value - if off, it does not go to 0.
			if [ "$state" == "OFF" ]; then
				actualBrightness=0;
			else
				actualBrightness=$brightness
			fi

			#'put' (i.e. update) to openhab server
			putInOH "$OPENHAB_SERVER/${bulb_Brightness[$i]}/state" "$actualBrightness" "BulbBrightness:";
			putInOH "$OPENHAB_SERVER/${bulb_State[$i]}/state" "$state" "BulbState:";
			putInOH "$OPENHAB_SERVER/${bulb_Mode[$i]}/state" "$modeValue" "BulbMode:$mode:";
		done
		debugLog "OpenHab Bulb Update Complete."	
	fi
}


# get other data, like external weather. not currently used.
function getOther {
	#jsnWeather=`curl --silent $WEATHER_URL`
	#tOutdoors=`echo $jsnWeather | jq '.weather.temperature.value'`
	#printf -v tOutdoors "%.1f" "$tOutdoors"
	#echo Outside Temp: $tOutdoors
	
	#result=`date +"%Y/%m/%d-%T"`
	#result="$result,$tIndoors,$tOutdoors,$target"
	#echo $result >> /var/www/hive/temphistory.csv
	#curl --header "Content-Type: text/plain" --request PUT --data $tOutdoors $ohURL_Outdoors
	echo nothing;
}

# optionally post to a dashing dashboard.
function postToDashing {
	# Post to dashing server...
	#curl -d '{ "auth_token": "openH4b", "state": '$tIndoors' }' http://localhost:3030/widgets/CH_Indoor_Temp
	#curl -d '{ "auth_token": "openH4b", "state": '$target' }' http://localhost:3030/widgets/CH_Target_Temp
	echo nothing;
}

################################
# main body

# 1. prepare
doCheck;
doInit;

# 2. use stub data or get live
if [ $usetestdata ]; then
	debugLog "Using Test data: $testdata";
	infoNodes=`cat $testdata`
else
	debugLog "Connecting for real data $usetestdata";
#TODO validate login, test for failed pass
	getData;
fi

# 3. Validate data
testData;
#TODO test with 1 thermo. 1 thermo and 1 water. none.

# 4. work with data (a or b.)
# 4a. config step
if [[ $getIDs == "true" ]]; then
	debugLog "Config step - getting ids.";
	getNodeIDs;
	exit 0;
fi

# 4b. retrieve and post the data
getHeatingNodes;
getWaterNodes;
getBulbNodes;

# 5. post processing
#postToDashing;

# terminate with positive message - if success, there should be no other msgs!
echo "OK";
exit;
