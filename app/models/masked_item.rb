# frozen_string_literal: true

require 'sequel'

module LockedCV
  # Sequel model for values/rules applied to one masked attachment output.
  class MaskedItem < Sequel::Model(:masked_items)
    SOURCES = %w[sensitive_data regex manual].freeze

    plugin :timestamps
    plugin :whitelist_security
    set_allowed_columns :field_name, :value, :is_masked, :source

    many_to_one :masked_attachment, class: :'LockedCV::MaskedAttachment', key: :masked_attachment_id

    def validate
      super
      errors.add(:source, 'is unsupported') unless SOURCES.include?(source)
    end

    def value
      SecureDB.decrypt(value_secure)
    end

    def value=(plaintext)
      self.value_secure = SecureDB.encrypt(plaintext)
    end
  end
end
