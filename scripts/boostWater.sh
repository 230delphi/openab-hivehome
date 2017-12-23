#!/bin/bash
# Hive Boost function (change duration and target temperature in boost curl)


DIR="$( cd "$( dirname "${BASH_SOURCE[$HOTWATER_NODE]}" )" && pwd )"
cd $DIR

echo `date` > ./lastCommand.log
echo --------------- Boost called  > ./lastCommand.log
echo Directory: $DIR  >> ./lastCommand.log

if [[ $# -eq 0 ]] ; then
    echo 'Usage: boostWater.sh <BOOST|CANCEL> <duration>'
    echo No arguments provided. Exiting > ./lastCommand.log
    exit 0
fi

source ./config

mode=${1:-"BOOST"}
duration=${2:-15}

echo Arguments - mode: $mode, duration $duration >> ./lastCommand.log

echo USERID: $USERID, Hive URL: $HIVE_URL  >> ./lastCommand.log
#echo PATH: $PATH   >> ./lastCommand.log

session=`curl --silent -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
#echo Session: $session  >> ./lastCommand.log
sessionId=$(echo $session | python -c 'import sys, json; print json.load(sys.stdin)["sessions"][0]["sessionId"]')

echo SessionID: $sessionId  >> ./lastCommand.log

if [[ "$mode" == BOOST ]]; then
  echo Boosting Hotwater... | tee >> ./lastCommand.log

  boost=$(curl -s -k --cookie-jar cookie.jar -X PUT -H "Content-Type: application/vnd.alertme.zoo-6.2+json" \
     -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" \
     -H "X-AlertMe-Client: swagger" -H 'X-Omnia-Access-Token: '"$sessionId" \
     -d '{"nodes":[{"attributes":{"activeHeatCoolMode":{"targetValue":"'$mode'"},"scheduleLockDuration":{"targetValue":'$duration'},"targetHeatTemperature":{"targetValue":99}}}]}' \
     "$HIVE_URL/nodes/${RECEIVER_ID_WATER}")

   #echo $boost >> /.lastCommand.log
   echo Hot water boosted for $duration minutes | tee >> /.lastCommand.log

else
  echo Cancelling hot water boost... | tee >> ./lastCommand.log
  #Check if we are already boosted
  infoNodes=`curl -s -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
  thermostatMode=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeHeatCoolMode.reportedValue -r` #-r strips the quotes
  #echo thermostatMode: $thermostatMode
  if [ "BOOST" != "$thermostatMode" ]; then
    #echo Cannot cancel boost as we are not in boost mode - current mode: $thermostatMode
    echo Cannot cancel hot water boost as we are not in boost mode - current mode: $thermostatMode | tee >> ./lastCommand.log
  else
    prevMode=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.previousConfiguration.reportedValue.mode -r` #-r strips quotes
    prevTemp=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.previousConfiguration.reportedValue.targetHeatTemperature`
    if [ "$prevMode" == "MANUAL" ]; then activeScheduleLock=true; else activeScheduleLock=false; fi
    if [ "$prevMode" == "AUTO" ] || [ "$prevMode" == "MANUAL" ]; then prevMode="HEAT"; fi
    prevTemp=${prevTemp%.*}
    #if [ "$prevTemp" -ge 30 ]; then prevTemp=18; fi

    boost=$(curl -s -k --cookie-jar cookie.jar -X PUT -H "Content-Type: application/vnd.alertme.zoo-6.2+json" \
       -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" \
       -H "X-AlertMe-Client: swagger" -H 'X-Omnia-Access-Token: '"$sessionId" \
       -d '{"nodes":[{"attributes":{"activeHeatCoolMode":{"targetValue":"'$prevMode'"},"targetHeatTemperature":{"targetValue":'$prevTemp'},"activeScheduleLock":{"targetValue":'$activeScheduleLock'}}}]}' \
       "$HIVE_URL/nodes/${RECEIVER_ID_WATER}")

    #echo Heating boost cancelled
    echo Hot water boost cancelled | tee >> /.lastCommand.log
  fi
fi

sleep 5 #Wait for boiler state to update
infoNodes=`curl -s -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
target=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.targetHeatTemperature.reportedValue -r`
thermostatMode=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeHeatCoolMode.reportedValue -r` #-r strips the quotes
activeScheduleLock=`echo $infoNodes | jq .nodes[$HOTWATER_NODE].attributes.activeScheduleLock.reportedValue -r`
if [ $thermostatMode == "HEAT" ] && [ $activeScheduleLock == true ]; then thermostatMode="MANUAL"; fi

#update openhab
curl --header "Content-Type: text/plain" --request PUT --data $thermostatMode "$OPENHAB_SERVER/CH_HotWaterMode/state"
#curl --header "Content-Type: text/plain" --request PUT --data $target "$OPENHAB_SERVER/CH_Target_Temp/state"

echo Hotwater Mode check: $thermostatMode, Target Temp: $target | tee >> ./lastCommand.log

#Logout
curl -s -k -X DELETE --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" \
   -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" \
   -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId" \
   "$HIVE_URL/auth/sessions/${sessionId}"
