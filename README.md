# Awful

The worst AWS command-line tool in the world.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'awful'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install awful

## Usage

```
$ for x in `ls bin`; do bin/$x help; done

Commands:
  ami delete NAME          # delete AMI
  ami help [COMMAND]       # Describe available commands or one specific command
  ami last NAME            # get last AMI matching NAME
  ami ls [PATTERN]         # list AMIs
  ami tags ID [KEY=VALUE]  # tag an image, or print tags

Options:
  -e, [--env=ENV]        # Load environment variables from file
  -o, [--owners=OWNERS]  # List images with this owner
                         # Default: self

Commands:
  asg create [FILE]            # create a new auto-scaling group
  asg delete NAME              # delete autoscaling group
  asg dump NAME                # dump existing autoscaling group as yaml
  asg help [COMMAND]           # Describe available commands or one specific command
  asg instances                # list instance IDs for instances in groups matching NAME
  asg ips NAME                 # list IPs for instances in groups matching NAME
  asg ls [PATTERN]             # list autoscaling groups with name matching PATTERN
  asg ssh NAME [ARGS]          # ssh to an instance for this autoscaling group
  asg stop NAME [NUMBER]       # stop NUMBER instances in group NAME
  asg terminate NAME [NUMBER]  # terminate NUMBER instances in group NAME
  asg update NAME [FILE]       # update existing auto-scaling group

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  ec2 addresses          # list elastic IP addresses
  ec2 allocate           # allocate a new elastic IP address
  ec2 associate NAME IP  # associate a public ip with an instance
  ec2 create NAME        # run new EC2 instance
  ec2 delete NAME        # terminate a running instance
  ec2 dns NAME           # get public DNS for named instance
  ec2 dump NAME          # dump EC2 instance with id or tag NAME as yaml
  ec2 help [COMMAND]     # Describe available commands or one specific command
  ec2 ls [PATTERN]       # list EC2 instances [with id or tags matching PATTERN]
  ec2 start NAME         # start a running instance
  ec2 stop NAME          # stop a running instance
  ec2 update NAME        # update an existing instance

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  elb create NAME        # create new load-balancer
  elb delete NAME        # delete load-balancer
  elb dns NAME           # get DNS name for load-balancers matching NAME
  elb dump NAME          # dump VPC with id or tag NAME as yaml
  elb health_check NAME  # set health-check
  elb help [COMMAND]     # Describe available commands or one specific command
  elb instances NAME     # list instances and states for elb NAME
  elb ls [PATTERN]       # list vpcs [with any tags matching PATTERN]

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  lc clean NAME [NUM]    # delete oldest NUM launch configs matching NAME
  lc create NAME [FILE]  # create a new launch configuration
  lc delete NAME         # delete launch configuration
  lc dump NAME           # dump existing launch_configuration as yaml
  lc help [COMMAND]      # Describe available commands or one specific command
  lc latest              # latest
  lc ls [PATTERN]        # list launch configs with name matching PATTERN

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  rds dns NAME        # show DNS name and port for DB instance NAME
  rds dump NAME       # dump DB instance matching NAME
  rds help [COMMAND]  # Describe available commands or one specific command
  rds ls [NAME]       # list DB instances matching NAME

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  route dump NAME       # dump route with id or tag NAME as yaml
  route help [COMMAND]  # Describe available commands or one specific command
  route ls [PATTERN]    # list routes

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  sg dump NAME       # dump security group with NAME as yaml
  sg help [COMMAND]  # Describe available commands or one specific command
  sg ls [NAME]       # list security groups [matching NAME]

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  subnet create NAME     # create subnet
  subnet delete NAME     # delete subnet with name or ID
  subnet dump NAME       # dump subnet with id or tag NAME as yaml
  subnet help [COMMAND]  # Describe available commands or one specific command
  subnet ls [PATTERN]    # list subnets [with any tags matching PATTERN]

Options:
  -e, [--env=ENV]  # Load environment variables from file

Commands:
  vpc dump NAME       # dump VPC with id or tag NAME as yaml
  vpc help [COMMAND]  # Describe available commands or one specific command
  vpc ls [PATTERN]    # list vpcs [with any tags matching PATTERN]

Options:
  -e, [--env=ENV]  # Load environment variables from file
```
