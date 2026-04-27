# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Sequel model for sensitive_data table
  class SensitiveData < Sequel::Model(:sensitive_data)
    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :first_name, :last_name, :phone_number, :birthday, :email, :address, :identification_numbers

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id

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

    def birthday
      SecureDB.decrypt(birthday_secure)
    end

    def birthday=(plaintext)
      self.birthday_secure = SecureDB.encrypt(plaintext&.to_s)
    end

    def email
      SecureDB.decrypt(email_secure)
    end

    def email=(plaintext)
      self.email_secure = SecureDB.encrypt(plaintext)
    end

    def address
      SecureDB.decrypt(address_secure)
    end

    def address=(plaintext)
      self.address_secure = SecureDB.encrypt(plaintext)
    end

    def identification_numbers
      SecureDB.decrypt(identification_numbers_secure)
    end

    def identification_numbers=(plaintext)
      self.identification_numbers_secure = SecureDB.encrypt(plaintext)
    end

    # rubocop:disable Metrics/MethodLength
    def to_json(options = {})
      JSON(
        {
          data: {
            type: 'sensitive_data',
            attributes: {
              id:,
              first_name:,
              last_name:,
              phone_number:,
              birthday:,
              email:,
              address:,
              identification_numbers:
            }
          }
        },
        options
      )
    end
    # rubocop:enable Metrics/MethodLength
  end
end
