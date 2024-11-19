# CloudFormation Template for EC2 Instance with DB2 Installation and S3 Access

This CloudFormation template provisions an EC2 instance configured with IBM DB2 and access to S3 for the DB2 installation files.

## Table of Contents
- [Prerequisites](#prerequisites)
- [How to Run the CloudFormation Template](#how-to-run-the-cloudformation-template)
- [Steps Using the AWS Console](#steps-using-the-aws-console)
- [Parameters](#parameters)

## Prerequisites

- An AWS account with permissions to create EC2 instances, VPCs, security groups, IAM roles, and S3 buckets.
- An existing VPC and subnet in your AWS account.
- An EC2 key pair for SSH access.

## How to Run the CloudFormation Template

1. **Clone the Repository**:
   ```bash
   git clone <your-repository-url>
   cd <your-repository-name>
   ```

2. **Deploy the CloudFormation Template**:
   Use the AWS CLI to create a CloudFormation stack. Replace `<your-stack-name>` with your desired stack name and update the parameters accordingly.
   ```bash
   aws cloudformation create-stack --stack-name <your-stack-name> \
     --template-body file://<your-template-file.yaml> \
     --parameters ParameterKey=VpcId,ParameterValue=<your-vpc-id> \
                  ParameterKey=SubnetId,ParameterValue=<your-subnet-id> \
                  ParameterKey=KeyPair,ParameterValue=<your-key-pair-name> \
                  ParameterKey=SecurityGroupDescription,ParameterValue="Description of security group" \
                  ParameterKey=DbInstallerFile,ParameterValue="s3://your-bucket/DB2_Svr_11.5_Linux_x86-64.tar.gz" \
                  ParameterKey=DbResponseFile,ParameterValue="s3://your-bucket/db2server.rsp"
   ```

3. **Monitor the Stack Creation**:
   You can check the status of your stack with:
   ```bash
   aws cloudformation describe-stacks --stack-name <your-stack-name>
   ```

4. **Access the EC2 Instance**:
   Once the stack is created, retrieve the public IP from the stack outputs or describe the instance.
   ```bash
   aws cloudformation describe-stacks --stack-name <your-stack-name> --query "Stacks[0].Outputs[?OutputKey=='InstancePublicIP'].OutputValue" --output text
   ```

5. **SSH into the EC2 Instance**:
   Use the public IP to SSH into the instance.
   ```bash
   ssh -i <path-to-your-key-pair.pem> ec2-user@<public-ip>
   ```
## Steps Using the AWS Console

1. **Open the AWS CloudFormation Console**:
   - Navigate to [AWS CloudFormation](https://console.aws.amazon.com/cloudformation/).

2. **Create a New Stack**:
   - Click on **Create stack** → **With new resources (standard)**.
   - Upload your CloudFormation template file or paste the template content directly.

3. **Specify Stack Details**:
   - Enter a **Stack name** (e.g., `db2-ec2-stack`).
   - Provide the required **parameters** (e.g., VPC ID, subnet, key pair, and S3 URLs for DB2 installer and response files).

4. **Configure Stack Options**:
   - Optionally, set tags, permissions, and advanced settings.

5. **Review and Create**:
   - Review the provided configuration and click **Create stack**.

6. **Monitor the Stack Creation**:
   - Wait for the status to change to **CREATE_COMPLETE**.

7. **Retrieve the EC2 Public IP**:
   - Go to the **Outputs** tab in the CloudFormation console to find the public IP address of the instance.

8. **SSH into the EC2 Instance**:
   - Use the retrieved IP to SSH into the EC2 instance with your key pair:
     ```bash
     ssh -i <path-to-your-key-pair.pem> ubuntu@<public-ip>
     ```
   - You can check the logs inside the **/tmp/db2_deploy_logs** directory
     

## Parameters

| Parameter Name           | Description                                                     | Example Value                                                  |
|-------------------------|-----------------------------------------------------------------|--------------------------------------------------------------|
| VpcId                   | Select an existing VPC ID for the EC2 instance.               | `vpc-0a1b2c3d4e5f6g7h8`                                    |
| SubnetId                | Select an existing Subnet ID for the EC2 instance.            | `subnet-0a1b2c3d4e5f6g7h8`                                 |
| SecurityGroupName       | Name of the Security Group.                                    | `oms-db2-security-group`                                    |
| SecurityGroupDescription | Description of the security group.                             | `Security group for DB2 instance`                           |
| InstanceName            | Name of the EC2 instance.                                     | `oms_db2_instance`                                          |
| InstanceType            | EC2 instance type.                                            | `t3.medium`                                                 |
| EbsSize                 | Size of the EBS volume in GB.                                 | `100`                                                       |
| AmiId                   | AMI ID for the EC2 instance.                                  | `ami-00eb69d236edcfaf8`                                    |
| KeyPair                 | Name of the EC2 Key Pair for SSH access.                     | `my-key-pair`                                              |
| DbInstance              | DB2 instance name.                                            | `db2inst1`                                                 |
| DbUsername              | DB2 username.                                                | `db2inst1`                                                 |
| DbPassword              | DB2 password.                                                | `your-password`                 |
| DbPort                  | DB2 port.                                                    | `50000`                                                    |
| DbName                  | DB2 database name.                                           | `OMSDB`                                                    |
| DbSchema                | Default schema name.                                         | `OMS`                                                      |
| DbInstallerFile         | S3 URL for DB2 installer file.                               | `s3://oms-installer-bucket/DB2_Svr_11.5_Linux_x86-64.tar.gz` |
| DbResponseFile          | S3 URL for DB2 response file.                                | `s3://oms-installer-bucket/db2server.rsp`                  |

## License
TBD
