# CSV --> Service Graph using Terrafrom

Based on original code shared by Tom Bryant from PagerDuty Professional Services.


This Terraform code allows you to quickly create Service Graphs based on a CSV input. Use the pre-made examples for various different industries or create your own using the blank template provided. A number of dependent recources are included (Users, Schedules, Escaalation Policies) to make this as quick and easy as possible, but you can specify your own existing Escalation Policies if you would prefer (see usage notes below for details).

You will need:

- PagerDuty:
  - Access to a domain: https://www.pagerduty.com/sign-up/
  - Access to a REST API Token from target domain: https://support.pagerduty.com/docs/generating-api-keys
- Terraform:
  - [CLI](https://learn.hashicorp.com/terraform/getting-started/install) - minimum version of v0.13 required


## Installation

1. Clone repo (via SSH) into appropriate location and enter directory.

    ```bash
    $ git clone git@github.com:pdt-jpickles/terraform-servicegraph.git
    ```

    ```bash
    $ cd terraform-servicegraph
    ```

2. Initialise Terraform Workspace

    ```bash
    $ terraform init
    ```

A successful output should look something like:

```
Initializing the backend...

Initializing provider plugins...
- Finding pagerduty/pagerduty versions matching "1.9.6"...
- Installing pagerduty/pagerduty v1.9.6...
- Installed pagerduty/pagerduty v1.9.6 (signed by a HashiCorp partner, key ID 027C6DD1F0707B45)

Partner and community providers are signed by their developers.
If you'd like to know more about provider signing, you can read about it here:
https://www.terraform.io/docs/cli/plugins/signing.html

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!
```

## Usage

Copy whichever of the pre-made examples you would like to use from the `./available_templates` folder into the `./include_in_build` folder. (Multiple templates can be used at the same time).

If you want to create your own use the `./available_templates/template.csv` and fill in the following information:

- ServiceName [required]:
  - The name of the service
- ServiceDescription [optional]:
  - The description of the service
- ServiceID [required]:
  - The id of the service (used to reference service dependencies). This must be unique within the csv file
- ServiceType [required]:
  - Either `business_service` for a Business Service or `service` for a Technical Service
- SupportingServices [optional]:
  - The ServiceID of any supporting services. Multiple IDs must be seperated by a semicolon with no spaces
- EscPol [optional]:
  - The id of an Escalation Policy to be used by that service. If left blank it will automatically be associated with the `Operations (EP)` Escalation Policy included with the build in `escalation_policies.tf`


Once a PagerDuty REST API token has been generated within the appropriate domain, the repo can be used to provision resources using Terraform.  
The token can be passed through the command line or as an environment variable; we _do not_ recommend checking this into the code.

We recommend including the optional argument `-parallelism=1` which will disable concurrent Terraform operations. 

```bash
$ terraform apply -parallelism=1 -var="PAGERDUTY_TOKEN=TOKEN_HERE" 
```

Terraform `apply` will formulate an appropriate plan depending on the order of resources to be provisioned/updated.
Alternatively you can ```terraform apply -auto-approve``` to avoid the prompt

```bash
$ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # pagerduty_business_service.main["0-1"] will be created
  + resource "pagerduty_business_service" "main" {
      + description = "Boutique Store Business Service"
      + html_url    = (known after apply)
      + id          = (known after apply)
      + name        = "Online Boutique"
      + self        = (known after apply)
      + summary     = (known after apply)
      + type        = "business_service"
    }

  # pagerduty_escalation_policy.it_management will be created
  + resource "pagerduty_escalation_policy" "it_management" {
      + description = "Managed by Terraform"
      + id          = (known after apply)
      + name        = "IT Management (EP)"

      + rule {
          + escalation_delay_in_minutes = 15
          + id                          = (known after apply)

          + target {
              + id   = (known after apply)
              + type = "schedule_reference"
            }
        }
    }

  (... omitted for brevity)

Plan: 38 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 
```

When you've reviewed the suggested changes, enter `yes` to provision/update the resources.

```bash
  Enter a value: yes

pagerduty_user.noah_cooper: Creating...
pagerduty_user.noah_cooper: Creation complete after 5s [id=POC8QGM]
pagerduty_user.paul_miller: Creating...
pagerduty_user.paul_miller: Creation complete after 4s [id=P82KQ4Z]

  (... omitted for brevity)

pagerduty_service_dependency.main["0-3/0-10"]: Creating...
pagerduty_service_dependency.main["0-3/0-10"]: Creation complete after 1s [id=D5ZXNQ5DM6SK5W5HY]
pagerduty_service_dependency.main["0-3/0-7"]: Creating...
pagerduty_service_dependency.main["0-3/0-7"]: Creation complete after 1s [id=D5ZXNQ5DM6SK5W5HX]

Apply complete! Resources: 38 added, 0 changed, 0 destroyed.
```

Once the resources have been provisioned, `terraform.tfstate` will keep the current state of the deployment on the local disk. If you wish to have this securely managed, kindly consider using a [remote backend provider](https://www.terraform.io/docs/backends/index.html).