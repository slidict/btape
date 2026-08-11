# frozen_string_literal: true

require_relative 'lib/btape/version'

Gem::Specification.new do |spec|
  spec.name = 'btape'
  spec.version = Btape::VERSION
  spec.authors = ['btape contributors']
  spec.summary = 'Record browser automation scripts as animated GIFs'
  spec.description = 'A small VHS-inspired browser recorder driven by .tape files.'
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/slidict/btape'
  spec.required_ruby_version = '>= 3.1'
  spec.files = Dir['lib/**/*', 'exe/*', 'README.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = ['btape']
  spec.require_paths = ['lib']

  spec.add_dependency 'chunky_png', '~> 1.4'
  spec.add_dependency 'ferrum', '~> 0.16'

  # Where a published gem came from, so it can be audited without guessing.
  # The homepage is set above and needs no metadata entry of its own; adding
  # one that repeats source_code_uri only makes rubygems drop one of them.
  # Releases are drafted from merged pull requests, so the release list is
  # the changelog.
  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/releases",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'documentation_uri' => "#{spec.homepage}#readme",
    'rubygems_mfa_required' => 'true'
  }
end
