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
    ROCKETCHAT_API_URL=$ROCKETCHAT_URL/api/v1
}

printmainstep "Notification du déploiement du macroservice sur Rocketchat"

if [[ "$NOTIFY_MUTE" == "true" ]]; then
    printinf "La notification a été désactivée pour ce projet (variable NOTIFY_MUTE=true)"
    exit 0
fi

printstep "Vérification des paramètres d'entrée"
init_env
int_gitlab_api_env 
check_notify_env

LOGIN_RESULT=`curl -s --noproxy '*' $ROCKETCHAT_API_URL/login -d "username=$ROCKETCHAT_USER&password=$ROCKETCHAT_PASSWORD"`
LOGIN_STATUS=`echo $LOGIN_RESULT | jq .status | tr -d '"'`
if [[ "$LOGIN_STATUS" != "success" ]]; then 
    printerror "Erreur de connection à $ROCKETCHAT_URL avec l'utilisateur $ROCKETCHAT_USER"
    exit 1
fi

AUTH_TOKEN=`echo $LOGIN_RESULT | jq .data.authToken | tr -d '"'`
USER_ID=`echo $LOGIN_RESULT | jq .data.userId | tr -d '"'`
PROJECT_PREFIX=${PROJECT_NAME%-*}

echo "CI_ENVIRONMENT_URL: $CI_ENVIRONMENT_URL"
if [[ $CI_ENVIRONMENT_URL != "" ]]; then
    APP_DISPLAY_NAME="[$PROJECT_PREFIX]($CI_ENVIRONMENT_URL)"
else
    APP_DISPLAY_NAME=$PROJECT_PREFIX
fi

if [[ $DEPLOY_STATUS == "success" ]]; then
    EMOJI_STATUS=":white_check_mark:"
    LABEL_STATUS="succès"
else
    EMOJI_STATUS=":negative_squared_cross_mark:"
    LABEL_STATUS="erreurs"
fi

CHAN_APP=SLN_APP_$PROJECT_PREFIX
ENV_NAME=`echo "$CI_ENVIRONMENT_NAME" | tr '[:upper:]' '[:lower:]'`
CHAN_ENV=SLN_ENV_$ENV_NAME

printstep "Envoi de la notification Rocketchat sur le chan $CHAN_APP"

MSG="$EMOJI_STATUS Application *$APP_DISPLAY_NAME* déployée avec *$LABEL_STATUS* sur *$CI_ENVIRONMENT_NAME* (accès aux logs : $GITLAB_URL/$PROJECT_NAMESPACE/$PROJECT_NAME/builds/$CI_BUILD_ID)"
PAYLOAD=`jq --arg channel "#$CHAN_APP" --arg msg "$MSG" '. | .channel=$channel | .text=$msg' <<< '{}'`
curl -s --noproxy '*' --header "X-Auth-Token: $AUTH_TOKEN" --header "X-User-Id: $USER_ID" --header "Content-type:application/json"  $ROCKETCHAT_API_URL/chat.postMessage  -d "$PAYLOAD" | jq .

printstep "Envoi de la notification Rocketchat sur le chan $CHAN_ENV"

PAYLOAD=`jq --arg channel "#$CHAN_ENV" --arg msg "$MSG" '. | .channel=$channel | .text=$msg' <<< '{}'`
curl -s --noproxy '*' --header "X-Auth-Token: $AUTH_TOKEN" --header "X-User-Id: $USER_ID" --header "Content-type:application/json"  $ROCKETCHAT_API_URL/chat.postMessage  -d "$PAYLOAD" | jq .
