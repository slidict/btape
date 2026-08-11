require_relative "lib/btape/version"

Gem::Specification.new do |spec|
  spec.name = "btape"
  spec.version = Btape::VERSION
  spec.authors = ["btape contributors"]
  spec.summary = "Record browser automation scripts as animated GIFs"
  spec.description = "A small VHS-inspired browser recorder driven by .tape files."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["btape"]
  spec.require_paths = ["lib"]

  spec.add_dependency "chunky_png", "~> 1.4"
  spec.add_dependency "ferrum", "~> 0.16"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end

