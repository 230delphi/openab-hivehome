#!/bin/bash
# original work from smar: https://community.openhab.org/t/hive-thermostat-british-gas-tutorial/36371
# script to logon to hivehome, retrieve data and update openhab
#
# main configuration is contained within:
configFilename="./hive.config"
errorFilename=hive-error.log
getIDs=
scriptOpts="$@"

#default curl command
curlCmd="curl --silent -g"
# connect timeouts used with curl commands to OpenHab
openHabCurlOPTS="-k --connect-timeout 4 --max-time 10"
# connect timeouts used with curl commands to hive on Internet - allow longer.
hiveCurlOPTS="--cookie-jar cookie.jar --connect-timeout 10 --max-time 20"

#log messages if debug enabled
function debugLog {
	if [ $debug ]
	then
	echo "DEBUG: $1" >> $debugFilename
		if [ "$verbose" == "true" ]
		then
				echo "DEBUG: $1";
		fi
	fi	
}

# always log errors
function errorLog {
	echo "ERROR: $1" >> $errorFilename;
	echo "ERROR: $1";
}

# pre checks
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

# print help
function printHelp {
	echo "README.md";
	echo "-v : verbose";
	echo "-getIDs : get IDs";
	exit 0;
}

# initialize script/env and passed parameters
function doInit {
	cd $DIR
	source $configFilename
	if [ -f "./cookie.jar" ]; then
		rm ./cookie.jar
	fi
	debugLog "Parsing options: $scriptOpts"
	for i in "$scriptOpts"
	do
		case $i in
		    -h)
		    printHelp;
		    ;;
		    -getIDs)
		    getIDs=true
		    ;;
		    -v)
		    verbose=true
		    ;;
		    *)
			# unknown option
		    ;;
		esac
	done
}

# get the data from hive
function getData {
	#Login...
	session=`$curlCmd $hiveCurlOPTS -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
	
	debugLog "echo Session: `echo $session | jq .`"
	
	sessionId=`echo $session | jq .sessions[].sessionId`
	#remove quotes from beginning/end
	sessionId="${sessionId%\"}"
	sessionId="${sessionId#\"}"
	debugLog "SessionID: $sessionId"
	
	infoNodes=`$curlCmd $hiveCurlOPTS -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
	
	debugLog $infoNodes
	if [ $debug ]
	then
		debugjson=debug.json
		echo $infoNodes | jq . > $debugjson
		debugLog "Logged formatted to $debugjson"
	fi
	
	#Logout
	$curlCmd $hiveCurlOPTS -X DELETE -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'"  -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId"  "$HIVE_URL/auth/sessions/${sessionId}"
}

# identify heating and water nodes
function getNodeIDs {
	echo $infoNodes |jq . > nodes.jsn
	echo "Thermostat node(s):"
	thermos=`echo $infoNodes | jq '.nodes[] | select((.attributes.temperature|length)>=1).id' | sed -e 's/\"//g;'| tr '\n' ' '`
	echo "RECEIVER_IDs_HEATING=(${thermos})"
	echo
	echo "Water node(s):"
	waters=`echo $infoNodes | jq '.nodes[] | select((.attributes.stateHotWaterRelay|length)>=1).id' | sed -e 's/\"//g'| tr '\n' ' '`
	echo "RECEIVER_IDs_WATER=(${waters})"
	echo 
	echo "Add the nodes of interest to the configuration file: $configFilename"
	exit 0
}

