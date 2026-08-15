# DevOps Final Project — End-to-End Deployment Pipeline

*Author:* Maryam Adepoju
*Repo:* `Devops-final-project-bloomy`
*Live Apps:*
- Portfolio site: http://34.204.39.50:5000
- Java (Vaadin) app: http://34.204.39.50:8080/sampleapp

## What This Project Does (in plain words)

Imagine you built two websites on your laptop. Right now, only you can see them — they live and die with your computer. This project takes those two websites and:

1. Puts each one in its own *box* (Docker container) so they run the same way anywhere
2. *Builds a house for them in the cloud* (AWS servers, built automatically with Terraform)
3. *Furnishes the house* — installs everything the apps need to run (Ansible)
4. *Builds a robot* that does steps 1–3 automatically every time you push new code (Jenkins)

By the end, pushing code to GitHub is the only thing you ever have to do — a robot handles building, testing, provisioning, and deploying, and the apps show up live on the internet without you touching a server by hand.

---

## The Two Applications

| App | Built with | Runs on port |
|---|---|---|
| Portfolio website | Python Flask | 5000 |
| Sample Java app (Vaadin address book) | Java + Maven, served by Tomcat | 8080 |

---

## Architecture — How the Pieces Fit Together

```
GitHub (code) 
   ↓ triggers
Jenkins (the robot)
   ↓ runs, in order
1. Pull code  →  2. Build Java app (Maven)  →  3. Build Docker images
   ↓
4. Terraform (builds/checks AWS infrastructure)
   ↓
5. Ansible (installs Docker on the server, copies app files, starts containers)
   ↓
6. Verify (checks both apps respond)
```

---

## Phase 1: Dockerizing Both Apps

*Why:* Docker puts an app and everything it needs (Python, libraries, etc.) into one sealed box. That box runs identically on my laptop, on a teammate's laptop, or on a cloud server — no more "it works on my machine" problems.

### Portfolio App (Flask)

`portfolio-app/Dockerfile`:
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
```
- `FROM python:3.11-slim` — start from a small Linux box that already has Python installed
- `WORKDIR /app` — everything happens inside a folder called `/app`
- `COPY requirements.txt .` then `pip install` — install Flask before copying the rest of the code (this lets Docker reuse this step if only the code changes later, which speeds up rebuilds)
- `EXPOSE 5000` — this container listens on port 5000
- `CMD` — the command that runs when the container starts

### Java App (Vaadin, via Tomcat)

`java-app/Dockerfile`:
```dockerfile
FROM tomcat:8.5.40
COPY target/sampleapp.war /usr/local/tomcat/webapps
EXPOSE 8080
CMD /usr/local/tomcat/bin/catalina.sh run
```
- Java web apps are traditionally packaged as a single `.war` file and dropped into a Java web server (Tomcat) to run — this Dockerfile just takes an already-built `.war` file and hands it to Tomcat.

### Running Both Together — Docker Compose

`docker-compose.yml`:
```yaml
services:
  portfolio-app:
    build: ./portfolio-app
    ports:
      - "5000:5000"
    container_name: portfolio-app

  java-app:
    build: ./java-app
    ports:
      - "8080:8080"
    container_name: java-app
```
*Why:* instead of typing two separate `docker build` and `docker run` commands, this one file says "build and run both of these together" with a single command: `docker compose up -d`.

---

## Phase 2: Terraform — Building the Cloud Infrastructure

*Why:* Instead of clicking around the AWS website to create a server (which is slow, error-prone, and impossible to repeat exactly), Terraform lets me *describe* the infrastructure I want in code. Run it once, and it builds everything. Run it again, and it only fixes what's different — it never blindly recreates things that already exist.

### `provider.tf` — tells Terraform which cloud and region to use
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "devops-final-tfstate-marade19"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}
```
The `backend "s3"` block stores Terraform's memory (the "state file," which tracks what it has already built) in an S3 bucket instead of on my own laptop. **Why this matters:** both my laptop and Jenkins need to look at the *same* memory of what's built, or they'll fight each other and create duplicate infrastructure (which happened to me during testing — see Lessons Learned below).

