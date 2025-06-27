# Local mmproxy Setup for Preserving Client IP

This project provides a modular and robust set of scripts and configurations to set up `mmproxy`.

The core concept is a separation of concerns:
1.  **Network Pathways**: These are the dataflow routes for proxied traffic, defined by a firewall mark (`fwmark`). You create one pathway for each source proxy (e.g., one for `vps01`, one for `router01`). The underlying `ip` and `iptables` rules are managed by the `setup-pathway.sh` script.
2.  **Service Instances**: These are the individual `mmproxy` processes that listen for traffic and forward it to a local TCP service (like SSH or a web server). Each instance is assigned to use one of the pre-defined network pathways.

## Architecture

The setup involves three main components:

1.  **Workload Server (`wks01`)**: The server running the actual service (e.g., SSHD on port 22). This server also runs `mmproxy` to handle incoming PROXY protocol connections. It uses policy-based routing (`iptables` and `iproute2`) to correctly handle traffic from spoofed client IPs.

2.  **Proxy Server (`vps01`)**: A server with a public IP (e.g., a VPS) that runs `HAProxy`. It accepts public traffic and forwards it to `wks01` over a private network (like Tailscale), adding a PROXY protocol header that contains the original client's IP.

3.  **Second Proxy (`router01`)**: An optional second proxy, which could be an OpenWrt router or another server. This demonstrates how to handle multiple ingress points.

The connection flow is as follows:
`Client` -> `Proxy (vps01/router01)` -> `wks01 (mmproxy instance)` -> `wks01 (Local TCP Service)`

The `mmproxy` instance uses a specific **network pathway** based on its configuration.

## Prerequisites

- **`wks01`**:
    - A Linux server.
    - `go` (version 1.20+ recommended) to build `go-mmproxy`.
    - `iptables` and `iproute2`.
    - A private network connection to the proxies (e.g., Tailscale).
- **`vps01`/`router01`**:
    - `haproxy` installed.

## Setup Instructions

### 1. Configure Your Proxies (`vps01`, `router01`)

On each proxy server, configure `HAProxy` to forward traffic to the appropriate `mmproxy` listener on `wks01`. For example, if you are setting up `vps01-ssh`, the `haproxy.cfg` on `vps01` should forward traffic to the port defined in `LISTEN_ADDRS[vps01-ssh]` in your `mmproxy.conf`.

### 2. Configure the Workload Server (`wks01`)

#### a. Install `go-mmproxy`

If you haven't installed `go` and `go-mmproxy` yet, you can follow the commands from the original notes:

```bash
# Install Go (adjust version if needed)
curl -LO https://mirrors.aliyun.com/golang/go1.22.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.4.linux-amd64.tar.gz
# ... configure go path ...
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
export GOPATH=$HOME/go

# Install go-mmproxy
GOPROXY=https://goproxy.cn,direct go install github.com/path-network/go-mmproxy@latest
```

#### b. Create the `mmproxy` Configuration
The setup uses two configuration files to define all services:
1.  `config/pathways.conf`: Defines the network pathways (the `fwmark` values) that can be used.
2.  `config/instances.tsv`: Defines each service instance and maps it to a pathway and a target service.

**Step 1: Define Network Pathways**
-   Copy the example file: `cp config/pathways.conf.example config/pathways.conf`
-   In `config/pathways.conf`, list all the unique `fwmark` numbers you will need. Typically, this is one per proxy server.

**Step 2: Define Service Instances**
-   Copy the example map file: `cp config/instances.tsv.example config/instances.tsv`
-   In `config/instances.tsv`, define all your `mmproxy` services, one per line. The format is a tab-separated list:
    `<instance_name> <fwmark> <listen_addr> <target_ipv4> <target_port> <target_ipv6>`

Example of adding a new `vps01-web` service that uses the same pathway as `vps01-ssh` (`fwmark 123`):

1.  Ensure `123` is in `config/pathways.conf`.
2.  Add a line to `config/instances.tsv`:
    ```tsv
    vps01-web	123	100.101.102.123:8443	127.0.0.1	443	::1
    ```

#### c. Configure Paths and Allowed Proxies
The `start-mmproxy.sh` script needs to know the location of the `go-mmproxy` binary and the `allow.txt` file.

-   **Binary and Allow List Paths**: The script uses the `MMPROXY_BIN` and `ALLOW_LIST_PATH` environment variables. If these are not set, it falls back to default hardcoded paths (e.g., `/opt/mmproxy/bin/go-mmproxy` and `/opt/mmproxy/config/allow.txt`). For a local setup, it's recommended to set these variables:
    ```bash
    export MMPROXY_BIN="$PWD/bin/go-mmproxy"
    export ALLOW_LIST_PATH="$PWD/config/allow.txt"
    ```

