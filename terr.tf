provider "aws" {
  region = "us-east-1"
}

# Fetch the default VPC
data "aws_vpc" "default" {
  default = true
}

# Create a security group for our instances
resource "aws_security_group" "app_security_group" {
  name        = "app-security-group"
  description = "Security group for Flask and Ansible servers"
  vpc_id      = data.aws_vpc.default.id

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access for Flask application
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Application port access
  ingress {
    from_port   = 4080
    to_port     = 4080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "AppSecurityGroup"
  }
}

# EC2 instance for Flask App Server (Amazon Linux)
resource "aws_instance" "flask_server" {
  ami                    = "ami-0c02fb55956c7d316"  # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = "ansible"  # Replace with your key pair
  vpc_security_group_ids = [aws_security_group.app_security_group.id]
  
  tags = {
    Name = "FlaskAppServer"
  }
}

# EC2 instance for Ansible Server (Amazon Linux)
resource "aws_instance" "ansible_server" {
  ami                    = "ami-0c02fb55956c7d316"  # Amazon Linux 2 AMI
  instance_type          = "t2.micro"
  key_name               = "ansible"
  vpc_security_group_ids = [aws_security_group.app_security_group.id]
  
  # Ensure Ansible instance is created after the Flask server
  depends_on = [aws_instance.flask_server]
  
  # Upload the private key file to Ansible server
  provisioner "file" {
    source      = "ansible.pem"  # Your local key file
    destination = "/home/ec2-user/ansible.pem"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("ansible.pem")
      host        = self.public_ip
    }
  }
  
  # Create the playbook file for Flask deployment
  provisioner "file" {
    content     = <<-EOF
    - hosts: all
      user: ec2-user
      become: yes
      vars:
        app_port: 4080  # Change this value if needed
    
      tasks:
        - name: Install required system packages
          yum:
            name:
              - python3
              - python3-pip
              - git
            state: present

        - name: Enable and install nginx using amazon-linux-extras
          shell: |
            sudo amazon-linux-extras enable nginx1
            sudo yum clean metadata
            sudo yum install -y nginx

        - name: Ensure pip is installed
          pip:
            name: pip
            state: latest
            executable: pip3

        - name: Install Python dependencies
          pip:
            name:
              - flask
              - gunicorn
              - joblib
              - scikit-learn
            executable: pip3

        - name: Clone Flask application from GitHub
          git:
            repo: https://github.com/manojmanu9441/cardio_heart_detection.git
            dest: /home/ec2-user/cardio_heart_detection
            version: main

        - name: Configure Gunicorn systemd service
          copy:
            dest: /etc/systemd/system/gunicorn.service
            content: |
              [Unit]
              Description=Gunicorn instance to serve Flask app
              After=network.target
              
              [Service]
              User=ec2-user
              Group=ec2-user
              WorkingDirectory=/home/ec2-user/cardio_heart_detection
              Environment="FLASK_RUN_PORT={{ app_port }}"
              ExecStart=/usr/local/bin/gunicorn --workers 3 --bind 0.0.0.0:{{ app_port }} main:app
              
              [Install]
              WantedBy=multi-user.target

        - name: Reload systemd and enable Gunicorn
          systemd:
            name: gunicorn
            enabled: yes
            state: restarted
            daemon_reload: yes

        - name: Configure Nginx for Flask
          copy:
            dest: /etc/nginx/conf.d/flaskapp.conf
            content: |
              server {
                  listen 80;
                  server_name _;

                  location / {
                      proxy_pass http://127.0.0.1:{{ app_port }};
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                      proxy_set_header X-Forwarded-Proto $scheme;
                  }
              }

        - name: Restart Nginx
          systemd:
            name: nginx
            state: restarted
            enabled: yes
    EOF
    destination = "/home/ec2-user/deploy_flask_app.yml"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("ansible.pem")
      host        = self.public_ip
    }
  }

  # Configure the Ansible server
  provisioner "remote-exec" {
    inline = [
      "sudo amazon-linux-extras install ansible2 -y",
      "sudo yum install -y git",
      "chmod 400 /home/ec2-user/ansible.pem",
      
      # Create inventory file with proper SSH key configuration
      "echo '[flask_servers]' > /home/ec2-user/hosts",
      "echo '${aws_instance.flask_server.private_ip} ansible_user=ec2-user ansible_ssh_private_key_file=/home/ec2-user/ansible.pem ansible_ssh_common_args=\"-o StrictHostKeyChecking=no\"' >> /home/ec2-user/hosts",
      
      # Test connection
      "ansible -i /home/ec2-user/hosts all -m ping",
      
      # Run the playbook to deploy the Flask application
      "ansible-playbook -i /home/ec2-user/hosts /home/ec2-user/deploy_flask_app.yml"
    ]
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("ansible.pem")
      host        = self.public_ip
    }
  }
  
  tags = {
    Name = "AnsibleServer"
  }
}

# Output the public IPs and DNS for easy access
output "flask_server_public_ip" {
  value = aws_instance.flask_server.public_ip
}

output "flask_server_public_dns" {
  value = aws_instance.flask_server.public_dns
}

output "ansible_server_public_ip" {
  value = aws_instance.ansible_server.public_ip
}