# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'reaper'

Gem::Specification.new do |spec|
  spec.name          = "reaper"
  spec.version       = Reaper::VERSION
  spec.authors       = ["Tinco Andringa"]
  spec.email         = ["tinco@phusion.nl"]
  spec.description   = %q{A process that can run as PID1 to reap orphan and zombie processes.}
  spec.summary       = %q{A process that can run as PID1 to reap orphan and zombie processes.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