### `vpc.tf` — the network the server lives in
Creates a private section of AWS (VPC), a subnet inside it, an internet gateway (the "door" to the internet), and a route table telling traffic how to get out.

### `security_group.tf` — the bouncer
```hcl
resource "aws_security_group" "app_sg" {
  ...
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Portfolio app"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Java app"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```
Only three doors are open on the server: SSH (22, so I can log in), and the two app ports (5000, 8080, so browsers can reach them). Everything else is closed by default.

### `ec2.tf` — the actual server, plus a permanent address
```hcl
resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = aws_key_pair.deployer.key_name
}

resource "aws_eip" "app_server_eip" {
  instance = aws_instance.app_server.id
  domain   = "vpc"
}
```
- `t3.micro` is a small, free-tier-eligible virtual machine — cheap and enough for this project
- The *Elastic IP* (`aws_eip`) gives the server a permanent public address. Without it, AWS assigns a *new* IP address every time the server restarts, which would break every script that points at the old one.

### `outputs.tf` — print the important info after building
```hcl
output "server_public_ip" {
  value = aws_eip.app_server_eip.public_ip
}
```
So I don't have to go hunting through the AWS console for the address every time.

*Commands used:*
```bash
terraform init      # downloads the AWS plugin
terraform plan       # previews what will be built, without building it
terraform apply       # actually builds it
```

---

## Phase 3: Ansible — Configuring the Server and Deploying the Apps

*Why:* Terraform builds the *empty* server. Ansible is the one that walks in, installs Docker, copies the app code over, and starts everything running — the "furnishing the house" step.

### `inventory.ini` — tells Ansible which server to talk to
```ini
[web]
34.204.39.50 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/devops-key ansible_python_interpreter=/usr/bin/python3 ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```
`StrictHostKeyChecking=no` skips the "do you trust this server?" prompt that SSH normally asks the first time — necessary because Jenkins runs unattended and has no human to answer "yes."

