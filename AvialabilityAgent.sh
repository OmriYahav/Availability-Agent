#!/bin/bash

TEST_PERIODICITY=5

# Function to perform ping check and return latency
ping_check() {
    result=$(ping "$1" -c 1 -W 2 2>/dev/null)  # Perform ping check
    [[ "$?" == "0" ]] && echo "$result" | grep -oP '(?<=time=)\d+(\.\d+)?' | awk '{print $1*1000}' || echo 0  # Return latency if ping successful, otherwise 0
}

# Function to execute ping check for a given address and store the result
execute_check() {
    [[ -n "$1" ]] && {  # Check if address is not empty
        result=$(ping_check "$1")  # Perform ping check
        echo "Ping result for host $1: Latency $result ms"  # Print host and latency
        curl -X POST "http://localhost:8086/write?db=hosts_metrics" -u "admin:12345678" \
             --data-binary "availability_test,host=$1 value=$result $(date +'%s%N')" 2>/dev/null || echo "Test result for $1 is $result at $(date +'%s%N')"  # Store result in the database or print to screen if storing fails
    }
}

hosts=$(cat ./hosts)

start_time=$(date +%s)  # Get the start time in seconds

while true; do
    current_time=$(date +%s)  # Get the current time in seconds
    elapsed_time=$((current_time - start_time))  # Calculate the elapsed time

    echo "Elapsed time: $elapsed_time seconds"  # Print the elapsed time

    for host in $hosts; do
        execute_check "$host"  # Execute ping check for each host
    done

    sleep "$TEST_PERIODICITY"  # Wait for the specified duration before the next round of checks
done
