#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
source ./config


if [ -f "./cookie.jar" ];
then
	rm ./cookie.jar
fi

#Login...
session=`curl --silent -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`

#echo Session: `echo $session | jq .`

sessionId=`echo $session | jq .sessions[].sessionId`
#remove quotes from beginning/end
sessionId="${sessionId%\"}"
sessionId="${sessionId#\"}"
#echo SessionID: $sessionId

infoNodes=`curl --silent -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
#echo InfoNodes: `echo $infoNodes | jq .`

#Logout
curl -s -k -X DELETE --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'"  -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId"  "$HIVE_URL/auth/sessions/${sessionId}"

tIndoors=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.temperature.reportedValue -r`
target=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.targetHeatTemperature.reportedValue -r`
heatingStatus=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.stateHeatingRelay.reportedValue -r`
heatingMode=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeHeatCoolMode.reportedValue -r`
heatingASL=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeScheduleLock.reportedValue -r` #targetValue when it's there, is seems to be more accurate. But not always there.
heatingASL_Target=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeScheduleLock.TargetValue -r` 

hotWaterStatus=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.stateHotWaterRelay.reportedValue -r` #Hot water is on Node 4 - another Your receiver
hotWaterASL=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeScheduleLock.reportedValue -r`
hotWaterASL_Target=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeScheduleLock.targetValue -r`
hotwaterMode=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeHeatCoolMode.reportedValue -r`

if [ "$heatingASL_Target" != null  ]; then heatingASL = $heatingASL_Target; fi
if [ "$hotWaterASL_Target" != null  ]; then hotWaterASL = $hotWaterASL_Target; fi

if [ "$heatingMode" == "HEAT" ]; then
	if [ "$heatingASL" == true ]; then heatingMode="MANUAL"; else heatingMode="SCHEDULE"; fi
fi

if [ "$hotwaterMode" == "HEAT" ]; then
	if [ "$hotWaterASL" == true ]; then hotwaterMode="MANUAL"; else hotwaterMode="SCHEDULE"; fi
fi
jsnWeather=`curl --silent $WEATHER_URL`
tOutdoors=`echo $jsnWeather | jq '.weather.temperature.value'`


printf -v tIndoors "%.1f" "$tIndoors"
printf -v tOutdoors "%.1f" "$tOutdoors"
printf -v target "%.1f" "$target"

echo ==============================
echo Indoor Temp:  $tIndoors
echo Outside Temp: $tOutdoors
echo Target Temp: $target
echo Heating Status: $heatingStatus
echo Heating Mode: $heatingMode
echo
echo Hot Water Status: $hotWaterStatus
echo Hot Water Mode: $hotwaterMode
echo

result=`date +"%Y/%m/%d-%T"`
result="$result,$tIndoors,$tOutdoors,$target"
#echo $result >> /var/www/hive/temphistory.csv

#'put' (i.e. update) to openhab server
ohURL_Thermostat="$OPENHAB_SERVER/CH_Target_Temp/state"
ohURL_Indoors="$OPENHAB_SERVER/CH_Indoor_Temp/state"
ohURL_Outdoors="$OPENHAB_SERVER/CH_Outdoor_Temp/state"
ohURL_heatingStatus="$OPENHAB_SERVER/CH_HeatingStatus/state"
ohURL_hotWaterStatus="$OPENHAB_SERVER/CH_HotWaterStatus/state"
ohURL_heatingMode="$OPENHAB_SERVER/CH_HeatingMode/state"
ohURL_hotwaterMode="$OPENHAB_SERVER/CH_HotWaterMode/state"

#echo $ohURL_Thermostat

curl --header "Content-Type: text/plain" --request PUT --data $target $ohURL_Thermostat
curl --header "Content-Type: text/plain" --request PUT --data $tIndoors $ohURL_Indoors
curl --header "Content-Type: text/plain" --request PUT --data $tOutdoors $ohURL_Outdoors
curl --header "Content-Type: text/plain" --request PUT --data "$heatingStatus" $ohURL_heatingStatus
curl --header "Content-Type: text/plain" --request PUT --data "$hotWaterStatus" $ohURL_hotWaterStatus
curl --header "Content-Type: text/plain" --request PUT --data "$hotwaterMode" $ohURL_hotwaterMode
curl --header "Content-Type: text/plain" --request PUT --data "$heatingMode" $ohURL_heatingMode

# Post to dashing server...
curl -d '{ "auth_token": "openH4b", "state": '$tIndoors' }' http://localhost:3030/widgets/CH_Indoor_Temp
curl -d '{ "auth_token": "openH4b", "state": '$target' }' http://localhost:3030/widgets/CH_Target_Temp
