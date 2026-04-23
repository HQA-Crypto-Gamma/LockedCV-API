# frozen_string_literal: true

require 'json'
require 'sequel'

module LockedCV
  # Sequel model for sensitive_data table
  class SensitiveData < Sequel::Model(:sensitive_data)
    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :user_name, :phone_number, :birthday, :email, :address, :identification_numbers

    many_to_one :attachment, class: :'LockedCV::Attachment', key: :attachment_id

    # Secure getters and setters
    def user_name
      SecureDB.decrypt(user_name_secure)
    end

    def user_name=(plaintext)
      self.user_name_secure = SecureDB.encrypt(plaintext)
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
              user_name:,
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
