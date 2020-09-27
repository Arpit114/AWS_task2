provider "aws" {
	region = "ap-south-1"
	profile = "arpit"
}

//Generating Key pair

resource "tls_private_key" "key-pair" {
algorithm = "RSA"
}

resource "aws_key_pair" "key" {
	depends_on = [ tls_private_key.key-pair ,]
	key_name = "arpitT2"
	public_key = tls_private_key.key-pair.public_key_openssh
}


//Generating Security Group

resource "aws_security_group" "task-security" {
    depends_on = [aws_key_pair.key,]
	name = "task-security"
	description = "SSH ,HTTP and NFS"

	ingress {
		description = "SSH"
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = [ "0.0.0.0/0" ]
	}

	ingress {
		description = "HTTP"
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = [ "0.0.0.0/0" ]
	}
	
	ingress {
		description = "NFS"
		from_port   = 2049
		to_port     = 2049
		protocol    = "tcp"
		cidr_blocks = [ "0.0.0.0/0" ]
    }

	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "task-security"
	}
}


// Launching The Instance
resource "aws_instance" "task2" {
	depends_on = [aws_security_group.task-security,]
	ami           = "ami-0447a12f28fddb066"
	instance_type = "t2.micro"
	key_name = aws_key_pair.key.key_name
	security_groups = [ "task-security" ]

// Connecting to the instance
	connection {
		type     = "ssh"
		user     = "ec2-user"
		private_key = tls_private_key.key-pair.private_key_pem
		host     = aws_instance.task2.public_ip
	}

// Installing the requirements
	provisioner "remote-exec" {
		inline = [
			"sudo yum install httpd  php git -y",
			"sudo systemctl restart httpd",
			"sudo systemctl enable httpd",
		]
	}

	tags = {
		Name = "task-2"
	}

}


// Launching a EFS Storage
resource "aws_efs_file_system" "nfs" {
	depends_on =  [ aws_security_group.task-security , aws_instance.task2 ] 
	creation_token = "nfs"


	tags = {
		Name = "nfs"
	}
}

// Mounting the EFS volume onto the VPC's Subnet

resource "aws_efs_mount_target" "target" {
	depends_on =  [ aws_efs_file_system.nfs,] 
	file_system_id = aws_efs_file_system.nfs.id
	subnet_id      = aws_instance.task2.subnet_id
	security_groups = ["${aws_security_group.task-security.id}"]
}


output "task-instance-ip" {
	value = aws_instance.task2.public_ip
}


//Connect to instance again
resource "null_resource" "remote-connect"  {

	depends_on = [ aws_efs_mount_target.target,]

	connection {
		type     = "ssh"
		user     = "ec2-user"
		private_key = tls_private_key.key-pair.private_key_pem
		host     = aws_instance.task2.public_ip
	}	
	
// Mounting the EFS on the folder and pulling the code from github
 provisioner "remote-exec" {
      inline = [
        "sudo echo ${aws_efs_file_system.nfs.dns_name}:/var/www/html efs defaults,_netdev 0 0 >> sudo /etc/fstab",
        "sudo mount  ${aws_efs_file_system.nfs.dns_name}:/  /var/www/html",
		"sudo git clone https://github.com/Arpit114/AWS_task2.git /var/www/html/"
    ]
  }
}



//Connect to the webserver to see the website
resource "null_resource" "webpage"  {

depends_on = [null_resource.remote-connect,]

	provisioner "local-exec" {
	    command = "start chrome ${aws_instance.task2.public_ip}"
  	}
}


