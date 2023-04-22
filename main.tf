terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>4.0"
    }
  }
  backend "s3" {
    bucket         = "load-balance-ec2"
    key            = "terraform.tfstate"
    dynamodb_table = "load-balance-ec2"
    region         = "us-east-1"
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-1"
}

# Provision the ec2 instance for NGINX
resource "aws_launch_configuration" "apache-server-2" {
  name = "apache-server-2"
  image_id        = "ami-007855ac798b5175e"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.general-sg.id]
  lifecycle {
    create_before_destroy = true
  }
  user_data              = <<-EOF
                #!/bin/bash
                sudo apt-get update
                sudo apt-get install apache2 -y
                sudo systemctl start apache2
                sudo systemctl enable apache2
                EOF
}

resource "aws_launch_configuration" "nginx-server-2" {
  name = "nginx-server-2"
  image_id        = "ami-007855ac798b5175e"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.general-sg.id]
  lifecycle {
    create_before_destroy = true
  }
  user_data              = file("./text.sh")
}


# Provision a load balancer
resource "aws_lb" "terraform-load-balance" {
  name               = "terraform-load-balance"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.general-sg.id]
  subnets            = ["subnet-0b7093fd341ea9132", "subnet-022b34ff2256dc4d0", "subnet-04753fdd10dd8e1b3"]
}

# Provision a target group
resource "aws_lb_target_group" "terraform-load-balance" {
  name        = "terraform-load-balance-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = "vpc-0958e011f386713ce"

  health_check {
    path = "/"
  }
}

# Provision a listener 
resource "aws_lb_listener" "terraform-load-balance" {
  load_balancer_arn = aws_lb.terraform-load-balance.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.terraform-load-balance.arn
  }
}

# Provision the security group
resource "aws_security_group" "general-sg" {
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]

  ingress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = "allow ssh"
    from_port        = 22
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = []
    self             = false
    to_port          = 22
    },
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = "allow http"
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 80
  }]
}

#Autoscaling group
resource "aws_autoscaling_group" "terraform-load-balance" {
  availability_zones = ["us-east-1a"]
  desired_capacity = 1
  max_size           = 1
  min_size           = 1
  launch_configuration = aws_launch_configuration.nginx-server-2.name
  tag {
    key                 = "Key"
    value               = "Value"
    propagate_at_launch = true
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 60
    }
    triggers = ["tag"]
  }
}
data "aws_ami" "terraform-load-balance" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }
}
