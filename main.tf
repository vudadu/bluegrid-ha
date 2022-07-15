provider "aws" {
  access_key = "xxxxx"
  secret_key = "xxx"
  region     = "us-east-1"
}

data "aws_availability_zones" "all" {}

resource "aws_security_group" "web" {
  name = "ssh-http-access"

ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  
} 

# Security group for RDS
resource "aws_security_group" "RDS_allow_rule" {
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = ["${aws_security_group.web.id}"]
  }
  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "allow ec2"
  }

}


resource "aws_db_instance" "wordpress-sql" {
  allocated_storage    = 10
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0.28"
  instance_class       = "db.t2.micro"
  db_name                 = "mydb"
  username             = "blue"
  password             = "blueblue"
  #db_subnet_group_name = "my_database_subnet_group"
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot       = true

  vpc_security_group_ids = [aws_security_group.RDS_allow_rule.id]
}

## Creating Launch Configuration
resource "aws_launch_configuration" "lc1" {
  image_id               = "ami-0cff7528ff583bf9a"
  instance_type          = "t2.micro"
  security_groups        = ["${aws_security_group.web.id}"]
  #key_name               = "${var.key_name}"
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras install -y php7.2
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              cd /var/www/html
              wget https://wordpress.org/latest.tar.gz
              tar -xzf latest.tar.gz
              cp -r wordpress/* ./
              chmod -R 755 wp-content
              chown -R apache:apache wp-content
              cp wp-config-sample.php wp-config.php
              sudo sed -i 's/database_name_here/mydb/g' wp-config.php
              sudo sed -i 's/username_here/blue/g' wp-config.php
              sudo sed -i 's/password_here/blueblue/g' wp-config.php
              sudo sed -i 's/localhost/${aws_db_instance.wordpress-sql.endpoint}/g' wp-config.php
              EOF
  lifecycle {
    create_before_destroy = true
  }
}
## Creating AutoScaling Group
resource "aws_autoscaling_group" "asg1" {
  launch_configuration = "${aws_launch_configuration.lc1.id}"
  availability_zones = ["${data.aws_availability_zones.all.names[0]}"]
  min_size = 2
  max_size = 10
  load_balancers = ["${aws_elb.elb1.name}"]
  health_check_type = "ELB"
  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
}


## Security Group for ELB
resource "aws_security_group" "elb" {
  name = "terraform-example-elb"
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

### Creating ELB
resource "aws_elb" "elb1" {
  name = "terraform-asg-example"
  security_groups = ["${aws_security_group.elb.id}"]
  availability_zones = ["${data.aws_availability_zones.all.names[0]}"]
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }
}


# output "instance_ids" {
#     value = ["${aws_instance.web.*.public_ip}"]
# }
output "elb_dns_name" {
  value = "${aws_elb.elb1.dns_name}"
}