#!/bin/sh

RESULT_CONFIGMAP_NAME='nvidia-nim-validation-result'
DATA_CONFIGMAP_NAME='nvidia-nim-images-data'
IMAGE_PULL_SECRET_NAME='nvidia-nim-image-pull'

function verify_result_configmap_exists() {
  if ! oc get configmap "${RESULT_CONFIGMAP_NAME}" &>/dev/null; then
    echo "Result ConfigMap doesn't exist, creating"
    oc create configmap "${RESULT_CONFIGMAP_NAME}" --from-literal validation_result="false"
  fi
}

function write_result_configmap_value() {
  oc patch configmap "${RESULT_CONFIGMAP_NAME}" -p '"data": { "validation_result": "'${1}'" }'
}

function write_last_valid_time() {
  oc patch configmap "${RESULT_CONFIGMAP_NAME}" -p '"data": { "last_valid_time": "'$(date -Is)'" }'
}

function create_image_pull_secret() {
  if ! oc get secret "${IMAGE_PULL_SECRET_NAME}" &>/dev/null; then
    echo "Image Pull Secret doesn't exist, creating"

    api_key=$(get_api_key)
    decoded_api_key=$(printf $api_key | base64 -d)

    oc create secret docker-registry "${IMAGE_PULL_SECRET_NAME}" \
     --docker-server=nvcr.io \
     --docker-username='$oauthtoken' \
     --docker-password=${decoded_api_key}
   fi
}

function delete_image_pull_secret() {
  oc delete secret "${IMAGE_PULL_SECRET_NAME} --all-namespace=true --ignore-not-found=true"
}

function success() {
  echo "Validation succeeded, enabling image"
  verify_result_configmap_exists
  write_result_configmap_value true
  write_last_valid_time
}

function failure() {
  echo "Validation failed, disabling image"
  verify_result_configmap_exists
  write_result_configmap_value false
}

function get_api_key() {
  # cat "/etc/secret-volume/api_key"
  echo "YUdjMWNXMXVaWFE0TTNGb056aGtielJsWm04MmNXOTJOVGs2WkRjd01XUTBPVGN0TURBNE55MDBOak5rTFdFMFpETXRPR1ExWlRJek1XTTVZakZs"
}

function get_ngc_token() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile "https://authn.nvidia.com/token?service=ngc&" \
  -H "Authorization: ApiKey $1")

  if [ "${http_code}" == 200 ]; then
    token=$(jq -r '.token' $tempfile)
    echo $token
  fi
}

function get_nim_images() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile \
  https://api.ngc.nvidia.com/v2/search/catalog/resources/CONTAINER?q=%7B%22query%22%3A+%22orgName%3Anim%22%7D)

  if [ "${http_code}" == 200 ]; then
    nim_images=$(jq -r \
    '.results[] | select(.groupValue == "CONTAINER") | .resources[] | (.resourceId + ":" + (.attributes[] | select(.key == "latestTag") | .value))' \
    $tempfile)
    echo $nim_images
  fi
}

function get_nim_image_details() {
  IFS=':' read -r -a refs <<< "$1"
  if [ ${#refs[@]} -ne 2 ]; then
    return
  fi

  name="${refs[0]}"
  tag="${refs[1]}"

  IFS='/' read -r -a parts <<< "$name"
  if [ ${#parts[@]} -ne 3 ]; then
    return
  fi
  org="${parts[0]}"
  team="${parts[1]}"
  image="${parts[2]}"

  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile \
  https://api.ngc.nvidia.com/v2/org/$org/team/$team/repos/$image?resolve-labels=true \
  -H "Authorization: Bearer $2")

  if [ "${http_code}" == 200 ]; then
#     nim_images=$(jq -r \
#     '.results[] | select(.groupValue == "CONTAINER") | .resources[] | .resourceId' \
#     $tempfile)
    cat $tempfile
  fi
}

function get_image_data() {
  images=("$@")

  api_key=$(get_api_key)
  token=$(get_ngc_token $api_key)

  if [ ! -z "$token" ]; then
    for image in "${images[@]}";
      do get_nim_image_details $image $token;
    done
  fi
}

function get_image_registry_token() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile \
  "https://nvcr.io/proxy_auth?account=\$oauthtoken&offline_token=true&scope=repository:$1:pull" \
  -H "Authorization: Basic $2")

  if [ "${http_code}" == 200 ]; then
    token=$(jq -r '.token' $tempfile)
    echo $token
  fi
}

function get_image_manifest() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile \
  "https://nvcr.io/v2/$1/manifests/$2" \
  -H "Authorization: Bearer $3")

  if [ "${http_code}" == 200 ]; then
    cat $tempfile
  fi
}

function verify_api_key() {
  api_key=$(get_api_key)
  decoded_api_key=$(printf $api_key | base64 -d)
  basic=$(printf "\$oauthtoken:$decoded_api_key" | base64)
  #basic=$(printf "\$oauthtoken:$decoded_api_key" | base64 -w 0)

  token=$(get_image_registry_token $1 $basic)
  if [ ! -z "$token" ]; then
    manifest=$(get_image_manifest $1 $2 $token)
    if [ ! -z "$manifest" ]; then
      echo $manifest
    fi
  fi
}

echo "Install jq"
dnf install -y jq

echo "Get NIM images"
nim_images=$(get_nim_images)
if [ ! -z "$nim_images" ]; then
  images=($nim_images)

  IFS=':' read -r -a refs <<< "${images[0]}"
  if [ ${#refs[@]} -ne 2 ]; then
    echo "Failed to parse NIM image name"
    failure
  fi

  echo "Verify Api Key"
  verification=$(verify_api_key ${refs[0]} ${refs[1]})
  if [ ! -z "$verification" ]; then
    echo "Get images data"
    get_image_data "${images[@]}"
  else
    echo "Api key verification failed"
    failure
  fi
else
  echo "Failed to get NIM images"
  failure
fi

exit 0