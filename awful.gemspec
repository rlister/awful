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

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake"

  spec.add_dependency('aws-sdk', '>= 2.7.2')
  spec.add_dependency('thor', '< 0.19.2')
  spec.add_dependency('dotenv')
end