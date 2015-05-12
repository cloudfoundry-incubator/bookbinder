require 'fileutils'
require_relative '../lib/bookbinder'
require_relative '../template_app/app.rb'
require_relative 'fixtures/repo_fixture'

include Bookbinder::DirectoryHelperMethods

Dir[File.expand_path(File.join(File.dirname(__FILE__), 'helpers/*'))].each { |file| require_relative file }

RSpec.configure do |config|
  config.include Bookbinder::SpecHelperMethods

  config.order = 'random'
  config.color = true

  config.before do
    # awful hack to prevent tests that invoke middleman directly from polluting code that shells out to call it
    ENV['MM_ROOT'] = nil
  end

  config.before do
    allow_any_instance_of(Bookbinder::Pusher).to receive(:push) unless self.class.metadata[:enable_pusher]
  end

  config.mock_with :rspec do |mocks|
    mocks.yield_receiver_to_any_instance_implementation_blocks = true
  end
end

