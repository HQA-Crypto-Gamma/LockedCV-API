# frozen_string_literal: true

require 'rake/testtask'
require './require_app'

task default: :spec

desc 'Tests API specs only'
task :api_spec do
  sh 'ruby spec/integration/api_spec.rb'
end

desc 'Test all the specs'
Rake::TestTask.new(:spec) do |t|
  t.pattern = 'spec/{integration,unit}/**/*_spec.rb'
  t.warning = false
end

desc 'Runs rubocop on tested code'
task style: %i[spec audit] do
  mkdir_p 'tmp'
  sh({ 'RUBOCOP_CACHE_ROOT' => 'tmp/rubocop_cache' }, 'rubocop .')
end

desc 'Update vulnerabilities list and audit gems'
task :audit do
  advisory_db = 'tmp/ruby-advisory-db'
  mkdir_p 'tmp'
  audit_command = "bundle audit check --database #{advisory_db}"
  update_command = "#{audit_command} --update"

  next if system(update_command)

  raise 'Could not update ruby-advisory-db' unless Dir.exist?(advisory_db)

  warn 'Could not update ruby-advisory-db; using local advisory database'
  sh audit_command
end

desc 'Checks for release'
task release_check: %i[spec style audit] do
  puts "\nReady for release!"
end

desc 'Prints the current environment'
task :print_env do
  puts "Environment: #{ENV['RACK_ENV'] || 'development'}"
end

desc 'Run application console (pry)'
task console: :print_env do
  sh 'pry -r ./spec/test_load_all'
end

namespace :run do
  desc 'Run API in development mode'
  task dev: [:print_env] do
    sh 'puma -p 9000'
  end
end

namespace :db do
  desc 'Load nothing by default'
  task :load do
    require_app(nil) # load nothing by default
    require 'sequel'

    Sequel.extension :migration
    @app = LockedCV::Api
  end

  desc 'Load all models'
  task :load_models do
    require_app(%w[models policies services])
    @app = LockedCV::Api
  end

  desc 'Run migrations'
  task migrate: %i[load print_env] do
    puts 'Migrating database to latest'
    Sequel::Migrator.run(@app.DB, 'db/migrations')
  end

  desc 'Destroy data in database; maintain tables'
  task delete: :load_models do
    LockedCV::MaskedItem.dataset.destroy
    LockedCV::MaskedAttachment.dataset.destroy
    LockedCV::SensitiveData.dataset.destroy
    LockedCV::AttachmentPermission.dataset.destroy
    LockedCV::Attachment.dataset.destroy
    @app.DB[:accounts_roles].delete
    LockedCV::Role.dataset.destroy
    LockedCV::Account.dataset.destroy
  end

  desc 'Reset seed tracking'
  task reset_seeds: :load do
    @app.DB[:schema_seeds].delete if @app.DB.tables.include?(:schema_seeds)
  end

  desc 'Delete uploaded files for the current local environment'
  task clear_storage: :load_models do
    if @app.environment == :production
      puts 'Cannot wipe production storage!'
      return
    end

    FileUtils.rm_rf(LockedCV::ResolveAttachmentPath::STORAGE_ROOT)
    puts "Deleted #{LockedCV::ResolveAttachmentPath::STORAGE_ROOT}"
  end

  desc 'Delete dev or test database file'
  task drop: :load do
    if @app.environment == :production
      puts 'Cannot wipe production database!'
      return
    end

    db_filename = "db/local/#{LockedCV::Api.environment}.db"
    FileUtils.rm(db_filename)
    puts "Deleted #{db_filename}"
  end

  desc 'Seeds the development database'
  task seed: :load_models do
    require 'sequel/extensions/seed'

    Sequel.extension :seed
    Sequel::Seed.setup(@app.environment)
    Sequel::Seeder.apply(@app.DB, 'db/seeds')
  end

  desc 'Bootstrap an admin: ensure roles, create-or-find USERNAME, grant admin'
  task bootstrap_admin: :load_models do
    require 'io/console'

    username = ENV.fetch('USERNAME', nil).to_s.strip
    email = ENV.fetch('EMAIL', nil).to_s.strip
    abort 'USERNAME=<username> required' if username.empty?

    LockedCV::Role::SYSTEM_ROLES.each { |name| LockedCV::Role.find_or_create(name:) }
    puts "Roles ensured: #{LockedCV::Role::SYSTEM_ROLES.join(', ')}"

    account = LockedCV::Account.first(username:)
    if account.nil?
      abort 'EMAIL=<email> required when creating a new account' if email.empty?

      password =
        if $stdin.tty?
          print 'Password (input hidden): '
          input = $stdin.noecho(&:gets).to_s.chomp
          puts ''
          input
        else
          warn '(no TTY -- reading password from stdin without echo masking)'
          $stdin.gets.to_s.chomp
        end
      abort 'Password must be at least 8 characters' if password.length < 8

      account = LockedCV::CreateAccountService.call(
        account_data: { username:, email:, password: }
      )
      puts "+ Created account #{username} (id=#{account.id})"
    else
      puts "- Account #{username} already exists (id=#{account.id})"
    end

    result = LockedCV::SetSystemRoleService.call(account:, role_name: 'admin')
    if result.created?
      puts "  + granted 'admin'"
    else
      puts "  - already has 'admin'"
    end
  end

  desc 'Delete all data and reseed'
  task reseed: %i[delete clear_storage reset_seeds seed]
end

namespace :newkey do
  desc 'Create sample cryptographic key for database'
  task :db do
    require_app('lib', config: false)
    puts "DB_KEY: #{LockedCV::SecureDB.generate_key}"
  end

  desc 'Create sample cryptographic key for HMAC lookup hashing'
  task :hash do
    require_app('lib', config: false)
    puts "HASH_KEY: #{LockedCV::SecureDB.generate_key}"
  end

  desc 'Create sample cryptographic key for encrypted auth tokens'
  task :msg do
    require_app('lib', config: false)
    puts "MSG_KEY: #{LockedCV::AuthToken.generate_key}"
  end

  desc 'Create sample Ed25519 keypair for signed client requests'
  task :signing do
    require_app('lib', config: false)
    keypair = LockedCV::SignedRequest.generate_keypair
    puts "SIGNING_KEY: #{keypair[:signing_key]}"
    puts "VERIFY_KEY: #{keypair[:verify_key]}"
  end
end
