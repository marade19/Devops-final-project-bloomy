pipeline {
    agent any

    environment {
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main', url: 'https://github.com/marade19/devops-final-project-bloomy.git'
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
