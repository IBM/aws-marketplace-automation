# IBM Sterling OMS Deployment on AWS

This repository contains AWS CloudFormation templates to deploy IBM Sterling Order Management System (OMS) on AWS. It provides flexibility for various infrastructure setups, allowing deployment on new or existing OpenShift clusters, and in new or existing VPCs. Additionally, the deployment supports two database options as prerequisites: DB2 on an EC2 instance or PostgreSQL on RDS.

## Getting Started

### Prerequisites

- An AWS account with permissions to create EC2 instances, IAM roles, security groups, RDS instances, and other AWS resources.
- An EC2 Key Pair for SSH access.
- IBM Entitled Registry Key for deploying IBM Sterling OMS.
- Knowledge of AWS, CloudFormation, EC2, and OpenShift.

### Deployment Options

This repository includes different deployment configurations based on your existing infrastructure setup:

1. **New OpenShift with New VPC**: Deploys a new OpenShift cluster in a new VPC.
2. **New OpenShift with Existing VPC**: Deploys a new OpenShift cluster in an existing VPC.
3. **Existing OpenShift**: Deploys IBM Sterling OMS on an already existing OpenShift cluster.

Each option has its own CloudFormation template in this repository to simplify deployment based on your requirements.

### Database Options

The following databases are supported as prerequisites for the IBM Sterling OMS deployment:

1. ![**DB2 on EC2**](db2/DB2_README.md): A CloudFormation template to deploy a DB2 database on an EC2 instance. This requires the DB2 installer to be available in an S3 bucket.
2. ![**PostgreSQL on RDS**](postgresql/postgresql_README.md): A CloudFormation template to deploy a managed PostgreSQL instance on Amazon RDS.

You can choose one of these database options based on your environment and preferences.

---

### Deployment Architecture

![Architecture Diagram](images/Deployment_Architecture.png)

*This architecture diagram demonstrates the interaction between EC2, OpenShift, RDS/DB2, and other AWS resources necessary for deploying IBM Sterling OMS.*

---

## CloudFormation Template Execution

Follow the steps below to deploy IBM Sterling OMS using a CloudFormation template:

### Step 1: Choose and Download the Template

Select the appropriate CloudFormation template from this repository based on your deployment scenario (New OpenShift with New/Existing VPC, or Existing OpenShift). Download the chosen template to your local machine, or upload it to an S3 bucket.

### Step 2: Launch the CloudFormation Stack

