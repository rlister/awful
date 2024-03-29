# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'awful/version'

Gem::Specification.new do |spec|
  spec.name          = "awful"
  spec.version       = Awful::VERSION
  spec.authors       = ["Ric Lister"]
  spec.email         = ["rlister+gh@gmail.com"]
  spec.summary       = %q{Simple AWS command-line tool.}
  spec.description   = %q{AWS cmdline and yaml loader.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = Dir['lib/*'] + Dir['bin/*']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"

  spec.add_dependency('thor')
  spec.add_dependency('dotenv')
  spec.add_dependency('ox')

  spec.add_dependency('aws-sdk-acm')
  spec.add_dependency('aws-sdk-autoscaling')
  spec.add_dependency('aws-sdk-cloudformation')
  spec.add_dependency('aws-sdk-dynamodb')
  spec.add_dependency('aws-sdk-ec2')
  spec.add_dependency('aws-sdk-ecr')
  spec.add_dependency('aws-sdk-elasticloadbalancingv2')
  spec.add_dependency('aws-sdk-iam')
  spec.add_dependency('aws-sdk-rds')
  spec.add_dependency('aws-sdk-s3')
  spec.add_dependency('aws-sdk-secretsmanager')
  spec.add_dependency('aws-sdk-ssm')
end
