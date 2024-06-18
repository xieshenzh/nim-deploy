#!/bin/sh

CONFIGMAP_NAME='nvidia-nim-validation-result'

function get_variable() {
  cat "/etc/secret-volume/${1}"
}

function verify_configmap_exists() {
  if ! oc get configmap "${CONFIGMAP_NAME}" &>/dev/null; then
    echo "Result ConfigMap doesn't exist, creating"
    oc create configmap "${CONFIGMAP_NAME}" --from-literal validation_result="false"
  fi
}

function write_configmap_value() {
  oc patch configmap "${CONFIGMAP_NAME}" -p '"data": { "validation_result": "'${1}'" }'
}

function write_last_valid_time() {
  oc patch configmap "${CONFIGMAP_NAME}" -p '"data": { "last_valid_time": "'$(date -Is)'" }'
}

function success() {
  echo "Validation succeeded, enabling image"
  verify_configmap_exists
  write_configmap_value true
  write_last_valid_time
}

function failure() {
  echo "Validation failed, disabling image"
  verify_configmap_exists
  write_configmap_value false
}

function old() {
# CURL_RESULT=$(curl -w 'RESP_CODE:%{response_code}' -IHEAD "" 2>/dev/null)
# CURL_CODE=$(echo "${CURL_RESULT}" | grep -o 'RESP_CODE:[1-5][0-9][0-9]'| cut -d':' -f2)
# TODO
CURL_CODE = 403

echo "Validation result: ${CURL_CODE}"

if [ "${CURL_CODE}" == 200 ]; then
  success
elif [ "${CURL_CODE}" == 403 ]; then
  failure
else
  echo "Return code ${CURL_CODE} from validation check, possibly upstream error. Exiting."
  echo "Result from curl:"
  echo "${CURL_RESULT}"
fi
}

function get_api_key() {
  # cat "/etc/secret-volume/api_key"
  echo "YUdjMWNXMXVaWFE0TTNGb056aGtielJsWm04MmNXOTJOVGs2WkRjd01XUTBPVGN0TURBNE55MDBOak5rTFdFMFpETXRPR1ExWlRJek1XTTVZakZs"
}

function get_ngc_token() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile "https://authn.nvidia.com/token?service=ngc&" \
  -H "Content-Type: application/json" -H "Authorization: ApiKey $1")

  if [ "${http_code}" == 200 ]; then
    token=$(jq -r '.token' $tempfile)
    echo $token
  fi
}

function get_nim_images() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile \
  https://api.ngc.nvidia.com/v2/search/catalog/resources/CONTAINER?q=%7B%22query%22%3A+%22orgName%3Anim%22%7D \
  -H "Content-Type: application/json")

  if [ "${http_code}" == 200 ]; then
    nim_images=$(jq -r \
    '.results[] | select(.groupValue == "CONTAINER") | .resources | map( {(.resourceId): (.attributes[] | select(.key == "latestTag") | .value)}) | add' \
    $tempfile)
    echo $nim_images
  fi
}

function get_image_registry_token() {
  tempfile=$(mktemp)

  http_code=$(curl -s --write-out "%{http_code}" -o $tempfile "https://authn.nvidia.com/token?service=ngc&" \
  -H "Content-Type: application/json" -H "Authorization: ApiKey $1")

  if [ "${http_code}" == 200 ]; then
    token=$(jq -r '.token' $tempfile)
    echo $token
  fi
}

echo "Install jq"
# dnf install -y jq

api_key=$(get_api_key)

# token=$(get_ngc_token $api_key)
# if [ ! -z "$token" ]; then
#
# else
#   echo "Failed to get ngc token"
# fi

nim_images=$(get_nim_images)
if [ ! -z "$nim_images" ]; then
   echo $nim_images
else
   echo "Failed to get NIM images"
fi

exit 0