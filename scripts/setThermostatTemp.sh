#!/bin/bash
# Hive set temperature

#https://github.com/lwsrbrts/PoSHive/blob/master/PoSHive.ps1
# 'MANUAL' {$ApiMode = 'HEAT'; $ApiScheduleLock = $true}
#            'SCHEDULE' {$ApiMode = 'HEAT'; $ApiScheduleLock = $false}
#            'OFF' {$ApiMode = 'OFF'; $ApiScheduleLock = $true}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR


echo `date` > ./lastCommand.log
echo --------------- | tee -a ./lastCommand.log
echo Set Temperature called \(args: $1, $2 \)  | tee -a ./lastCommand.log
echo Directory: $DIR  | tee -a ./lastCommand.log


if [[ $# -eq 0 ]] ; then
    echo 'Usage: setThermostatTemp.sh <target> <mode=AUTO|MANUAL|OFF>'
    echo '<mode> defaults to existing state'
    exit 0
fi

source ./config

newMode=${2:-""}

session=`curl -s -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"'$USERID'", "password":"'$PW'","caller":"openhab"}]}' $HIVE_URL/auth/sessions`
sessionId=$(echo $session | python -c 'import sys, json; print json.load(sys.stdin)["sessions"][0]["sessionId"]')
infoNodes=`curl -s -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
thermostatMode=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeHeatCoolMode.targetValue -r` #-r strips the quotes; use targetValue instead of reportedValue
activeScheduleLock=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeScheduleLock.reportedValue -r`

if [ "$newMode" == "" ]; then newMode=$thermostatMode; fi
mode="OFF"
if [ "$newMode" == "AUTO" ]; then
  mode="HEAT"
  activeScheduleLock=false
elif [ "$newMode" == "MANUAL" ]; then
  mode="HEAT"
  activeScheduleLock=true
fi

echo DEBUG: activeScheduleLock = $activeScheduleLock, mode=$mode, current thermostatMode=$thermostatMode, newMode=$newMode

echo USERID: $USERID, Hive URL: $HIVE_URL  | tee -a ./lastCommand.log
echo SessionID: $sessionId  | tee -a ./lastCommand.log
# echo \[DEBUG\] Calling set temp url.... | tee -a ./lastCommand.log

echo Target modes: thermostatMode $mode, activeScheduleLock $activeScheduleLock, targetValue $1 | tee -a ./lastCommand.log
echo Sending commands... | tee -a ./lastCommand.log
setTemp=$(curl -s -k --cookie-jar cookie.jar -X PUT -H "Content-Type: application/vnd.alertme.zoo-6.2+json" \
   -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" \
   -H "X-AlertMe-Client: swagger" -H 'X-Omnia-Access-Token: '"$sessionId" \
   -d '{"nodes":[{"attributes":{"activeHeatCoolMode":{"targetValue":"'$mode'"},"targetHeatTemperature":{"targetValue":'$1'},"activeScheduleLock":{"targetValue":'$activeScheduleLock'}}}]}' \
   "$HIVE_URL/nodes/${RECEIVER_ID_HEATING}")

#echo   \[DEBUG\] $setTemp  | tee -a ./lastCommand.log
echo Verifying whether settings took.... | tee -a ./lastCommand.log
# Check that settings have taken effect.........................
sleep 3
infoNodes=`curl -s -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
target=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.targetHeatTemperature.reportedValue -r`
thermostatMode=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeHeatCoolMode.reportedValue -r` #-r strips the quotes
activeScheduleLock=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.activeScheduleLock.targetValue -r` #reportedValue seems to give incorrect status
heatingStatus=`echo $infoNodes | jq .nodes[$HEATING_NODE].attributes.stateHeatingRelay.reportedValue -r`
if [ $thermostatMode == "HEAT" ] && [ $activeScheduleLock == true ]; then thermostatMode="MANUAL"; fi

#update openhab
curl --header "Content-Type: text/plain" --request PUT --data $thermostatMode "$OPENHAB_SERVER/CH_HeatingMode/state"
curl --header "Content-Type: text/plain" --request PUT --data $target "$OPENHAB_SERVER/CH_Target_Temp/state"
curl --header "Content-Type: text/plain" --request PUT --data "$heatingStatus" "$OPENHAB_SERVER/CH_HeatingStatus/state"

echo Mode check: $thermostatMode, Target Temp: $target, Heating Status: $heatingStatus, activeScheduleLock: $activeScheduleLock| tee -a ./lastCommand.log

# Tidy up
curl -s -k -X DELETE --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" \
   -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" \
   -H "X-AlertMe-Client: Hive Web Dashboard" -H 'X-Omnia-Access-Token: '"$sessionId" \
   "$HIVE_URL/auth/sessions/${sessionId}"

echo Hive target temperature set to $1 [ Heating Status: $heatingStatus, Thermostat Mode: $thermostatMode ]
