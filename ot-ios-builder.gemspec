# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "ot-ios-builder"
  s.version = "0.7.9.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Luke Redpath", "Nick Peelman", "Olivier Larivain"]
  s.date = "2013-01-18"
  s.email = ["luke@lukeredpath.co.uk", "nick@peelman.us", "olarivain@opentable.com"]
  s.extra_rdoc_files = ["README.md", "LICENSE", "CHANGES.md"]
  s.files = ["CHANGES.md", "LICENSE", "README.md", "lib/beta_builder/archived_build.rb", "lib/beta_builder/build_output_parser.rb", "lib/beta_builder/deployment_strategies/testflight.rb", "lib/beta_builder/deployment_strategies/web.rb", "lib/beta_builder/deployment_strategies.rb", "lib/beta_builder/release_strategies/git.rb", "lib/beta_builder/release_strategies.rb", "lib/beta_builder.rb", "lib/ot-ios-builder.rb"]
  s.homepage = "http://github.com/opentable/betabuilder"
  s.rdoc_options = ["--main", "README.md"]
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.24"
  s.summary = "A set of Rake tasks and utilities for building and releasing iOS apps"

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<CFPropertyList>, ["~> 2.0.0"])
      s.add_runtime_dependency(%q<uuid>, ["~> 2.3.1"])
      s.add_runtime_dependency(%q<rest-client>, ["~> 1.6.1"])
      s.add_runtime_dependency(%q<json>, [">= 0"])
    else
      s.add_dependency(%q<CFPropertyList>, ["~> 2.0.0"])
      s.add_dependency(%q<uuid>, ["~> 2.3.1"])
      s.add_dependency(%q<rest-client>, ["~> 1.6.1"])
      s.add_dependency(%q<json>, [">= 0"])
    end
  else
    s.add_dependency(%q<CFPropertyList>, ["~> 2.0.0"])
    s.add_dependency(%q<uuid>, ["~> 2.3.1"])
    s.add_dependency(%q<rest-client>, ["~> 1.6.1"])
    s.add_dependency(%q<json>, [">= 0"])
  end
end
