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
    printinfo "La notification a été désactivée pour ce projet (variable NOTIFY_MUTE=true)"
    exit 0
fi

printstep "Vérification des paramètres d'entrée"
init_env
int_gitlab_api_env 
check_notify_env

LOGIN_RESULT=`myCurl $ROCKETCHAT_API_URL/login -d "username=$ROCKETCHAT_USER&password=$ROCKETCHAT_PASSWORD"`
LOGIN_STATUS=`echo $LOGIN_RESULT | jq -r .status`
if [[ "$LOGIN_STATUS" != "success" ]]; then 
    printerror "Erreur de connection à $ROCKETCHAT_URL avec l'utilisateur $ROCKETCHAT_USER"
    exit 1
fi

AUTH_TOKEN=`echo $LOGIN_RESULT | jq -r .data.authToken`
ROCKETCHAT_USER_ID=`echo $LOGIN_RESULT | jq -r .data.userId`
PROJECT_PREFIX=${PROJECT_NAME%-*}
PROJECT=${SERVICE_TO_UPDATE:-$PROJECT_PREFIX}
GITLAB_USER_ID=${TRIGGER_USER_ID:-$GITLAB_USER_ID}

if [[ $CI_ENVIRONMENT_URL != "" ]]; then
    APP_DISPLAY_NAME="[$PROJECT]($CI_ENVIRONMENT_URL)"
else
    APP_DISPLAY_NAME=$PROJECT
fi



PROJECT_ID=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects?search=$PROJECT_NAME" | jq --arg project_namespace "$PROJECT_NAMESPACE" '.[] | select(.namespace.name == "\($project_namespace)") | .id'`
LAST_COMMIT_ID=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_ID/repository/commits?per_page=25&page=1&ref_name=$BRANCH_NAME" | jq -r '.[] | select(.message | startswith("Merge branch") | not) | .id' | head -1`
PROJECT_TAG=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/projects/$PROJECT_ID/repository/tags" | jq -r --arg commit_id "$LAST_COMMIT_ID" '.[] | select(.commit.id == "\($commit_id)") | .name'`
USER_NAME=`myCurl --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API_URL/users/$GITLAB_USER_ID" | jq -r .username`

if [[ $PROJECT_TAG != "" ]]; then APP_DISPLAY_NAME="$APP_DISPLAY_NAME $PROJECT_TAG"; fi

if [[ $DEPLOY_STATUS == "success" ]]; then
    EMOJI_STATUS=":white_check_mark:"
    LABEL_STATUS="succès"
else
    EMOJI_STATUS=":negative_squared_cross_mark:"
    LABEL_STATUS="erreurs"
fi

if [[ $DEPLOY_TOOL == "helm" ]]; then
    EMOJI_DEPLOY_TOOL=":k8s:"
fi

DISPLAY_STATUS="[$LABEL_STATUS]($GITLAB_URL/$PROJECT_NAMESPACE/$PROJECT_NAME/builds/$CI_BUILD_ID)"

CHAN_APP=SLN_APP_$PROJECT_PREFIX
ENV_NAME=`echo "$CI_ENVIRONMENT_NAME" | tr '[:upper:]' '[:lower:]'`
CHAN_ENV=SLN_ENV_$ENV_NAME

printstep "Envoi de la notification Rocketchat sur le chan $CHAN_APP"

MSG="$NOTIFY_MENTION $EMOJI_STATUS Application *$APP_DISPLAY_NAME* déployée avec *$DISPLAY_STATUS* par *$USER_NAME* sur *$CI_ENVIRONMENT_NAME* $EMOJI_DEPLOY_TOOL"
PAYLOAD=`jq --arg channel "#$CHAN_APP" --arg msg "$MSG" '. | .channel=$channel | .text=$msg' <<< '{}'`
curl -s --noproxy '*' --header "X-Auth-Token: $AUTH_TOKEN" --header "X-User-Id: $ROCKETCHAT_USER_ID" --header "Content-type:application/json"  $ROCKETCHAT_API_URL/chat.postMessage  -d "$PAYLOAD" | jq .

printstep "Envoi de la notification Rocketchat sur le chan $CHAN_ENV"

PAYLOAD=`jq --arg channel "#$CHAN_ENV" --arg msg "$MSG" '. | .channel=$channel | .text=$msg' <<< '{}'`
curl -s --noproxy '*' --header "X-Auth-Token: $AUTH_TOKEN" --header "X-User-Id: $ROCKETCHAT_USER_ID" --header "Content-type:application/json"  $ROCKETCHAT_API_URL/chat.postMessage  -d "$PAYLOAD" | jq .
