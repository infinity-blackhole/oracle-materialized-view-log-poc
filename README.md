# Oracle Materialized View Log PoC

This proof of concept (PoC) demonstrates the creation of a Change Data Capture
(CDC) Datastream pipeline using Oracle as the data source.

## Usage

To run this PoC, you can use the provided devcontainer in this repository.
Follow the steps below to configure Terraform:

1. Create a `{environment}.gcs.tfbackend` file with the following content:

```hcl
bucket = "shikanime-studio-labs-terraform-state"
prefix = "oracle-cdc"
```

**Note**: The environment is defaulted to Shikanime Studio Labs Google Cloud environment by default.

2. Run the following command to initialize Terraform:

```bash
terraform init -backend-config=default.gcs.tfbackend
```

To run the SQL commands, you need to open a proxy connection to the Oracle
database. You can use the following command to open a proxy connection:

```bash
gcloud compute ssh oracle-cdc-001 \
    --zone "europe-west1-b" \
    --project "shikanime-studio-labs" \
    --tunnel-through-iap \
    -- -L 1521:localhost:1521
```