1. **Navigate to the AWS Management Console**:
   - Open the [CloudFormation Console](https://console.aws.amazon.com/cloudformation).

2. **Create a New Stack**:
   - Click on "Create Stack" and select "With new resources (standard)".
   - Upload the CloudFormation template file, or provide the S3 URL if the template is in an S3 bucket.

3. **Enter Required Parameters**:

4. **Review and Create the Stack**:
   - Review the parameters, acknowledge the IAM resource creation, and click "Create Stack".

5. **Monitor Stack Creation**:
   - Monitor the stack creation in the "Events" tab of the CloudFormation console. Once the stack completes, resources like EC2 instances, RDS or DB2 instances, security groups, and IAM roles will be created.

### Resources Created

Depending on the chosen configuration, the following resources will be created:

- **EC2 Instance**: Hosts the Sterling OMS setup and optionally the DB2 database.
- **Security Groups**: For access control to EC2 instances and OpenShift/EKS clusters.
- **IAM Roles**: Provides permissions for EC2, OpenShift/EKS, S3, and other AWS services.
- **OpenShift**: Provisions an OpenShift if not already available.
- **Database (DB2/PostgreSQL)**: Deploys either a DB2 database on an EC2 instance or a PostgreSQL RDS instance.


### Post-Deployment Steps

1. **Connect to the EC2 Instance**:
   - SSH into the EC2 instance using the Key Pair and the EC2 instance's public IP.

2. **Deployment Logs**:
   - Deployment logs are stored on the EC2 instance in `/oms-deploy-aws/logs/`.

3. **Database Preparation**:
   - For DB2, ensure the installer is available in S3, and configure access to download it on the EC2 instance.
   - For PostgreSQL, RDS setup will be handled by the CloudFormation template.

---

## Technical Stack

- **Compute**: EC2 instances for Sterling OMS and optional DB2 database.
- **Kubernetes Management**: OpenShift for orchestrating Sterling OMS services.
- **Database**: DB2 on EC2 or PostgreSQL on Amazon RDS.


---
### CloudFormation Template Parameters

This template deploys a self-managed OpenShift cluster on AWS. Below are descriptions of each parameter to assist you in filling out the necessary details.

#### 1. **VPC Configuration**
- **VpcCidr**: The CIDR block for the VPC (e.g., `10.0.0.0/16`). Valid range: `/16` to `/24`.
- **SubnetBits**: The number of subnet bits, with a range of `/19` to `/27`. Defines subnet size within each availability zone.
- **AvailabilityZoneCount**: Number of Availability Zones to use for subnet creation. Allowed values are `1` to `3`.

#### 2. **Cluster Configuration**
- **ClusterName**: Custom name for the OpenShift cluster (alphanumeric, lowercase, and hyphens only).
- **DomainName**: The Route 53 domain name configured for the OpenShift cluster (e.g., `example.com`).
- **PrivateCluster**: Set to `True` for a private cluster or `False` for a public one.
- **RedhatPullSecret**: URL to the Red Hat pull secret (e.g., `s3://mybucket/path/pullsecret.json`).
- **OpenshiftVersion**: Version of OpenShift to install (e.g., `4.14.0`).
- **EnableFips**: Set to `true` to enable FIPS (Federal Information Processing Standards) compliance, otherwise `false`.

#### 3. **Control Plane Configuration**
- **MasterInstanceType**: EC2 instance type for the control plane (e.g., `m6i.xlarge`). 
- **MasterVolumeIOPS**: IOPS for the control plane volume. Ensure the instance type supports the specified IOPS.
- **MasterVolumeSize**: Size of the master volume in GiB (default is `200`).
- **MasterVolumeType**: Storage type for the master volume (`gp3`, `gp2`, `io1`, `io2`).

#### 4. **Worker Configuration**
- **WorkerInstanceType**: EC2 instance type for worker nodes (e.g., `m6i.2xlarge`).
- **WorkerVolumeIOPS**: IOPS for worker volume. Compatible with the chosen volume type.
- **WorkerVolumeSize**: Size of the worker volume in GiB (default is `200`).
- **WorkerVolumeType**: Storage type for worker volumes (`gp3`, `gp2`, `io1`, `io2`).
- **WorkerCount**: Number of worker nodes (minimum of `3` required for highly available clusters).

#### 5. **Storage Configuration**
- **OcsInstanceType**: EC2 instance type for OpenShift Container Storage (OCS).
- **OcsIOPS**: IOPS for the OCS volume. Compatible with the instance type.
- **OcsVolumeSize**: Size of the OCS volume in GiB.
- **OcsVolumeType**: Storage type for OCS volumes (`gp3`, `gp2`, `io1`, `io2`).

#### 6. **Availability Zones**
- **NumberOfAZs**: Number of Availability Zones (AZs) for deployment. Choose `1` or `3` for redundancy.
- **AvailabilityZones**: List of AZs to use (e.g., `us-east-2a,us-east-2b,us-east-2c`).

#### 7. **Cluster Networking**
- **ClusterNetworkCIDR**: CIDR range for the cluster network (e.g., `10.128.0.0/14`).
- **ClusterNetworkHostPrefix**: Host prefix for the cluster network.
- **MachineNetworkCIDR**: CIDR block of the VPC used by the cluster (must match subnet CIDR range).
- **ServiceNetworkCIDR**: CIDR range for services within the OpenShift cluster (e.g., `172.30.0.0/16`).

#### 8. **Instance Configuration**
- **KeyPairName**: Name of an existing EC2 key pair to connect to instances after deployment.
- **BootNodeAccessCIDR**: IP range allowed to access the boot node (e.g., `0.0.0.0/0` for open access).

#### 9. **OMS Configuration**
- **EntitlementKey**: Your IBM OMS entitlement key.
- **License**: Accept the license by setting this to `Agree`.

#### 10. **Database Configuration**
- **DatabaseType**: Type of the database (`DB2` or `PostgreSQL`).
- **DatabaseHostName**: Hostname or IP of the database server.
- **DatabasePort**: Port for the database (default is `5432` for PostgreSQL).
- **DatabaseUserName**: Username for database access.
- **DatabasePassword**: Password for the database (hidden for security).
- **DatabaseSchema**: Schema name in the database.
- **DatabaseName**: Name of the database to be used by OpenShift.

## License Agreement

By using these CloudFormation templates, you agree to the IBM Sterling OMS license terms and conditions.

