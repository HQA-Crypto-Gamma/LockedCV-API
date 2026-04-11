# frozen_string_literal: true

require 'roda'
require 'figaro'
require 'sequel'

module LockedCV
  # Main API class, inherits from Roda
  # Configuration for the API
  class Api < Roda
    plugin :environments

    # load config secrets into local environment variables (ENV)
    Figaro.application = Figaro::Application.new(
      environment: environment,
      path: File.expand_path('config/secrets.yml')
    )
    Figaro.load

    # Make the environment variables accessible to other classes
    def self.config = Figaro.env

    # Connect and make the database accessible to other classes
    db_url = ENV.delete('DATABASE_URL')
    DB = Sequel.connect("#{db_url}?encoding=utf8")
    def self.DB = DB # rubocop:disable Naming/MethodName

    configure :development, :production do
      plugin :common_logger, $stderr
    end

    configure :development, :test do
      require 'pry'
    end
  end
end
