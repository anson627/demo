#!/usr/bin/env python3

import argparse
import base64
import json
import subprocess
import ipaddress


def run_az(args, capture=True):
  print(args)
  cmd = ["az", *args]
  result = subprocess.run(cmd, capture_output=capture, text=True)
  if result.returncode != 0:
    raise RuntimeError(f"Command failed: {' '.join(cmd)}\n{result.stderr}")
  return result.stdout.strip() if capture else ""


def ip_config_exists(node_rg, nic_name):
  cmd = [
    "az", "network", "nic", "ip-config", "show",
    "--resource-group", node_rg,
    "--nic-name", nic_name,
    "--name", "ipvlan",
  ]
  return subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def ensure_ipvlan_ipconfig(node_rg, nic_name, prefix_length):
  if ip_config_exists(node_rg, nic_name):
    print(f"NIC {nic_name} already has an ipvlan IP config; skipping create.")
    return
  print(f"Creating ipvlan IP config for NIC {nic_name} in {node_rg}...")
  primary = run_az([
    "network", "nic", "show",
    "--resource-group", node_rg,
    "--name", nic_name,
    "--query", "ipConfigurations[0].name",
    "-o", "tsv",
  ])
  if not primary:
    print(f"Unable to determine primary IP config for NIC {nic_name}; skipping.")
    return
  print(f"Using primary IP config {primary} for NIC {nic_name}.")
  subnet_id = run_az([
    "network", "nic", "ip-config", "show",
    "--resource-group", node_rg,
    "--nic-name", nic_name,
    "--name", primary,
    "--query", "subnet.id",
    "-o", "tsv",
  ])
  if not subnet_id:
    print(f"Unable to determine subnet for NIC {nic_name}; skipping.")
    return
  run_az([
    "network", "nic", "ip-config", "create",
    "--resource-group", node_rg,
    "--nic-name", nic_name,
    "--name", "ipvlan",
    "--subnet", subnet_id,
    "--private-ip-address-version", "IPv4",
    "--private-ip-address-prefix-length", str(prefix_length),
  ])
  print(f"Created ipvlan IP config on {nic_name}.")


def push_cni_config(node_rg, nic_name, vm_name, ipvlan_prefix_length):
  if not vm_name or vm_name == "null":
    print(f"NIC {nic_name} not attached to a VM; skipping CNI config.")
    return
  print(f"Gathering ipvlan IP details for NIC {nic_name}...")
  ipvlan_ip = run_az([
    "network", "nic", "ip-config", "show",
    "--resource-group", node_rg,
    "--nic-name", nic_name,
    "--name", "ipvlan",
    "--query", "privateIPAddress",
    "-o", "tsv",
  ])
  if not ipvlan_ip:
    print(f"Unable to read ipvlan IP for NIC {nic_name}; skipping.")
    return
  ipvlan_cidr = ipvlan_ip if "/" in ipvlan_ip else f"{ipvlan_ip}/{ipvlan_prefix_length}"
  start, end = derive_range(ipvlan_cidr).split()
  print(f"Preparing ipvland config with subnet {ipvlan_cidr}, rangeStart {start}, rangeEnd {end}...")
  
  config = {
    "cniVersion": "0.3.1",
    "name": "ipvlan-eth0",
    "type": "ipvlan",
    "master": "eth0",
    "linkInContainer": False,
    "mode": "l3s",
    "ipam": {
      "type": "host-local",
      "ranges": [[{
        "subnet": ipvlan_cidr,
        "rangeStart": start,
        "rangeEnd": end,
      }]],
      "routes": [{"dst": "0.0.0.0/0"}],
    },
  }
  payload = base64.b64encode(json.dumps(config, indent=2).encode()).decode()
  print(f"Pushing ipvlan CNI config to VM {vm_name}...")
  run_az([
    "vm", "run-command", "invoke",
    "--resource-group", node_rg,
    "--name", vm_name,
    "--command-id", "RunShellScript",
    "--scripts",
    f"echo {payload} | base64 -d | tee /etc/cni/net.d/01-ipvlan-eth0.conf",
  ])

def parse_ipvlan_fields(raw):
  text = (raw or "").strip()
  if not text or text.lower() == "none":
    return "", ""
  if "\t" in text:
    ip, prefix = text.split("\t", 1)
  elif "/" in text:
    ip, prefix = text.split("/", 1)
  else:
    return "", ""
  return ip.strip(), prefix.strip()


def derive_range(ip_addr):
  network = ipaddress.IPv4Network(ip_addr, strict=False)
  if network.num_addresses <= 2:
    raise ValueError("Prefix too small for usable host range")
  start = network.network_address + 1
  end = network.broadcast_address - 1
  return f"{start} {end}"


def main():
  parser = argparse.ArgumentParser(description="Sync ipvlan configs for AKS nodes.")
  parser.add_argument("--resource-group", required=True)
  parser.add_argument("--cluster-name", required=True)
  parser.add_argument("--ipvlan-prefix-length", type=int, default=28)
  args = parser.parse_args()

  node_rg = run_az([
    "aks", "show",
    "-g", args.resource_group,
    "-n", args.cluster_name,
    "--query", "nodeResourceGroup",
    "-o", "tsv",
  ])
  if not node_rg:
    raise RuntimeError(f"Unable to determine node resource group for {args.cluster_name}")
  print(f"Operating on node resource group {node_rg}.")

  nics_raw = run_az([
    "network", "nic", "list",
    "--resource-group", node_rg,
    "--query", "[].{name:name,vm:virtualMachine.id}",
    "-o", "tsv",
  ])
  print("Scanning NICs for ipvlan synchronization...")
  for line in filter(None, nics_raw.splitlines()):
    parts = line.split("\t")
    nic_name = parts[0]
    print(f"Processing NIC {nic_name}")
    ensure_ipvlan_ipconfig(node_rg, nic_name, args.ipvlan_prefix_length)
    vm_id = parts[1] if len(parts) > 1 else ""
    vm_name = vm_id.split("/")[-1] if vm_id else ""
    if not vm_name:
      print(f"NIC {nic_name} is detached; skipping CNI config push.")
      continue
    print(f"Pushing config to VM {vm_name}")
    push_cni_config(node_rg, nic_name, vm_name, args.ipvlan_prefix_length)


if __name__ == "__main__":
  main()