### `playbook.yml` — the list of jobs Ansible performs, in order
1. *Update package list* — refresh Ubuntu's list of available software
2. *Install Docker* — add Docker's official signing key and download source, then install Docker itself
3. *Add `ubuntu` user to the `docker` group* — so Docker commands don't need `sudo` every time
4. *Create an app folder* on the server
5. *Sync the app folders over* (using `rsync`, which only copies what's changed — much faster than a full copy every time):
```yaml
- name: Sync portfolio-app folder to server
  synchronize:
    src: ../portfolio-app/
    dest: /home/ubuntu/app/portfolio-app/
    rsync_opts:
      - "--exclude=__pycache__"

- name: Sync java-app folder to server
  synchronize:
    src: ../java-app/
    dest: /home/ubuntu/app/java-app/
    rsync_opts:
      - "--exclude=.git"
```
6. **Copy `docker-compose.yml`** over
7. **Run `docker compose up -d --build`** — builds fresh images from the copied code and starts both containers in the background

**Command used:**
```bash
ansible-playbook -i inventory.ini playbook.yml
```

---

## Phase 4: Jenkins — Automating Everything

**Why:** Phases 1–3 above were all done *by hand* first, to prove each piece worked on its own. Jenkins' job is to become "me" — every time code changes, it runs those exact same steps automatically, in order, without me typing a single command.

### `Jenkinsfile` — the pipeline definition
```groovy
pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/marade19/Devops-final-project-bloomy.git'
            }
        }

        stage('Build Java App') {
            steps {
                dir('java-app') {
                    sh 'mvn clean package'
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh 'docker compose build'
            }
        }

        stage('Provision Infrastructure') {
            steps {
                dir('terraform') {
                    sh 'terraform init'
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        stage('Configure & Deploy') {
            steps {
                sshagent(credentials: ['ec2-ssh-key']) {
                    dir('ansible') {
                        sh 'ansible-playbook -i inventory.ini playbook.yml'
                    }
                }
            }
        }

        stage('Verify') {
            steps {
                script {
                    def ip = sh(script: "cd terraform && terraform output -raw server_public_ip", returnStdout: true).trim()
                    sh "curl -sf http://${ip}:5000 || echo 'Portfolio app check failed'"
                    sh "curl -sf http://${ip}:8080/sampleapp || echo 'Java app check failed'"
                }
            }
        }
    }
}
```

**What each stage does:**
| Stage | Job | Plain-language purpose |
|---|---|---|
| Checkout | Pulls the latest code from GitHub | "Get the newest version of everything" |
| Build Java App | Runs Maven to compile Java code into a `.war` file | "Turn Java source code into something runnable" |
| Build Docker Images | Builds both container images | "Package both apps into their boxes" |
| Provision Infrastructure | Runs Terraform | "Make sure the cloud server exists and is set up right" |
| Configure & Deploy | Runs Ansible | "Install Docker on the server and start both apps" |
| Verify | Curls both app URLs | "Double-check both apps actually respond" |

### Credentials set up in Jenkins (Manage Jenkins → Credentials → System → Global)
| ID | Type | Purpose |
|---|---|---|
| `aws-access-key-id` | Secret text | Lets Terraform talk to AWS |
| `aws-secret-access-key` | Secret text | Lets Terraform talk to AWS |
| `ec2-ssh-key` | SSH Username with private key | Lets Ansible log into the EC2 server |
| `github-creds` | Username with password (token) | Lets Jenkins pull the private repo |

---

## Lessons Learned / Real Problems I Fixed

Documenting these because fixing them was most of the actual learning:

1. **`java-app` had its own hidden `.git` folder** from cloning it, which made my main repo track it as a broken reference instead of real files. Fixed by removing the nested `.git` and re-adding the files properly.
2. **Compiled build output (`target/`) was almost committed to Git.** Added it to `.gitignore` — build artifacts should always be generated fresh, not stored in source control.
3. **Jenkins runs in its own isolated Docker container** — it doesn't share tools with my WSL terminal. Had to manually install Maven, Ansible, Terraform, `rsync`, and the Docker Compose plugin *inside* the Jenkins container.
4. **Terraform state duplication:** running `terraform apply` from Jenkins (with no shared memory of what was already built) created a second, duplicate set of AWS resources. Fixed by moving the state file to a shared S3 bucket (the "backend"), so both my laptop and Jenkins read/write the same source of truth.
5. **EC2's public IP changes every restart** by default, breaking my inventory file each time. Fixed by attaching an Elastic IP — a permanent address that doesn't change.
6. **SSH host key verification failed inside Jenkins**, because Jenkins had never connected to the server before and had no human available to type "yes" to the trust prompt. Fixed with `StrictHostKeyChecking=no` in the Ansible inventory.
7. **`rsync` wasn't installed inside the Jenkins container**, so the file-sync tasks in the Ansible playbook failed. Installed it manually inside the container.

---

## Cost-Saving Decisions

- Used `t3.micro` (free-tier eligible instance type)
- No NAT Gateway or Load Balancer — both apps run on one EC2 instance, and the load balancer was optional per the assignment
- Set up a zero-spend AWS Billing budget alert to catch unexpected charges early
- **Reminder to self:** run `terraform destroy` when not actively working on this, since AWS bills hourly regardless of usage

---

## How to Run This Yourself

```bash
# 1. Clone the repo
git clone https://github.com/marade19/Devops-final-project-bloomy.git
cd Devops-final-project-bloomy

# 2. Build infrastructure
cd terraform
terraform init
terraform apply

# 3. Deploy apps
cd ../ansible
ansible-playbook -i inventory.ini playbook.yml

# 4. Or just push to GitHub and let Jenkins do all of the above automatically
```
