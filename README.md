<h1 align="center">
  <img src="https://dashboard.snapcraft.io/site_media/appmedia/2022/03/K6-logo_1.jpg.png" alt="K6 Load Testing Tool Logo" width="35"/>
  K6 Load Testing Management Tool
</h1>

## Overview

The K6 Load Testing Management Tool is a bash script that simplifies the process of creating, managing, and monitoring load tests using the K6 performance testing tool. This script provides an interactive interface to streamline your load testing workflow.

## Features

- Create and configure K6 load testing scripts
- Manage K6 services through systemd
- List active K6 services
- Stop and remove existing K6 services
- Automatic installation of K6 if not present on the system

## Prerequisites

- Linux-based operating system with systemd
- Bash shell
- Root or sudo access

## Usage

```bash
bash <(curl -LS https://raw.githubusercontent.com/xmohammad1/k6/refs/heads/main/k6.sh)
```

Follow the on-screen prompts to:

1. Create a new K6 script and service
2. Remove an existing K6 service
3. List all K6 services
4. Exit the tool

## Creating a New K6 Test

When creating a new K6 test, you'll be prompted to enter:

- Number of Virtual Users (VUs)
- Test duration
- Target URL
- Service name

The script will create a K6 test script and a systemd service to manage the test.

## Managing Existing Tests

You can list all active K6 services and choose to stop and remove any of them.

## Contributions

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/xmohammad1/k6/issues).

## License

This project is [MIT](https://choosealicense.com/licenses/mit/) licensed.

## Acknowledgments

- [K6 Load Testing Tool](https://k6.io/)