-   **Allowed IPs**: Create the `allow.txt` file (e.g., `cp config/allow.txt.example config/allow.txt`) and add the private IPs of your proxy servers, one per line.

#### d. Setup Policy Routing
The network pathways are managed by the `scripts/setup-pathway.sh` script.

All network scripts are **idempotent**: they can be run multiple times without causing errors or changing the result beyond the initial setup.

- **For immediate, one-time setup**: You can manually add or remove rules for a specific pathway. This can be done by providing either the raw `fwmark` number or the more convenient instance name.
  ```bash
  # Add rules for the pathway used by 'vps01-ssh'
  sudo bash scripts/setup-pathway.sh add vps01-ssh
  
  # This is equivalent to looking up the fwmark and running:
  sudo bash scripts/setup-pathway.sh add 123
  
  # Remove rules for the pathway identified by fwmark 123
  sudo bash scripts/setup-pathway.sh del 123
  ```
- **For persistent setup (recommended)**: The `systemd/mmproxy-pathways.service` will handle this automatically.

### 3. Run `mmproxy`

You can run `mmproxy` directly via the start script for testing or install the provided `systemd` services for production use.

#### a. As a Shell Script (for testing)

The `start-mmproxy.sh` script is designed to be called with a single argument: the name of the instance you want to run. It reads all the necessary configuration from `config/instances.tsv`.

There is no longer a central `mmproxy.conf` file to manage.

To run an instance:
1.  Ensure the instance (e.g., `vps01-ssh`) is defined in `config/instances.tsv`.
2.  Ensure the paths to the binary and allow list are correctly set (see step 2c above).
3.  Run the script with the instance name:
    ```bash
    # For the 'vps01-ssh' instance
    bash scripts/start-mmproxy.sh vps01-ssh

    # For the 'router01-ssh' instance
    bash scripts/start-mmproxy.sh router01-ssh
    ```
The script is idempotent and will not start a duplicate process if an instance is already running.

#### b. As `systemd` Services (for production)

This is the recommended way to run `mmproxy`. The `systemd` template `mmproxy@.service` allows you to manage each configured instance.

1.  **Customize Service Files**: Edit `systemd/mmproxy-pathways.service` and `systemd/mmproxy@.service` and change the `WorkingDirectory` and `ExecStart` paths to match your project's location (e.g., `/opt/mmproxy-setup`).

2.  **Install the services**:
    ```bash
    sudo cp systemd/mmproxy-pathways.service /etc/systemd/system/
    sudo cp systemd/mmproxy@.service /etc/systemd/system/
    sudo systemctl daemon-reload
    ```

3.  **Enable and Start**:
    - First, enable the pathways service. It will apply rules for all pathways in `pathways.conf` at boot and remove them at shutdown.
      ```bash
      sudo systemctl enable --now mmproxy-pathways.service
      ```
    - Next, enable and start a service for each instance you defined in `instances.tsv`.
      ```bash
      # For the 'vps01-ssh' instance
      sudo systemctl enable --now mmproxy@vps01-ssh.service
      
      # For the 'router01-ssh' instance
      sudo systemctl enable --now mmproxy@router01-ssh.service

      # If you added a web service instance:
      # sudo systemctl enable --now mmproxy@vps01-web.service
      ```

4.  **Check Status**:
    ```bash
    # Check the pathways service
    systemctl status mmproxy-pathways.service

    # Check your mmproxy instances
    systemctl status mmproxy@*.service
    ```

## How It Works

The magic lies in Linux's policy-based routing.

1.  `mmproxy` receives a connection with a PROXY header.
2.  It creates a *new* connection to the local SSH server, spoofing the source IP to be the one from the PROXY header. It also sets a unique `fwmark` (firewall mark) on these packets.
3.  An `ip rule` (`ip rule add fwmark <mark> lookup <table>`) directs the kernel to use a special routing table for any packet with this mark.
4.  This special routing table has a single rule (`ip route add local 0.0.0.0/0 dev lo table <table>`) which tells the kernel "any destination is valid for local delivery". This tricks the kernel into accepting the packet with a "foreign" source IP as a local packet.
5.  `CONNMARK` rules in `iptables` ensure that reply packets from the SSH server are also marked, so they follow the same path back.

This setup allows the final service (SSHD) to see the true client IP, which is essential for logging, access control, and security. 