# get heating nodes data
function getHeatingNodes {
	for i in ${!RECEIVER_IDs_HEATING[@]} 
	do
		#echo $i/${#RECEIVER_IDs_HEATING[@];
		#process the output captured for each node listed, and push it into openhab.
		RECEIVER_ID_HEATING=${RECEIVER_IDs_HEATING[$i]};
		debugLog "id:$i node: $RECEIVER_ID_HEATING"
		if [ "$RECEIVER_ID_HEATING" == "" ]
		then
			echo error - no id found
			exit 1
		fi
	
		tIndoors=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.temperature.reportedValue' -r`
		target=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.targetHeatTemperature.reportedValue' -r`
		heatingStatus=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.stateHeatingRelay.reportedValue' -r`
		heatingMode=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeHeatCoolMode.reportedValue' -r`
		heatingASL=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeScheduleLock.reportedValue' -r`
		heatingASL_Target=`echo $infoNodes | jq --arg RECEIVER_ID_HEATING $RECEIVER_ID_HEATING '.nodes[] | select(.id == $RECEIVER_ID_HEATING).attributes.activeScheduleLock.TargetValue' -r`

		if [ "$heatingASL_Target" != null  ]; then heatingASL=$heatingASL_Target; fi
		if [ "$heatingMode" == "HEAT" ]; then
			if [ "$heatingASL" == true ]; then heatingMode="MANUAL"; else heatingMode="SCHEDULE"; fi
		fi
		printf -v tIndoors "%.1f" "$tIndoors"
		printf -v target "%.1f" "$target"
		debugLog "=============================="
		debugLog "Indoor Temp:  $tIndoors"
		debugLog "Target Temp: $target"
		debugLog "Heating Status: $heatingStatus"
		debugLog "Heating Mode: $heatingMode"
		debugLog "Updating OpenHab..."
	
		#'put' (i.e. update) to openhab server
		ohURL_Thermostat="$OPENHAB_SERVER/${ohThermostatTarget[$i]}/state"
		ohURL_Indoors="$OPENHAB_SERVER/${ohThermostatTemp[$i]}/state"
		ohURL_heatingStatus="$OPENHAB_SERVER/${ohHeatingStatus[$i]}/state"
		ohURL_heatingMode="$OPENHAB_SERVER/${ohHeatingMode[$i]}/state"
				
		$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $target $ohURL_Thermostat
		debugLog "indoor $target $ohURL_Thermostat"
		$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $tIndoors $ohURL_Indoors
		debugLog "Heating status: $heatingStatus $ohURL_heatingStatus"
		$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $heatingStatus $ohURL_heatingStatus
		heatingModeValue=`echo $heatingMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/MANUAL/0/;s/OFF/0/;"`
		debugLog "heat mode: $heatingModeValue $ohURL_heatingMode"
		$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $heatingModeValue $ohURL_heatingMode
		debugLog "OpenHab Update Complete."	
	done
}

# get the water Node data
function getWaterNodes {
	for i in ${!RECEIVER_IDs_WATER[@]} 
	do
		#echo $i/${#RECEIVER_IDs_WATER[@];
		#process the output captured for each node listed, and push it into openhab.
		RECEIVER_ID_WATER=${RECEIVER_IDs_WATER[$i]};
		debugLog "id:$i node: $RECEIVER_ID_WATER"
		if [ "$RECEIVER_ID_WATER" == "" ]
		then
			echo error - no id found
			exit
		fi

		hotWaterStatus=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.stateHotWaterRelay.reportedValue' -r`
		hotWaterASL=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeScheduleLock.reportedValue' -r`
		hotWaterASL_Target=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeScheduleLock.targetValue' -r`
		hotWaterMode=`echo $infoNodes | jq --arg RECEIVER_ID_WATER $RECEIVER_ID_WATER '.nodes[] | select(.id == $RECEIVER_ID_WATER).attributes.activeHeatCoolMode.reportedValue' -r`
		if [ "$hotWaterASL_Target" != null  ]; then hotWaterASL=$hotWaterASL_Target; fi
		if [ "$hotwaterMode" == "HEAT" ]; then
			if [ "$hotWaterASL" == true ]; then hotwaterMode="MANUAL"; else hotwaterMode="SCHEDULE"; fi
		fi
		debugLog "=============================="
		debugLog "Hot Water Status: $hotWaterStatus"
		debugLog "Hot Water Mode: $hotWaterMode"
		
		ohURL_hotWaterStatus="$OPENHAB_SERVER/${ohHotWaterStatus[$i]}/state"
		ohURL_hotwaterMode="$OPENHAB_SERVER/${ohHotwaterMode[$i]}/state"
		
		
		debugLog "water status: $hotWaterStatus $ohURL_hotWaterStatus"
		$curlCmd $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $hotWaterStatus $ohURL_hotWaterStatus
		hotWaterModeValue=`echo $hotWaterMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/OFF/0/;"`
		debugLog "water mode $hotWaterModeValue $ohURL_hotwaterMode"
		curl $openHabCurlOPTS --header "Content-Type: text/plain" --request PUT --data $hotWaterModeValue $ohURL_hotwaterMode
	done
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
# do it!
doCheck;
doInit;
#getData;
infoNodes=`cat debug.json`
echo $getIDs
if [ $getIDs ]; then
	getNodeIDs;
	exit 0;
fi
getHeatingNodes;
getWaterNodes;
#postToDashing;
echo "OK";
exit;