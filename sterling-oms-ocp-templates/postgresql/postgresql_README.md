# CloudFormation Template for RDS PostgreSQL Deployment

This CloudFormation template provisions a PostgreSQL RDS instance with optional public access and Multi-AZ configuration.

## Table of Contents
- [Prerequisites](#prerequisites)
- [How to Run the CloudFormation Template](#how-to-run-the-cloudformation-template)
- [Steps Using the AWS Console](#steps-using-the-aws-console)
- [Parameters](#parameters)

## Prerequisites

- An AWS account with permissions to create RDS instances, VPCs, subnets, and security groups.
- An existing VPC and subnets for the RDS instance.

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
     --parameters ParameterKey=VPCID,ParameterValue=<your-vpc-id> \
                  ParameterKey=SubnetIDs,ParameterValue='<subnet-1-id,subnet-2-id>' \
                  ParameterKey=RDSInstanceIdentifier,ParameterValue=<rds-instance-identifier> \
                  ParameterKey=RDSMasterUsername,ParameterValue=<master-username> \
                  ParameterKey=RDSMasterPassword,ParameterValue=<master-password> \
                  ParameterKey=EngineVersion,ParameterValue=16.2 \
                  ParameterKey=PubliclyAccessible,ParameterValue=false \
                  ParameterKey=MultiAZ,ParameterValue=false
   ```

3. **Monitor the Stack Creation**:
   You can check the status of your stack with:
   ```bash
   aws cloudformation describe-stacks --stack-name <your-stack-name>
   ```

4. **Retrieve the RDS Endpoint**:
   After the stack is created, retrieve the RDS endpoint for database connections.
   ```bash
   aws cloudformation describe-stacks --stack-name <your-stack-name> --query "Stacks[0].Outputs[?OutputKey=='RDSHost'].OutputValue" --output text
   ```

5. **Connect to the RDS Instance**:
   Use a PostgreSQL client to connect to the RDS instance.
   ```bash
   psql -h <rds-endpoint> -U <master-username> -d <your-database-name>
   ```
## Steps Using the AWS Console

1. **Open the AWS CloudFormation Console**:
   - Navigate to [AWS CloudFormation](https://console.aws.amazon.com/cloudformation/).

2. **Create a New Stack**:
   - Click on **Create stack** → **With new resources (standard)**.
   - Upload your CloudFormation template file or paste the template content directly.

3. **Specify Stack Details**:
   - Enter a **Stack name** (e.g., `postgres-rds-stack`).
   - Fill in the required **parameters** (e.g., VPC ID, Subnet IDs, RDS master credentials).

4. **Configure Stack Options**:
   - Optionally, set tags, permissions, and advanced settings.

5. **Review and Create**:
   - Review the provided configuration and click **Create stack**.

6. **Monitor the Stack Creation**:
   - Wait for the status to change to **CREATE_COMPLETE**.

7. **Retrieve the RDS Endpoint**:
   - Go to the **Outputs** tab in the CloudFormation console to find the RDS endpoint.

8. **Connect to the RDS Instance**:
   - Use the retrieved endpoint to connect to the RDS instance with a PostgreSQL client.
## Parameters

| Parameter Name         | Description                                                  | Sample Value                        |
|------------------------|--------------------------------------------------------------|-------------------------------------|
| VPCID                  | Select the VPC for the RDS instance.                        | `vpc-0a1b2c3d4e5f6g7h8`            |
| SubnetIDs              | Select the subnets in the chosen VPC for the RDS instance.  | `subnet-0a1b2c3d4e5f6g7h8,subnet-1b2c3d4` |
| RDSInstanceIdentifier  | Identifier for the RDS instance.                            | `my-postgres-db`                    |
| RDSMasterUsername      | Master username for the RDS instance.                       | `admin`                             |
| RDSMasterPassword      | Master password for the RDS instance.                       | `your-password`            |
| EngineVersion          | PostgreSQL engine version.                                  | `16.2`                              |
| AllocatedStorage       | Allocated storage size in GB for the RDS instance.          | `50`                                |
| PubliclyAccessible     | Specify whether the RDS instance should be publicly accessible. | `false`                        |
| MultiAZ                | Enable or disable Multi-AZ deployment.                      | `false`                             |

## License

