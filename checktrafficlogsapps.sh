#!/bin/bash

# Prompt user for number of hours
read -p "Enter number of hours to check traffic (default 1): " hours
HOURS="${hours:-1}"

# Download and run the modified script inline with the user's input
bash <(wget -qO- https://raw.githubusercontent.com/delson93/cwmysqlbackup/main/checktraffic_all_apps.sh | sed "s/-l 1h/-l ${HOURS}h/")

