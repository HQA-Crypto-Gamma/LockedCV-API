# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Sequel model for accounts table
  class Account < Sequel::Model(:accounts)
    plugin :uuid, field: :id
    plugin :timestamps
    plugin :association_dependencies
    plugin :whitelist_security
    set_allowed_columns :username, :email, :phone_number, :password

    one_to_many :attachments, class: :'LockedCV::Attachment', key: :account_id
    many_to_many :system_roles,
                 class: :'LockedCV::Role',
                 join_table: :accounts_roles,
                 left_key: :account_id,
                 right_key: :role_id
    add_association_dependencies attachments: :destroy

    def system_role?(role_name)
      system_roles_dataset.where(name: role_name).any?
    end

    def admin?
      system_role?('admin')
    end

    def member?
      system_role?('member')
    end

    # Plaintext username - direct access to DB column
    def username
      self[:username]
    end

    def username=(value)
      self[:username] = value
    end

    # PII - Email
    def email
      SecureDB.decrypt(self[:email_secure])
    end

    def email=(plaintext)
      self[:email_secure] = SecureDB.encrypt(plaintext)
      self[:email_hash] = SecureDB.hash(plaintext)
    end

    # PII - Phone Number (optional)
    def phone_number
      return nil if self[:phone_number_secure].nil?

      SecureDB.decrypt(self[:phone_number_secure])
    end

    def phone_number=(plaintext)
      if plaintext.nil?
        self[:phone_number_secure] = nil
        self[:phone_number_hash] = nil
      else
        self[:phone_number_secure] = SecureDB.encrypt(plaintext)
        self[:phone_number_hash] = SecureDB.hash(plaintext)
      end
    end

    def password=(new_password)
      self.password_digest = Password.digest(new_password)
    end

    def password?(try_password)
      digest = Password.from_digest(password_digest)
      digest.correct?(try_password)
    rescue StandardError
      false
    end

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'account',
            attributes: {
              id:,
              username:,
              email:,
              phone_number:
            }
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
