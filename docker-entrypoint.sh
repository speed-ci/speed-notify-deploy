#!/bin/bash
set -e

source /init.sh

check_notify_env () {
    if [[ -z $ROCKETCHAT_URL ]];then
        printerror "La variable d'environnement ROCKETCHAT_URL doit être renseignée au lancement du container (ex: -e ROCKETCHAT_URL=XXXXXXXX)"
        exit 1
    fi
    if [[ -z $ROCKETCHAT_USER ]];then
        printerror "La variable d'environnement ROCKETCHAT_USER doit être renseignée au lancement du container (ex: -e ROCKETCHAT_USER=XXXXXXXX)"
        exit 1
    fi
    if [[ -z $ROCKETCHAT_PASSWORD ]];then
        printerror "La variable d'environnement ROCKETCHAT_PASSWORD doit être renseignée au lancement du container (ex: -e ROCKETCHAT_PASSWORD=XXXXXXXX)"
        exit 1
    fi    
}

printmainstep "Notification du déploiement du macroservice sur Rocketchat"
printstep "Vérification des paramètres d'entrée"

init_env
check_notify_env

ROCKETCHAT_API_URL=$ROCKETCHAT_URL/api/v1

LOGIN_RESULT=`curl -s --noproxy '*' $ROCKETCHAT_API_URL/login -d "username=$ROCKETCHAT_USER&password=$ROCKETCHAT_PASSWORD"`
LOGIN_STATUS=`echo $LOGIN_RESULT | jq .status | tr -d '"'`
if [[ "$LOGIN_STATUS" != "success" ]]; then 
    printerror "Erreur de connection à $ROCKETCHAT_URL avec l'utilisateur $ROCKETCHAT_USER"
    exit 1
fi

AUTH_TOKEN=`echo $LOGIN_RESULT | jq .data.authToken | tr -d '"'`
USER_ID=`echo $LOGIN_RESULT | jq .data.userId | tr -d '"'`
PROJECT_PREFIX=${PROJECT_NAME%-*}

MSG=":white_check_mark: L application $PROJECT_PREFIX a été déployée avec succès\n Accès aux logs : $GITLAB_URL/$PROJECT_NAMESPACE/$PROJECT_NAME/builds/$CI_BUILD_ID"

PAYLOAD=`jq --arg channel '#SLN_tests-rocketchat' --arg msg "$MSG" '. | .channel=$channel | .text=$msg' <<< '{}'`

curl --noproxy '*' --header "X-Auth-Token: $AUTH_TOKEN" --header "X-User-Id: $USER_ID" --header "Content-type:application/json"  $ROCKETCHAT_API_URL/chat.postMessage  -d "$PAYLOAD" | jq
