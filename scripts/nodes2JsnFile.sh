#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $DIR
source ./config


if [ -f "./cookie.jar" ];
then
	rm ./cookie.jar
fi

#Login...
#TODO message to ensure he changes password
session=`curl -v -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.1+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: Hive Web Dashboard" -d '{"sessions":[{"username":"user", "password":"passs","caller":"openhab"}]}' $HIVE_URL/auth/sessions`

echo Session: `echo $session | jq .`

sessionId=`echo $session | jq .sessions[].sessionId`
#remove quotes from beginning/end
sessionId="${sessionId%\"}"
sessionId="${sessionId#\"}"
echo SessionID: $sessionId

#---------------------------------------------------------------------------------------------
#Get Info Nodes and save to file
infoNodes=`curl -k --cookie-jar cookie.jar -g -H "Content-Type: application/vnd.alertme.zoo-6.2+json" -H "Accept: application/vnd.alertme.zoo-6.2+json" -H "Content-Type: 'application/*+json'" -H "X-AlertMe-Client: swagger" -H "X-Omnia-Access-Token: $sessionId" $HIVE_URL/nodes`
echo $infoNodes > ./nodes.jsn
#echo InfoNodes: `echo $infoNodes | jq .`
