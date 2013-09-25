# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{endicia}
  s.version = "0.3.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Mark Dickson", "Kurt Nelson"]
  s.date = %q{2013-09-23}
  s.description = %q{Uses the Endicia API to create USPS postage labels. Requires account id, partner id, and passphrase. Exports to a variety of image types.}
  s.email = %q{mark@sitesteaders.com}
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]

  s.files         = `git ls-files`.split($/)
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_paths = ["lib"]

  s.homepage = %q{http://github.com/ideaoforder/endicia}
  s.licenses = ["MIT"]
  s.require_paths = ["lib"]
  s.summary = %q{Uses the Endicia API to create USPS postage labels}

  s.add_dependency 'httparty'
  s.add_dependency 'bundler'
  s.add_dependency 'activesupport'
  s.add_dependency 'i18n'
  s.add_dependency 'builder'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'nokogiri'
end
