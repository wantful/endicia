require 'simplecov'
SimpleCov.start
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'rspec'
require 'pry'
require 'endicia'
# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

#VCR.configure do |c|
#  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
#  c.hook_into :webmock # or :fakeweb
#end

RSpec.configure do |config|

end
