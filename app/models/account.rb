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
    set_allowed_columns :first_name, :last_name, :phone_number

    one_to_many :attachments, class: :'LockedCV::Attachment', key: :account_id
    add_association_dependencies attachments: :destroy

    # Secure getters and setters
    def first_name
      SecureDB.decrypt(first_name_secure)
    end

    def first_name=(plaintext)
      self.first_name_secure = SecureDB.encrypt(plaintext)
    end

    def last_name
      SecureDB.decrypt(last_name_secure)
    end

    def last_name=(plaintext)
      self.last_name_secure = SecureDB.encrypt(plaintext)
    end

    def phone_number
      SecureDB.decrypt(phone_number_secure)
    end

    def phone_number=(plaintext)
      self.phone_number_secure = SecureDB.encrypt(plaintext)
    end

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'account',
            attributes: {
              id:,
              first_name:,
              last_name:,
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
