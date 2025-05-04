#!/bin/bash

# Define color variables
BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'

NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'

clear



# Instruction for entering the region
read -p "${GREEN}${BOLD_TEXT}Enter the region:${RESET_FORMAT} " REGION
export REGION=$REGION

# Instruction for setting project ID
export PROJECT_ID=$(gcloud config get-value project)
gcloud config set compute/region $REGION

# Enabling required services
gcloud services enable apigateway.googleapis.com --project $DEVSHELL_PROJECT_ID
gcloud services enable run.googleapis.com

sleep 20

# Adding IAM policy bindings
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/serviceusage.serviceUsageAdmin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/artifactregistry.reader"

sleep 30

# Cloning the repository
git clone https://github.com/GoogleCloudPlatform/nodejs-docs-samples.git
cd nodejs-docs-samples/functions/helloworld/helloworldGet

sleep 60

# Deploying the Cloud Function
deploy_function() {
  gcloud functions deploy helloGET \
    --runtime nodejs20 \
    --region $REGION \
    --trigger-http \
    --allow-unauthenticated
}

deploy_success=false

while [ "$deploy_success" = false ]; do
  if deploy_function; then
    echo "${GREEN_TEXT}${BOLD_TEXT}Cloud Run service is created. Exiting the loop.${RESET_FORMAT}"
    deploy_success=true
  else
    echo "${RED_TEXT}${BOLD_TEXT}Waiting for Cloud Run service to be created...${RESET_FORMAT}"
    sleep 60
  fi
done


# Describing the deployed function
gcloud functions describe helloGET --region $REGION

# Testing the deployed function
curl -v https://$REGION-$PROJECT_ID.cloudfunctions.net/helloGET

cd ~

# Creating the OpenAPI specification file
cat > openapi2-functions.yaml <<EOF_CP
# openapi2-functions.yaml
swagger: '2.0'
info:
  title: API_ID description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello
      x-google-backend:
        address: https://us-east4-qwiklabs-gcp-01-b47a65687b9f.cloudfunctions.net/helloGET
      responses:
       '200':
          description: A successful response
          schema:
            type: string
EOF_CP

# Generating a unique API ID
export API_ID="hello-world-$(cat /dev/urandom | tr -dc 'a-z' | fold -w ${1:-8} | head -n 1)"
sed -i "s/API_ID/${API_ID}/g" openapi2-functions.yaml
sed -i "s/PROJECT_ID/$PROJECT_ID/g" openapi2-functions.yaml

# Creating the API Gateway
export API_ID="hello-world-$(cat /dev/urandom | tr -dc 'a-z' | fold -w ${1:-8} | head -n 1)"
echo $API_ID
gcloud api-gateway apis create "hello-world-api"  --project=$PROJECT_ID
gcloud api-gateway api-configs create hello-world-config --project=$PROJECT_ID --api=$API_ID --openapi-spec=openapi2-functions.yaml --backend-auth-service-account=$PROJECT_NUMBER-compute@developer.gserviceaccount.com
gcloud api-gateway gateways create hello-gateway --location=$REGION --project=$PROJECT_ID --api=$API_ID --api-config=hello-world-config

# Creating an API key
gcloud alpha services api-keys create --display-name="awesome"  
KEY_NAME=$(gcloud alpha services api-keys list --format="value(name)" --filter "displayName=awesome") 
export API_KEY=$(gcloud alpha services api-keys get-key-string $KEY_NAME --format="value(keyString)") 
echo $API_KEY

# Enabling the managed service
MANAGED_SERVICE=$(gcloud api-gateway apis list --format json | jq -r .[0].managedService | cut -d'/' -f6)
echo $MANAGED_SERVICE

gcloud services enable $MANAGED_SERVICE

# Creating another OpenAPI specification file
cat > openapi2-functions2.yaml <<EOF_CP
# openapi2-functions.yaml
swagger: '2.0'
info:
  title: API_ID description
  description: Sample API on API Gateway with a Google Cloud Functions backend
  version: 1.0.0
schemes:
  - https
produces:
  - application/json
paths:
  /hello:
    get:
      summary: Greet a user
      operationId: hello
      x-google-backend:
        address: https://$REGION-$PROJECT_ID.cloudfunctions.net/helloGET
      security:
        - api_key: []
      responses:
       '200':
          description: A successful response
          schema:
            type: string
securityDefinitions:
  api_key:
    type: "apiKey"
    name: "key"
    in: "query"
EOF_CP

# Updating the API Gateway configuration
sed -i "s/API_ID/${API_ID}/g" openapi2-functions2.yaml
sed -i "s/PROJECT_ID/$PROJECT_ID/g" openapi2-functions2.yaml

gcloud api-gateway api-configs create hello-config --project=$PROJECT_ID \
  --display-name="Hello Config" --api=$API_ID --openapi-spec=openapi2-functions2.yaml \
  --backend-auth-service-account=$PROJECT_ID@$PROJECT_ID.iam.gserviceaccount.com	

gcloud api-gateway gateways update hello-gateway --location=$REGION --project=$PROJECT_ID --api=$API_ID --api-config=hello-config

# Adding IAM policy bindings
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECT_ID@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/serviceusage.serviceUsageAdmin"

gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" --role="roles/serviceusage.serviceUsageAdmin"

# Enabling the managed service again
MANAGED_SERVICE=$(gcloud api-gateway apis list --format json | jq -r --arg api_id "$API_ID" '.[] | select(.name | endswith($api_id)) | .managedService' | cut -d'/' -f6)
echo $MANAGED_SERVICE

gcloud services enable $MANAGED_SERVICE

# Fetching the Gateway URL
export GATEWAY_URL=$(gcloud api-gateway gateways describe hello-gateway --location $REGION --format json | jq -r .defaultHostname)
curl -sL $GATEWAY_URL/hello

# Testing the API Gateway with the API key
curl -sL -w "\n" $GATEWAY_URL/hello?key=$API_KEY

# Completion Message

echo -e "${GREEN_TEXT}${BOLD_TEXT}Subscribe my Channel (QwikLab Explorers):${RESET_FORMAT} ${CYAN_TEXT}${BOLD_TEXT}https://www.youtube.com/@qwiklabexplorers${RESET_FORMAT}"
echo
