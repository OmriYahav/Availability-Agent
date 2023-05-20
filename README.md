# Ping Monitoring with Grafana and InfluxDB

This repository contains a simple script written in Bash that performs periodic ping checks on a list of hosts and records the results in InfluxDB. The ping results can be visualized using Grafana.

## Prerequisites

Make sure you have Docker and Docker Compose installed on your system.

## Usage

1. Clone this repository to your local machine:

   ```bash
   git clone https://github.com/OmriYahav/AvialabilityAgent.git

2. Navigate to the project directory:

cd AvialabilityAgent

3. Modify the hosts file with the list of hosts you want to monitor. Each host should be on a separate line.

4. Start the Docker containers using Docker Compose:
    docker-compose up -d

5. Access Grafana in your web browser at http://localhost:3003. 
   Log in using the default credentials (admin/12345678).

6. Configure Grafana to connect to InfluxDB:

Go to "Configuration" > "Data Sources" in the Grafana sidebar.
Click on "Add data source" and select "InfluxDB".
Configure the data source with the following details:
Name: InfluxDB
URL: http://influxdb:8086
Database: hosts_metrics
User: admin
Password: 12345678
Click on "Save & Test" to verify the connection.

7. Import the Grafana dashboard:

Go to "Create" > "Import" in the Grafana sidebar.
Enter the dashboard ID 1234 (example) and click on "Load".
Customize the settings as needed (e.g., choose the appropriate data source).
Click on "Import" to import the dashboard.

8. The ping checks will run periodically based on the configured interval. The ping results will be stored in the InfluxDB database hosts_metrics and visualized in the Grafana dashboard.


## Customization
To change the ping interval, modify the TEST_PERIODICITY variable in the Bash script (monitor.sh).
Adjust the Grafana dashboard (dashboard.json) according to your preferences and monitoring requirements.

## License
This project is licensed under the MIT License.

Feel free to customize and enhance the setup according to your needs. Contributions are welcome!