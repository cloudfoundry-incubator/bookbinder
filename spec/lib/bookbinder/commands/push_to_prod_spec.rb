require_relative '../../../../lib/bookbinder/commands/push_to_prod'
require_relative '../../../../lib/bookbinder/remote_yaml_credential_provider'
require_relative '../../../../lib/bookbinder/configuration'

require_relative '../../../helpers/middleman'
require_relative '../../../helpers/nil_logger'

module Bookbinder
  describe Commands::PushToProd do
    include SpecHelperMethods

    let(:book_repo) { 'my-user/fixture-book-title' }
    let(:build_number) { '17' }
    let(:config_hash) { {'book_repo' => book_repo, 'cred_repo' => 'whatever'} }

    let(:fake_dir) { double }
    let(:fake_distributor) { double(Distributor, distribute: nil) }

    let(:options) do
      {
          app_dir: fake_dir,
          build_number: build_number,

          aws_credentials: config.aws_credentials,
          cf_credentials: config.cf_credentials('production'),

          book_repo: book_repo,
      }
    end

    let(:logger) { NilLogger.new }
    let(:configuration_fetcher) { double('configuration_fetcher') }
    let(:config) { Configuration.new(logger, config_hash) }
    let(:command) { described_class.new(logger, configuration_fetcher) }

    before do
      fake_cred_repo = double(RemoteYamlCredentialProvider, credentials: {'aws' => {}, 'cloud_foundry' => {}})
      allow(RemoteYamlCredentialProvider).to receive(:new).and_return(fake_cred_repo)

      allow(Distributor).to receive(:build).and_return(fake_distributor)
      allow(Dir).to receive(:mktmpdir).and_return(fake_dir)
      allow(configuration_fetcher).to receive(:fetch_config).and_return(config)
    end

    it 'returns 0' do
      expect(command.run([build_number])).to eq(0)
    end

    it 'builds a distributor with the right options and asks it to distribute' do
      real_distributor = expect_to_receive_and_return_real_now(Distributor, :build, logger, options)
      expect(real_distributor).to receive(:distribute)

      command.run([build_number])
    end

    context 'when missing credential repo' do
      let (:section1) do
        {
            'repository'=> {
                'name'=> 'cloudfoundry/docs-cloudfoundry-concepts'
            },
            'directory'=> 'concepts'
        }
      end

      let(:section2) do
        {
            'repository' => {
                'name' => 'cloudfoundry/docs-cloudfoundry-foo'
            },
            'directory' => 'foo'
        }
      end

      let(:invalid_push_to_prod_config_hash) do
        {
            'book_repo' => 'my_book',
            'public_host' => 'public_host',
            'sections' => [section1, section2]
        }
      end
      let(:config) { Configuration.new(logger, invalid_push_to_prod_config_hash) }

      it 'raises missing credential key error' do
        expect { command.run([build_number]) }.to raise_error PushToProdValidator::MissingRequiredKeyError, /Your config.yml is missing required key\(s\). The require keys for this commands are /
      end
    end

  end
end
