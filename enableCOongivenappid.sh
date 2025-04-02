#!/bin/bash

# Function to print colored messages
echo_success() { echo -e "\e[32m$1\e[0m"; }
echo_error() { echo -e "\e[31m$1\e[0m"; }

# Prompt for credentials
read -p "Please enter your email: " email
read -s -p "Please enter your API key: " api_key; echo
read -p "Please enter your Server ID: " server_id

# Prompt for app IDs where cron optimizer failed
read -p "Enter failed App IDs separated by space: " -a failed_apps

# Get the access token
response=$(curl -s -X POST --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' -d "email=$email&api_key=$api_key" 'https://api.cloudways.com/api/v1/oauth/access_token')

# Extract access token
access_token=$(echo "$response" | jq -r '.access_token')
if [[ -z "$access_token" || "$access_token" == "null" ]]; then
    echo_error "Failed to retrieve access token. Check your email and API key."
    exit 1
fi
echo_success "Access token retrieved successfully."

# Process each failed app
for app_id in "${failed_apps[@]}"; do
    # Enable cron optimizer with retry mechanism
    for attempt in {1..3}; do
        enable_response=$(curl -s -X POST --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' --header "Authorization: Bearer $access_token" -d "server_id=$server_id&app_id=$app_id&status=enable" 'https://api.cloudways.com/api/v1/app/manage/cron_setting')
        
        if echo "$enable_response" | jq -e '.status' &>/dev/null; then
            echo_success "Cron optimizer enabled for app ID: $app_id"
            break
        else
            echo_error "Failed to enable cron optimizer for app ID: $app_id (Attempt $attempt). Retrying..."
            sleep 10
        fi
    done
    sleep 10  # Short delay to avoid API rate limits

done
echo_success "Process completed."

