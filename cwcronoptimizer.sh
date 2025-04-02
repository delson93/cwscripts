#!/bin/bash

# Function to print colored messages
echo_success() { echo -e "\e[32m$1\e[0m"; }
echo_error() { echo -e "\e[31m$1\e[0m"; }

# Prompt for credentials
read -p "Please enter your email: " email
read -s -p "Please enter your API key: " api_key; echo
read -p "Please enter your Server ID: " server_id

# Get the access token
response=$(curl -s -X POST --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' -d "email=$email&api_key=$api_key" 'https://api.cloudways.com/api/v1/oauth/access_token')

# Extract access token
access_token=$(echo "$response" | jq -r '.access_token')
if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    echo_error "Failed to retrieve access token. Check your email and API key."
    exit 1
fi
echo_success "Access token retrieved successfully."

# Fetch server details
api_response=$(curl -s -X GET --header 'Accept: application/json' --header "Authorization: Bearer $access_token" 'https://api.cloudways.com/api/v1/server')
servers=$(echo "$api_response" | jq -r ".servers[] | select(.id == \"$server_id\")")

if [[ -z "$servers" ]]; then
    echo_error "No server found with ID: $server_id"
    exit 1
fi
echo_success "Server found: ID $server_id"

# List to store failed attempts
failed_apps=()

# Process each WordPress-related app
for app in $(echo "$servers" | jq -r '.apps[] | select(.application == "wordpress" or .application == "woocommerce" or .application == "wordpressmu") | .id'); do
    
    # Check cron optimizer status
    cron_status_response=$(curl -s -X GET --header 'Accept: application/json' --header "Authorization: Bearer $access_token" "https://api.cloudways.com/api/v1/app/manage/cron_setting?server_id=$server_id&app_id=$app")
    cron_status=$(echo "$cron_status_response" | jq -r '.status' 2>/dev/null)

    if [[ "$cron_status" == "enable" ]]; then
        echo_success "Cron optimizer is already enabled for app ID: $app, skipping..."
        continue
    fi

    # Enable cron optimizer with retry mechanism
    success=false
    for attempt in {1..3}; do
        enable_response=$(curl -s -X POST --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' --header "Authorization: Bearer $access_token" -d "server_id=$server_id&app_id=$app&status=enable" 'https://api.cloudways.com/api/v1/app/manage/cron_setting')
        if echo "$enable_response" | jq -e '.status' &>/dev/null; then
            echo_success "Cron optimizer enabled for app ID: $app"
            success=true
            break
        else
            echo_error "Failed to enable cron optimizer for app ID: $app (Attempt $attempt). Retrying..."
            sleep 10
        fi
    done
    
    if [[ "$success" == false ]]; then
        failed_apps+=("$app")
    fi
    sleep 60

done

# Display failed apps at the end
if [[ ${#failed_apps[@]} -ne 0 ]]; then
    echo_error "\nFailed to enable cron optimizer for the following app IDs:"
    printf '%s\n' "${failed_apps[@]}"
else
    echo_success "\nCron optimizer enabled successfully for all apps."
fi

