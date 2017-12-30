#!/bin/bash
debug=true
verbose=false
debugFilename=hive.log
errorFilename=$debugFilename


# connect timeouts used with curl commands to OpenHab
openHabTimeout="--connect-timeout 4 --max-time 10"
# connect timeouts used with curl commands to hive on Internet - allow longer.
hiveTimeout="--connect-timeout 10 --max-time 20"

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
source ./config

if [ -f "./cookie.jar" ];
then
	rm ./cookie.jar
fi

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

function commandLog {
	echo nothing
}

function errorLog {
	echo "ERROR: $1" >> $errorFilename;
	if [ "$verbose" == "true" ]
	then
		echo "ERROR: $1";
	fi
}



function getData {
	#Login...
	session=`curl $hiveTimeout --silent -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
	
	debug "echo Session: `echo $session | jq .`"
	
	sessionId=`echo $session | jq .sessions[].sessionId`
	#remove quotes from beginning/end
	sessionId="${sessionId%\"}"
	sessionId="${sessionId#\"}"
	#echo SessionID: $sessionId
	
	infoNodes=`curl $hiveTimeout --silent -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
	echo $infoNodes > raw.json
	echo $infoNodes | jq . > debug.json
	
	#Logout
	curl $hiveTimeout -s -k -X DELETE --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'"  -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId"  "$HIVE_URL/auth/sessions/${sessionId}"
}


#for index in ${!array[@]}; do
#    echo $index/${#array[@]}
#done

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
			exit
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
		#ohURL_Outdoors="$OPENHAB_SERVER/CH_Outdoor_Temp/state"
		ohURL_heatingStatus="$OPENHAB_SERVER/${ohHeatingStatus[$i]}/state"
		ohURL_heatingMode="$OPENHAB_SERVER/${ohHeatingMode[$i]}/state"
				
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $target $ohURL_Thermostat
		debugLog "indoor $target $ohURL_Thermostat"
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $tIndoors $ohURL_Indoors
		debugLog "Heating status: $heatingStatus $ohURL_heatingStatus"
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $heatingStatus $ohURL_heatingStatus
		heatingModeValue=`echo $heatingMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/MANUAL/0/;s/OFF/0/;"`
		debugLog "heat mode: $heatingModeValue $ohURL_heatingMode"
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $heatingModeValue $ohURL_heatingMode
		debugLog "OpenHab Update Complete."	
	done
}

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
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $hotWaterStatus $ohURL_hotWaterStatus
		hotWaterModeValue=`echo $hotWaterMode|sed "s/HEAT/2/;s/SCHEDULE/2/;s/BOOST/1/;s/OFF/0/;"`
		debugLog "water mode $hotWaterModeValue $ohURL_hotwaterMode"
		curl $openHabTimeout --header "Content-Type: text/plain" --request PUT --data $hotWaterModeValue $ohURL_hotwaterMode
	done
}

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

function postDashing {
	# Post to dashing server...
	#curl -d '{ "auth_token": "openH4b", "state": '$tIndoors' }' http://localhost:3030/widgets/CH_Indoor_Temp
	#curl -d '{ "auth_token": "openH4b", "state": '$target' }' http://localhost:3030/widgets/CH_Target_Temp
	echo nothing;
}

#getData;
infoNodes=`cat debug.json`
getHeatingNodes;
getWaterNodes;
exit;