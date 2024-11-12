#!/bin/bash
echo "inside create-eks-cluster.sh"
# Function to check and install eksctl
check_and_install_eksctl() {
  # Check if eksctl is already installed
  if ! command -v eksctl &> /dev/null; then
    echo "eksctl is not installed. Installing..."
    # Download and extract eksctl binary
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp &> /dev/null
    if [ $? -ne 0 ]; then
      echo "Error downloading eksctl. Please check network connectivity."
      exit 1
    fi
    # Move eksctl binary to /usr/local/bin (requires root)
    sudo mv /tmp/eksctl /usr/local/bin &> /dev/null
    if [ $? -ne 0 ]; then
      echo "Error moving eksctl binary. Please check permissions and try with sudo."
      exit 1
    fi
    echo "eksctl successfully installed."
  else
    echo "eksctl is already installed."
  fi
}

# Function to wait for the EKS cluster to be active
wait_for_cluster() {
  local cluster_name="$1"
  local region="$2"

  echo "Waiting for the EKS cluster '$cluster_name' to be active..."

  while true; do
    status=$(aws eks describe-cluster --name "$cluster_name" --region "$region" --query 'cluster.status' --output text)
    if [ "$status" == "ACTIVE" ]; then
      echo "EKS cluster '$cluster_name' is now active."
      break
    else
      echo "Current status: $status. Waiting for 30 seconds before checking again..."
      sleep 30
    fi
  done
}

# Call the function to check and install eksctl
check_and_install_eksctl

# Define variables
InstanceName=$1  # Replace with your desired cluster name
Region=$2
ClusterSize=$3  # Cluster size: small, medium, or large

# Set the number of nodes and instance type based on cluster size
node_count=0
instance_type="m5.2xlarge"

case "$ClusterSize" in
  small)
    node_count=3
    ;;
  medium)
    node_count=5
    ;;
  large)
    node_count=7
    ;;
  *)
    echo "Invalid cluster size. Please specify 'small', 'medium', or 'large'."
    exit 1
    ;;
esac

# Create the EKS cluster with the specified node count and instance type
if command -v eksctl &> /dev/null; then
  eksctl create cluster --name "${InstanceName}" --region "${Region}" \
    --nodegroup-name "${InstanceName}-node-group" --nodes "$node_count" \
    --node-type "$instance_type" --tags project=sterling_marketplace --tags org-team=AWS_SP

  # Wait for the cluster to be active
  wait_for_cluster "${InstanceName}" "${Region}"
fi
echo $env
