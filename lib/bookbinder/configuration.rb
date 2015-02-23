require 'git'
require_relative 'git_hub_repository'
require_relative 'remote_yaml_credential_provider'

module Bookbinder
  class Configuration

    CURRENT_SCHEMA_VERSION = '1.0.0'
    STARTING_SCHEMA_VERSION = '1.0.0'

    CredentialKeyError = Class.new(StandardError)
    ConfigSchemaUnsupportedError = Class.new(StandardError)

    class AwsCredentials
      REQUIRED_KEYS = %w(access_key secret_key green_builds_bucket)

      def initialize(cred_hash)
        @creds = cred_hash
      end

      REQUIRED_KEYS.each do |method_name|
        define_method(method_name) do
          begin
            creds.fetch(method_name)
          rescue KeyError => e
            raise CredentialKeyError, e
          end
        end
      end

      private

      attr_reader :creds
    end

    class CfCredentials
      def self.environment_keys
        %w(production staging).flat_map {|env| ["#{env}_space", "#{env}_host"] }
      end

      REQUIRED_KEYS = %w(api_endpoint organization app_name)
      OPTIONAL_KEYS = %w(username password) + environment_keys

      def initialize(cred_hash, environment)
        @creds = cred_hash
        @environment = environment
      end

      REQUIRED_KEYS.each do |method_name|
        define_method(method_name) do
          fetch(method_name)
        end
      end

      OPTIONAL_KEYS.each do |method_name|
        define_method(method_name) do
          creds.fetch(method_name, nil)
        end
      end

      def download_archive_before_push?
        production?
      end

      def push_warning
        if production?
          'Warning: You are pushing to CF Docs production. Be careful.'
        end
      end

      def routes
        fetch(host_key) if correctly_formatted_domain_and_routes?(host_key)
      end

      def flat_routes
        routes.reduce([]) do |all_routes, domain_apps|
          domain, apps = domain_apps
          all_routes + apps.map { |app| [domain, app] }
        end
      end

      def space
        fetch(space_key)
      end

      private

      attr_reader :creds, :environment

      def production?
        environment == 'production'
      end

      def fetch(key)
        creds.fetch(key)
      rescue KeyError => e
        raise CredentialKeyError, e
      end

      def correctly_formatted_domain_and_routes?(deploy_environment)
        routes_hash = fetch(deploy_environment)
        domains = routes_hash.keys
        domains.each { |domain| correctly_formatted_domain?(domain, routes_hash) }
      end

      def correctly_formatted_domain?(domain, routes_hash)
        raise 'Each domain in credentials must be a single string.' unless domain.is_a? String
        raise "Domain #{domain} in credentials must contain a web extension, e.g. '.com'." unless domain.include?('.')
        raise "Did you mean to add a list of hosts for domain #{domain}? Check your credentials.yml." unless routes_hash[domain]
        raise "Hosts in credentials must be nested as an array under the desired domain #{domain}." unless routes_hash[domain].is_a? Array
        raise "Did you mean to provide a hostname for the domain #{domain}? Check your credentials.yml." if routes_hash[domain].any?(&:nil?)
      end

      def host_key
        "#{environment}_host"
      end

      def space_key
        "#{environment}_space"
      end
    end

    attr_reader :schema_version, :schema_major_version, :schema_minor_version, :schema_patch_version

    def initialize(logger, config_hash)
      @logger = logger
      @config = config_hash
    end

    CONFIG_REQUIRED_KEYS = %w(book_repo public_host pdf)
    CONFIG_OPTIONAL_KEYS = %w(archive_menu dita_sections layout_repo versions pdf_index cred_repo)

    CONFIG_REQUIRED_KEYS.each do |method_name|
      define_method(method_name) do
        config.fetch(method_name)
      end
    end

    CONFIG_OPTIONAL_KEYS.each do |method_name|
      define_method(method_name) do
        config[method_name]
      end
    end

    def sections
      config.fetch('sections', [])
    end

    def has_option?(key)
      @config.has_key?(key)
    end

    def template_variables
      config.fetch('template_variables', {})
    end

    def aws_credentials
      @aws_creds ||= AwsCredentials.new(credentials.fetch('aws'))
    end

    def cf_staging_credentials
      @cf_staging_creds ||= CfCredentials.new(
        credentials.fetch('cloud_foundry'),
        'staging'
      )
    end

    def cf_production_credentials
      @cf_prod_creds ||= CfCredentials.new(
        credentials.fetch('cloud_foundry'),
        'production'
      )
    end

    def ==(o)
      (o.class == self.class) && (o.config == self.config)
    end

    alias_method :eql?, :==

    protected

    attr_reader :config

    private

    def credentials
      @credentials ||= RemoteYamlCredentialProvider.new(@logger, credentials_repository).credentials
    end

    def credentials_repository
      @credentials_repository ||= GitHubRepository.new(logger: @logger, full_name: cred_repo, git_accessor: Git)
    end
  end
end
