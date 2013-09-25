# encoding: utf-8

require 'rubygems'
require 'bundler'
begin
  Bundler.setup(:default, :development)
rescue Bundler::BundlerError => e
  $stderr.puts e.message
  $stderr.puts "Run `bundle install` to install missing gems"
  exit e.status_code
end
require 'rake'

require 'jeweler'
Jeweler::Tasks.new do |gem|
  # gem is a Gem::Specification... see http://docs.rubygems.org/read/chapter/20 for more options
  gem.name = "endicia"
  gem.homepage = "http://github.com/ideaoforder/endicia"
  gem.license = "MIT"
  gem.summary = %Q{Uses the Endicia API to create USPS postage labels}
  gem.description = %Q{Uses the Endicia API to create USPS postage labels. Requires account id, partner id, and passphrase. Exports to a variety of image types.}
  gem.email = "mark@sitesteaders.com"
  gem.authors = ["Mark Dickson"]
  # dependencies defined in Gemfile
end
Jeweler::RubygemsDotOrgTasks.new

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

namespace(:test) do
  Rake::TestTask.new(:integration) do |test|
    test.libs << 'lib' << 'test'
    test.pattern = 'test/integration.rb'
    test.verbose = true
  end
  
  desc "Run unit and integration tests"
  task(:all => ['test', 'test:integration'])
end  

task :default => :test

require 'rdoc/task'
Rake::RDocTask.new do |rdoc|
  version = File.exist?('VERSION') ? File.read('VERSION') : ""

  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "endicia #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
